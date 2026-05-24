import 'dart:io';

enum MessageType { text, image }
enum MessageStatus { sent, delivered, read }

class Message {
  final String id;
  final String? senderId;
  final String text;
  final String? imageUrl;
  final File? imageFile;
  final DateTime timestamp;
  final bool isMe;
  final MessageType type;
  final MessageStatus status;
  final String? replyToId;
  final String? replyText;
  final bool? replyIsImage;
  final String? reaction;
  final bool isDeleted;
  final bool isRead;

  Message({
    required this.id,
    this.senderId,
    required this.text,
    this.imageFile,
    this.imageUrl,
    required this.timestamp,
    required this.isMe,
    this.type = MessageType.text,
    this.status = MessageStatus.sent,
    this.replyToId,
    this.replyText,
    this.replyIsImage,
    this.reaction,
    this.isDeleted = false,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'text': text,
      'imageUrl': imageUrl,
      'timestamp': timestamp.toIso8601String(),
      'isMe': isMe,
      'type': type.index,
      'status': status.index,
      'replyToId': replyToId,
      'replyText': replyText,
      'replyIsImage': replyIsImage,
      'reaction': reaction,
      'isDeleted': isDeleted,
      'isRead': isRead,
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      senderId: json['senderId'],
      text: json['text'],
      imageUrl: json['imageUrl'],
      timestamp: DateTime.parse(json['timestamp']),
      isMe: json['isMe'],
      type: MessageType.values[json['type']],
      status: MessageStatus.values[json['status'] ?? 0],
      replyToId: json['replyToId'],
      replyText: json['replyText'],
      replyIsImage: json['replyIsImage'],
      reaction: json['reaction'],
      isDeleted: json['isDeleted'] ?? false,
      isRead: json['isRead'] ?? false,
    );
  }
}
