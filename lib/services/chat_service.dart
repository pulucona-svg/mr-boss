import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/message.dart';
import 'persistence_service.dart';

class ConversationSummary {
  final String userId;
  final String userName;
  final String? userEmail;
  final String? userPhotoUrl;
  final String lastMessageText;
  final DateTime lastMessageTimestamp;
  final int userUnreadCount;
  final int adminUnreadCount;
  final bool isUserTyping;
  final bool isAdminTyping;

  ConversationSummary({
    required this.userId,
    required this.userName,
    this.userEmail,
    this.userPhotoUrl,
    required this.lastMessageText,
    required this.lastMessageTimestamp,
    this.userUnreadCount = 0,
    this.adminUnreadCount = 0,
    this.isUserTyping = false,
    this.isAdminTyping = false,
  });

  factory ConversationSummary.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final ts = data['lastMessageTimestamp'];
    DateTime timestamp;
    if (ts is Timestamp) {
      timestamp = ts.toDate();
    } else if (ts is String) {
      timestamp = DateTime.tryParse(ts) ?? DateTime.now();
    } else {
      timestamp = DateTime.now();
    }

    return ConversationSummary(
      userId: doc.id,
      userName: data['userName'] as String? ?? 'User',
      userEmail: data['userEmail'] as String?,
      userPhotoUrl: data['userPhotoUrl'] as String?,
      lastMessageText: data['lastMessageText'] as String? ?? '',
      lastMessageTimestamp: timestamp,
      userUnreadCount: (data['userUnreadCount'] as num?)?.toInt() ?? 0,
      adminUnreadCount: (data['adminUnreadCount'] as num?)?.toInt() ?? 0,
      isUserTyping: data['isUserTyping'] == true,
      isAdminTyping: data['isAdminTyping'] == true,
    );
  }
}

class ChatService extends ChangeNotifier {
  static ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;

  @visibleForTesting
  static void resetInstance([ChatService? customInstance]) {
    _instance.disposeStreams();
    _instance = customInstance ?? ChatService._internal();
  }

  @visibleForTesting
  ChatService.testable();

  @visibleForTesting
  void setTestMessages(List<Message> testMessages, {int userUnreadCount = 0, String? currentUserId}) {
    _messages.clear();
    _messages.addAll(testMessages);
    _userUnreadCount = userUnreadCount;
    _currentUserId = currentUserId;
    notifyListeners();
  }

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseFunctions get _functions => FirebaseFunctions.instance;
  AudioPlayer? _audioPlayer;
  AudioPlayer get audioPlayer => _audioPlayer ??= AudioPlayer();

  final List<Message> _messages = [];
  bool _isAdminTyping = false;
  int _userUnreadCount = 0;
  String? _currentUserId;
  String? _currentUserName;
  String? _currentUserPhotoUrl;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _conversationSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _messagesSub;
  Timer? _typingDebounceTimer;

  List<Message> get messages => List.unmodifiable(_messages);
  bool get isAdminTyping => _isAdminTyping;
  int get unreadCount => _userUnreadCount > 0 ? _userUnreadCount : _messages.where((m) => !m.isMe && !m.isRead).length;

  ChatService._internal() {
    _restoreLocalMessages();
    _setupAuthListener();
  }

  void _setupAuthListener() {
    try {
      _authSubscription?.cancel();
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) {
          initForUser(
            userId: user.uid,
            userName: user.displayName ?? 'User',
            userPhotoUrl: user.photoURL,
          );
        } else {
          clear();
        }
      });

      final current = FirebaseAuth.instance.currentUser;
      if (current != null) {
        initForUser(
          userId: current.uid,
          userName: current.displayName ?? 'User',
          userPhotoUrl: current.photoURL,
        );
      }
    } catch (e) {
      debugPrint("ChatService _setupAuthListener error: $e");
    }
  }

  void clear() {
    _conversationSub?.cancel();
    _messagesSub?.cancel();
    _conversationSub = null;
    _messagesSub = null;
    _typingDebounceTimer?.cancel();
    _currentUserId = null;
    _currentUserName = null;
    _currentUserPhotoUrl = null;
    _userUnreadCount = 0;
    _isAdminTyping = false;
    _messages.clear();
    notifyListeners();
  }

  void disposeStreams() {
    _authSubscription?.cancel();
    _conversationSub?.cancel();
    _messagesSub?.cancel();
    _typingDebounceTimer?.cancel();
  }

  // -------------------------------------------------------------
  // LOCAL CACHE (OPTIONAL FALLBACK ONLY — NEVER AUTHORITATIVE)
  // -------------------------------------------------------------
  Future<void> _restoreLocalMessages() async {
    try {
      final json = PersistenceService().getJson('chat_messages');
      if (json != null) {
        _messages.clear();
        _messages.addAll(List<Message>.from((json as List).map((m) => Message.fromJson(m))));
        _cleanupOldLocalMessages();
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Local message restore error: $e");
    }
  }

  Future<void> _saveLocalMessages() async {
    try {
      await PersistenceService().setJson(
        'chat_messages',
        _messages.map((m) => m.toJson()).toList(),
      );
    } catch (e) {
      debugPrint("Local message save error: $e");
    }
  }

  /// 7-day retention applies ONLY to local offline cache, NEVER deletes from Firestore
  void _cleanupOldLocalMessages() {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    final initialCount = _messages.length;
    _messages.removeWhere((msg) => msg.timestamp.isBefore(sevenDaysAgo));
    if (_messages.length != initialCount) {
      _saveLocalMessages();
    }
  }

  // -------------------------------------------------------------
  // AUDIO PLAYBACK
  // -------------------------------------------------------------
  void _playSound(String fileName) async {
    try {
      await audioPlayer.play(AssetSource(fileName));
    } catch (e) {
      debugPrint("Sound play failed: $e");
    }
  }

  // -------------------------------------------------------------
  // INITIALIZATION FOR USER (HelpSupportScreen)
  // -------------------------------------------------------------
  void initForUser({
    required String userId,
    required String userName,
    String? userPhotoUrl,
  }) {
    if (_currentUserId == userId && _messagesSub != null) {
      // Already initialized for this user, just update identity fields if needed
      _currentUserName = userName;
      _currentUserPhotoUrl = userPhotoUrl;
      return;
    }

    _currentUserId = userId;
    _currentUserName = userName;
    _currentUserPhotoUrl = userPhotoUrl;

    _conversationSub?.cancel();
    _messagesSub?.cancel();

    final convRef = _firestore.collection('conversations').doc(userId);

    // 1. Ensure conversation document exists and listen to metadata & admin typing
    _conversationSub = convRef.snapshots().listen((snap) {
      if (snap.exists) {
        final data = snap.data();
        if (data != null) {
          final typing = data['isAdminTyping'] == true;
          final unread = (data['userUnreadCount'] as num?)?.toInt() ?? 0;
          bool changed = false;
          if (_isAdminTyping != typing) {
            _isAdminTyping = typing;
            changed = true;
          }
          if (_userUnreadCount != unread) {
            _userUnreadCount = unread;
            changed = true;
          }
          if (changed) notifyListeners();
        }
      }
    }, onError: (e) {
      debugPrint("Conversation listener error: $e");
    });

    // 2. Listen to messages subcollection in realtime
    _messagesSub = convRef
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen((snapshot) {
      final List<Message> remoteMessages = [];
      bool hasNewIncoming = false;

      for (var doc in snapshot.docs) {
        final msg = Message.fromFirestore(doc, currentUserId: userId, isAdmin: false);
        // Exclude messages deleted by user for themselves
        if (!msg.deletedFor.contains(userId)) {
          // Guard against snapshot race where Firestore write is still in flight
          // but message was already marked read in local memory
          if (!msg.isMe && !msg.isRead) {
            final localIndex = _messages.indexWhere((m) => m.id == msg.id);
            if (localIndex != -1 && _messages[localIndex].isRead) {
              remoteMessages.add(msg.copyWith(status: MessageStatus.read, isRead: true));
              continue;
            }
          }
          remoteMessages.add(msg);
        }

        // Mark incoming messages as delivered if still marked 'sent'
        if (!msg.isMe && msg.status == MessageStatus.sent) {
          doc.reference.update({'status': 'delivered'}).catchError((_) {});
        }
      }

      // Check if new incoming message was added
      if (remoteMessages.length > _messages.length) {
        final lastRemote = remoteMessages.last;
        if (!lastRemote.isMe) {
          hasNewIncoming = true;
        }
      }

      final remoteIds = remoteMessages.map((m) => m.id).toSet();
      final pendingLocal = _messages.where((m) => m.isMe && !remoteIds.contains(m.id)).toList();

      _messages.clear();
      _messages.addAll(remoteMessages);
      _messages.addAll(pendingLocal);
      _saveLocalMessages();
      notifyListeners();

      if (hasNewIncoming) {
        _playSound('received.mp3');
      }
    }, onError: (e) {
      debugPrint("Messages listener error: $e");
    });
  }

  // -------------------------------------------------------------
  // MARK ALL AS READ (USER SIDE)
  // -------------------------------------------------------------
  void markAllAsRead() {
    // 1. Immediately update in-memory message states for incoming admin messages
    for (int i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (!m.isMe && m.senderRole == 'admin' && m.status != MessageStatus.read) {
        _messages[i] = m.copyWith(
          status: MessageStatus.read,
          isRead: true,
        );
      }
    }
    _userUnreadCount = 0;
    _saveLocalMessages();
    notifyListeners();

    try {
      if (_currentUserId == null) return;
      final convRef = _firestore.collection('conversations').doc(_currentUserId);

      // 2. Clear user unread count on conversation metadata
      convRef.update({'userUnreadCount': 0}).catchError((e) {
        debugPrint("Error clearing user unread count: $e");
      });

      // 3. Mark unread admin messages as read in Firestore without an unindexed inequality query
      convRef.collection('messages')
          .where('senderRole', isEqualTo: 'admin')
          .get()
          .then((snap) {
        final unreadDocs = snap.docs.where((doc) {
          final data = doc.data();
          return data['status'] != 'read';
        }).toList();

        if (unreadDocs.isEmpty) return;

        const int batchLimit = 450;
        for (int i = 0; i < unreadDocs.length; i += batchLimit) {
          final chunk = unreadDocs.sublist(
            i,
            (i + batchLimit > unreadDocs.length) ? unreadDocs.length : i + batchLimit,
          );
          final batch = _firestore.batch();
          for (final doc in chunk) {
            batch.update(doc.reference, {'status': 'read'});
          }
          batch.commit().catchError((e) {
            debugPrint("Error committing read status batch: $e");
          });
        }
      }).catchError((e) {
        debugPrint("Error querying admin messages for read status update: $e");
      });
    } catch (e) {
      debugPrint("Error in markAllAsRead Firestore sync: $e");
    }
  }

  // -------------------------------------------------------------
  // SEND MESSAGE (USER SIDE)
  // -------------------------------------------------------------
  Future<void> sendMessage(
    String text, {
    File? imageFile,
    Message? replyTo,
    String? senderId,
    Map<String, dynamic>? metadata,
  }) async {
    final userId = _currentUserId ?? senderId ?? 'user';
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();
    final now = DateTime.now();

    String? imageUrl;
    if (imageFile != null) {
      imageUrl = await _uploadChatImage(imageFile, userId);
    }

    final message = Message(
      id: messageId,
      senderId: userId,
      senderRole: 'user',
      text: text,
      imageUrl: imageUrl,
      imageFile: imageFile,
      timestamp: now,
      isMe: true,
      type: (imageUrl != null || imageFile != null) ? MessageType.image : MessageType.text,
      status: MessageStatus.sent,
      replyToId: replyTo?.id,
      replyText: replyTo?.text,
      replyIsImage: replyTo?.type == MessageType.image,
      metadata: metadata,
    );

    // Optimistic local update & sound
    _messages.add(message);
    notifyListeners();
    _playSound('sent.mp3');

    final convRef = _firestore.collection('conversations').doc(userId);

    try {
      final batch = _firestore.batch();
      batch.set(convRef.collection('messages').doc(messageId), {
        'id': messageId,
        'senderId': userId,
        'senderRole': 'user',
        'text': text,
        'imageUrl': imageUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
        'replyToId': replyTo?.id,
        'replyText': replyTo?.text,
        'replyIsImage': replyTo?.type == MessageType.image,
        'isDeleted': false,
        'deletedFor': [],
        'metadata': metadata,
      });

      batch.set(convRef, {
        'userId': userId,
        'userName': _currentUserName ?? 'User',
        'userPhotoUrl': _currentUserPhotoUrl,
        'lastMessageText': text.isNotEmpty ? text : '📷 Photo',
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'adminUnreadCount': FieldValue.increment(1),
        'isUserTyping': false,
      }, SetOptions(merge: true));

      await batch.commit();
      _saveLocalMessages();
    } catch (e) {
      debugPrint("Error sending message to Firestore: $e");
      _messages.removeWhere((m) => m.id == messageId);
      notifyListeners();
      _saveLocalMessages();
      rethrow;
    }
  }

  /// Sends a structured comment report through the user's existing user-admin conversation.
  Future<void> sendCommentReport({
    required String userId,
    required String userName,
    String? userPhotoUrl,
    required String resourceId,
    required String resourceTitle,
    required String commentId,
    required String? commentAuthorId,
    required String commentAuthor,
    required String commentText,
    required String reason,
  }) async {
    initForUser(userId: userId, userName: userName, userPhotoUrl: userPhotoUrl);

    final metadata = {
      'reportType': 'comment_report',
      'materialId': resourceId,
      'materialTitle': resourceTitle,
      'commentId': commentId,
      'commentAuthorId': commentAuthorId,
      'commentAuthor': commentAuthor,
      'commentText': commentText,
      'reason': reason,
      'reportedBy': userId,
    };

    final summaryText = '🚩 [COMMENT REPORT]\nMaterial: $resourceTitle\nAuthor: $commentAuthor\nReason: $reason\nComment: "$commentText"';

    await sendMessage(
      summaryText,
      senderId: userId,
      metadata: metadata,
    );
  }

  // -------------------------------------------------------------
  // IMAGE UPLOAD TO IMAGEKIT VIA CLOUD FUNCTION
  // -------------------------------------------------------------
  Future<String?> _uploadChatImage(File file, String userId) async {
    try {
      final fileBytes = await file.readAsBytes();
      final base64File = base64Encode(fileBytes);
      final fileName = 'chat_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final result = await _functions.httpsCallable('uploadToImageKit').call({
        'file': base64File,
        'fileName': fileName,
        'folder': 'CHAT_IMAGES',
      });

      return result.data['url'] as String?;
    } catch (e) {
      debugPrint("Image upload error: $e");
      return null;
    }
  }

  // -------------------------------------------------------------
  // TYPING INDICATORS WITH DEBOUNCING
  // -------------------------------------------------------------
  void setUserTyping(bool isTyping) {
    if (_currentUserId == null) return;
    _typingDebounceTimer?.cancel();

    final convRef = _firestore.collection('conversations').doc(_currentUserId);

    convRef.update({'isUserTyping': isTyping}).catchError((_) {});

    if (isTyping) {
      // Auto-clear after 2.5 seconds of inactivity
      _typingDebounceTimer = Timer(const Duration(milliseconds: 2500), () {
        convRef.update({'isUserTyping': false}).catchError((_) {});
      });
    }
  }

  // -------------------------------------------------------------
  // REACTIONS, EDITING & DELETION
  // -------------------------------------------------------------
  void addReaction(String id, String emoji) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index != -1) {
      final oldMsg = _messages[index];
      if (oldMsg.isDeleted) return;
      _messages[index] = oldMsg.copyWith(reaction: emoji);
      notifyListeners();
    }

    if (_currentUserId != null) {
      _firestore
          .collection('conversations')
          .doc(_currentUserId)
          .collection('messages')
          .doc(id)
          .update({'reaction': emoji})
          .catchError((e) => debugPrint("Reaction update error: $e"));
    }
  }

  /// Delete for everyone (enforces 15-minute rule)
  void deleteMessage(String id) {
    deleteMessageForEveryone(id);
  }

  void deleteMessageForEveryone(String id) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index != -1) {
      final oldMsg = _messages[index];
      // 15-minute rule verification
      if (DateTime.now().difference(oldMsg.timestamp).inMinutes > 15) {
        debugPrint("Cannot delete message older than 15 minutes");
        return;
      }

      _messages[index] = oldMsg.copyWith(
        isDeleted: true,
        text: 'This message was deleted',
      );
      notifyListeners();
      _saveLocalMessages();
    }

    if (_currentUserId != null) {
      _firestore
          .collection('conversations')
          .doc(_currentUserId)
          .collection('messages')
          .doc(id)
          .update({
        'isDeleted': true,
        'text': 'This message was deleted',
      }).catchError((e) => debugPrint("Delete for everyone error: $e"));
    }
  }

  /// Delete for me (hides message for current user only)
  void deleteMessageForMe(String id) {
    _messages.removeWhere((m) => m.id == id);
    notifyListeners();
    _saveLocalMessages();

    if (_currentUserId != null) {
      _firestore
          .collection('conversations')
          .doc(_currentUserId)
          .collection('messages')
          .doc(id)
          .update({
        'deletedFor': FieldValue.arrayUnion([_currentUserId]),
      }).catchError((e) => debugPrint("Delete for me error: $e"));
    }
  }

  void editMessage(String id, String newText) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index != -1) {
      final oldMsg = _messages[index];
      if (DateTime.now().difference(oldMsg.timestamp).inMinutes > 15) return;

      _messages[index] = oldMsg.copyWith(text: newText);
      notifyListeners();
      _saveLocalMessages();
    }

    if (_currentUserId != null) {
      _firestore
          .collection('conversations')
          .doc(_currentUserId)
          .collection('messages')
          .doc(id)
          .update({'text': newText})
          .catchError((e) => debugPrint("Edit message error: $e"));
    }
  }

  void clearChat() {
    _messages.clear();
    _saveLocalMessages();
    notifyListeners();
  }

  // -------------------------------------------------------------
  // ADMIN CONVERSATION METHODS (Used by Admin screens)
  // -------------------------------------------------------------

  /// Stream all conversations for Admin Conversation List ordered by lastMessageTimestamp descending
  Stream<List<ConversationSummary>> streamAllConversations() {
    return _firestore
        .collection('conversations')
        .orderBy('lastMessageTimestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ConversationSummary.fromFirestore(doc))
            .toList());
  }

  /// Stream messages for a specific conversation (Admin Detail View)
  Stream<List<Message>> streamConversationMessages(String userId, {String? adminId}) {
    return _firestore
        .collection('conversations')
        .doc(userId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) {
      final list = <Message>[];
      for (var doc in snapshot.docs) {
        final msg = Message.fromFirestore(doc, currentUserId: adminId ?? 'admin', isAdmin: true);
        if (!msg.deletedFor.contains(adminId ?? 'admin')) {
          list.add(msg);
        }
      }
      return list;
    });
  }

  /// Mark conversation as read from Admin side
  Future<void> markAdminRead(String userId) async {
    final convRef = _firestore.collection('conversations').doc(userId);
    await convRef.update({'adminUnreadCount': 0}).catchError((_) {});

    // Mark user messages as read
    try {
      final snap = await convRef
          .collection('messages')
          .where('senderRole', isEqualTo: 'user')
          .where('status', isNotEqualTo: 'read')
          .get();

      for (var doc in snap.docs) {
        doc.reference.update({'status': 'read'}).catchError((_) {});
      }
    } catch (e) {
      debugPrint("Error marking messages read by admin: $e");
    }
  }

  /// Set admin typing state on a conversation
  void setAdminTyping({required String userId, required bool isTyping}) {
    _firestore.collection('conversations').doc(userId).update({
      'isAdminTyping': isTyping,
    }).catchError((_) {});
  }

  /// Admin send reply to user
  Future<String> adminSendMessage({
    required String userId,
    required String text,
    File? imageFile,
    Message? replyTo,
    required String adminId,
    String? messageId,
  }) async {
    final msgId = messageId ?? DateTime.now().millisecondsSinceEpoch.toString();
    String? imageUrl;
    if (imageFile != null) {
      imageUrl = await _uploadChatImage(imageFile, 'admin');
    }

    final convRef = _firestore.collection('conversations').doc(userId);
    final batch = _firestore.batch();

    batch.set(convRef.collection('messages').doc(msgId), {
      'id': msgId,
      'senderId': adminId,
      'senderRole': 'admin',
      'text': text,
      'imageUrl': imageUrl,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'sent',
      'replyToId': replyTo?.id,
      'replyText': replyTo?.text,
      'replyIsImage': replyTo?.type == MessageType.image,
      'isDeleted': false,
      'deletedFor': [],
    });

    batch.set(convRef, {
      'lastMessageText': text.isNotEmpty ? text : '📷 Photo',
      'lastMessageTimestamp': FieldValue.serverTimestamp(),
      'userUnreadCount': FieldValue.increment(1),
      'isAdminTyping': false,
    }, SetOptions(merge: true));

    await batch.commit();
    _playSound('sent.mp3');
    return msgId;
  }

  @override
  void dispose() {
    _conversationSub?.cancel();
    _messagesSub?.cancel();
    _typingDebounceTimer?.cancel();
    _audioPlayer?.dispose();
    super.dispose();
  }
}
