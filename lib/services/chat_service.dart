import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/message.dart';
import 'persistence_service.dart';

class ChatService extends ChangeNotifier {
  final List<Message> _messages = [];
  bool _isAdminTyping = false;
  final AudioPlayer _audioPlayer = AudioPlayer();

  List<Message> get messages => List.unmodifiable(_messages);
  bool get isAdminTyping => _isAdminTyping;

  int get unreadCount => _messages.where((m) => !m.isMe && !m.isRead).length;

  void markAllAsRead() {
    bool changed = false;
    for (int i = 0; i < _messages.length; i++) {
      if (!_messages[i].isMe && !_messages[i].isRead) {
        final oldMsg = _messages[i];
        _messages[i] = Message(
          id: oldMsg.id,
          senderId: oldMsg.senderId,
          text: oldMsg.text,
          imageFile: oldMsg.imageFile,
          imageUrl: oldMsg.imageUrl,
          timestamp: oldMsg.timestamp,
          isMe: oldMsg.isMe,
          type: oldMsg.type,
          status: oldMsg.status,
          replyToId: oldMsg.replyToId,
          replyText: oldMsg.replyText,
          replyIsImage: oldMsg.replyIsImage,
          reaction: oldMsg.reaction,
          isDeleted: oldMsg.isDeleted,
          isRead: true,
        );
        changed = true;
      }
    }
    if (changed) {
      _saveMessages();
      notifyListeners();
    }
  }

  ChatService() {
    _restoreMessages();
  }

  Future<void> _restoreMessages() async {
    final json = PersistenceService().getJson('chat_messages');
    if (json != null) {
      _messages.clear();
      _messages.addAll(List<Message>.from((json as List).map((m) => Message.fromJson(m))));
      _cleanupOldMessages();
      notifyListeners();
    }
  }

  Future<void> _saveMessages() async {
    await PersistenceService().setJson('chat_messages', _messages.map((m) => m.toJson()).toList());
  }

  void _playSound(String fileName) async {
    try {
      await _audioPlayer.play(AssetSource(fileName));
    } catch (e) {
      debugPrint("Sound play failed: $e");
    }
  }

  void sendMessage(String text, {File? imageFile, Message? replyTo, String? senderId}) {
    _cleanupOldMessages();
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();
    final message = Message(
      id: messageId,
      senderId: senderId,
      text: text,
      imageFile: imageFile,
      timestamp: DateTime.now(),
      isMe: true,
      type: imageFile != null ? MessageType.image : MessageType.text,
      status: MessageStatus.sent,
      replyToId: replyTo?.id,
      replyText: replyTo?.text,
      replyIsImage: replyTo?.type == MessageType.image,
    );
    _messages.add(message);
    _saveMessages();
    notifyListeners();
    _playSound('sent.mp3');

    // Simulate Status Transitions
    _simulateMessageStatus(messageId);

    // TASK 2: Gemini AI Help & Support Assistant Response
    if (text.trim().isNotEmpty) {
      _fetchGeminiAdminResponse(text.trim());
    } else if (imageFile != null) {
      _fetchGeminiAdminResponse("I uploaded an image regarding my issue.");
    }
  }

  void _simulateMessageStatus(String messageId) async {
    // 1. Delivered after short delay
    await Future.delayed(const Duration(seconds: 1));
    _updateMessageStatus(messageId, MessageStatus.delivered);

    // 2. Read after slightly longer delay
    await Future.delayed(const Duration(seconds: 2));
    _updateMessageStatus(messageId, MessageStatus.read);
  }

  void _updateMessageStatus(String id, MessageStatus status) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index != -1) {
      final oldMsg = _messages[index];
      _messages[index] = Message(
        id: oldMsg.id,
        senderId: oldMsg.senderId,
        text: oldMsg.text,
        imageFile: oldMsg.imageFile,
        imageUrl: oldMsg.imageUrl,
        timestamp: oldMsg.timestamp,
        isMe: oldMsg.isMe,
        type: oldMsg.type,
        status: status,
        replyToId: oldMsg.replyToId,
        replyText: oldMsg.replyText,
        replyIsImage: oldMsg.replyIsImage,
        reaction: oldMsg.reaction,
        isDeleted: oldMsg.isDeleted,
      );
      _saveMessages();
      notifyListeners();
    }
  }

  /// TASK 2 — AI Powered Help & Support Assistant
  void _fetchGeminiAdminResponse(String userText) async {
    await Future.delayed(const Duration(milliseconds: 400));
    _isAdminTyping = true;
    notifyListeners();

    try {
      final history = _messages
          .where((m) => !m.isDeleted && m.text.isNotEmpty)
          .take(10)
          .map((m) => {
                'isMe': m.isMe,
                'text': m.text,
              })
          .toList();

      final result = await FirebaseFunctions.instance
          .httpsCallable('askGeminiHelpSupport')
          .call({
        'message': userText,
        'history': history,
      });

      _isAdminTyping = false;

      if (result.data != null && result.data['reply'] != null) {
        final replyText = result.data['reply'].toString();
        _receiveAdminMessage(replyText);
      } else {
        _receiveAdminMessage(
            "Hello! I am the Mirror Laikipia AI Assistant. How can I help you with your account, uploads, downloads, or subscriptions today?");
      }
    } catch (e) {
      _isAdminTyping = false;
      debugPrint("Gemini Help Assistant error: $e");
      _receiveAdminMessage(
          "I'm having trouble connecting to the AI assistant right now. Please check your network connection and try again.");
    }
  }


  void _receiveAdminMessage(String text) {
    final message = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: 'admin',
      text: text,
      timestamp: DateTime.now(),
      isMe: false,
      type: MessageType.text,
    );
    _messages.add(message);
    _saveMessages();
    notifyListeners();
    _playSound('received.mp3');
  }

  void _cleanupOldMessages() {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    final initialCount = _messages.length;
    _messages.removeWhere((msg) => msg.timestamp.isBefore(sevenDaysAgo));
    if (_messages.length != initialCount) {
      _saveMessages();
    }
  }

  void addReaction(String id, String emoji) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index != -1) {
      final oldMsg = _messages[index];
      if (oldMsg.isDeleted) return;
      _messages[index] = Message(
        id: oldMsg.id,
        senderId: oldMsg.senderId,
        text: oldMsg.text,
        imageFile: oldMsg.imageFile,
        imageUrl: oldMsg.imageUrl,
        timestamp: oldMsg.timestamp,
        isMe: oldMsg.isMe,
        type: oldMsg.type,
        status: oldMsg.status,
        replyToId: oldMsg.replyToId,
        replyText: oldMsg.replyText,
        replyIsImage: oldMsg.replyIsImage,
        reaction: emoji,
        isDeleted: oldMsg.isDeleted,
      );
      _saveMessages();
      notifyListeners();
    }
  }

  void deleteMessage(String id) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index != -1) {
      final oldMsg = _messages[index];
      _messages[index] = Message(
        id: oldMsg.id,
        senderId: oldMsg.senderId,
        text: "This message was deleted",
        timestamp: oldMsg.timestamp,
        isMe: oldMsg.isMe,
        type: MessageType.text,
        status: oldMsg.status,
        isDeleted: true,
      );
      _saveMessages();
      notifyListeners();
    }
  }

  void editMessage(String id, String newText) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index != -1) {
      final oldMsg = _messages[index];
      _messages[index] = Message(
        id: oldMsg.id,
        senderId: oldMsg.senderId,
        text: newText,
        imageFile: oldMsg.imageFile,
        imageUrl: oldMsg.imageUrl,
        timestamp: oldMsg.timestamp,
        isMe: oldMsg.isMe,
        type: oldMsg.type,
        status: oldMsg.status,
        replyToId: oldMsg.replyToId,
        replyText: oldMsg.replyText,
        replyIsImage: oldMsg.replyIsImage,
        reaction: oldMsg.reaction,
      );
      _saveMessages();
      notifyListeners();
    }
  }

  void clearChat() {
    _messages.clear();
    _saveMessages();
    notifyListeners();
  }
}
