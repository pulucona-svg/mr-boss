import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/message.dart';

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
      notifyListeners();
    }
  }

  ChatService() {
    _cleanupOldMessages();
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
    notifyListeners();
    _playSound('sent.mp3');

    // Simulate Status Transitions
    _simulateMessageStatus(messageId);

    // Mock Admin Response Flow
    _simulateAdminResponse();
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
      notifyListeners();
    }
  }

  void _simulateAdminResponse() async {
    await Future.delayed(const Duration(seconds: 1));
    _isAdminTyping = true;
    notifyListeners();

    await Future.delayed(const Duration(seconds: 5));
    _isAdminTyping = false;
    _receiveAdminMessage("Thank you for contacting Mirror Laikipia support. How can we help you today?");
    notifyListeners();
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
    notifyListeners();
    _playSound('received.mp3');
  }

  void _cleanupOldMessages() {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    _messages.removeWhere((msg) => msg.timestamp.isBefore(sevenDaysAgo));
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
      notifyListeners();
    }
  }

  void clearChat() {
    _messages.clear();
    notifyListeners();
  }
}
