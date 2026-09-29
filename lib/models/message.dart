import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, image }
enum MessageStatus { sent, delivered, read }

class Message {
  final String id;
  final String? senderId;
  final String? senderRole; // 'user' or 'admin'
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
  final List<String> deletedFor;
  final Map<String, dynamic>? metadata;

  Message({
    required this.id,
    this.senderId,
    this.senderRole,
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
    this.deletedFor = const [],
    this.metadata,
  });

  Message copyWith({
    String? id,
    String? senderId,
    String? senderRole,
    String? text,
    String? imageUrl,
    File? imageFile,
    DateTime? timestamp,
    bool? isMe,
    MessageType? type,
    MessageStatus? status,
    String? replyToId,
    String? replyText,
    bool? replyIsImage,
    String? reaction,
    bool? isDeleted,
    bool? isRead,
    List<String>? deletedFor,
    Map<String, dynamic>? metadata,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderRole: senderRole ?? this.senderRole,
      text: text ?? this.text,
      imageUrl: imageUrl ?? this.imageUrl,
      imageFile: imageFile ?? this.imageFile,
      timestamp: timestamp ?? this.timestamp,
      isMe: isMe ?? this.isMe,
      type: type ?? this.type,
      status: status ?? this.status,
      replyToId: replyToId ?? this.replyToId,
      replyText: replyText ?? this.replyText,
      replyIsImage: replyIsImage ?? this.replyIsImage,
      reaction: reaction ?? this.reaction,
      isDeleted: isDeleted ?? this.isDeleted,
      isRead: isRead ?? this.isRead,
      deletedFor: deletedFor ?? this.deletedFor,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'senderRole': senderRole,
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
      'deletedFor': deletedFor,
      'metadata': metadata,
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? '',
      senderId: json['senderId'],
      senderRole: json['senderRole'],
      text: json['text'] ?? '',
      imageUrl: json['imageUrl'],
      timestamp: json['timestamp'] != null 
          ? DateTime.tryParse(json['timestamp']) ?? DateTime.now()
          : DateTime.now(),
      isMe: json['isMe'] ?? false,
      type: MessageType.values[json['type'] ?? 0],
      status: MessageStatus.values[json['status'] ?? 0],
      replyToId: json['replyToId'],
      replyText: json['replyText'],
      replyIsImage: json['replyIsImage'],
      reaction: json['reaction'],
      isDeleted: json['isDeleted'] ?? false,
      isRead: json['isRead'] ?? false,
      deletedFor: List<String>.from(json['deletedFor'] ?? const []),
      metadata: json['metadata'] != null ? Map<String, dynamic>.from(json['metadata'] as Map) : null,
    );
  }

  factory Message.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String currentUserId,
    bool isAdmin = false,
  }) {
    final data = doc.data() ?? {};
    final senderId = data['senderId'] as String?;
    final senderRole = data['senderRole'] as String?;
    final isDeleted = data['isDeleted'] == true;
    final List<String> deletedFor = List<String>.from(data['deletedFor'] ?? const []);

    final bool isMe;
    if (isAdmin) {
      isMe = senderRole == 'admin' || senderId == 'admin' || (currentUserId.isNotEmpty && senderId == currentUserId);
    } else {
      isMe = senderRole == 'user' || (currentUserId.isNotEmpty && senderId == currentUserId);
    }

    final ts = data['timestamp'];
    DateTime timestamp;
    if (ts is Timestamp) {
      timestamp = ts.toDate();
    } else if (ts is String) {
      timestamp = DateTime.tryParse(ts) ?? DateTime.now();
    } else {
      timestamp = DateTime.now();
    }

    MessageStatus status = MessageStatus.sent;
    final statusVal = data['status'];
    if (statusVal is String) {
      if (statusVal == 'read') {
        status = MessageStatus.read;
      } else if (statusVal == 'delivered') {
        status = MessageStatus.delivered;
      } else {
        status = MessageStatus.sent;
      }
    } else if (statusVal is int && statusVal < MessageStatus.values.length) {
      status = MessageStatus.values[statusVal];
    }

    final imageUrl = data['imageUrl'] as String?;
    final text = data['text'] as String? ?? '';

    return Message(
      id: doc.id,
      senderId: senderId,
      senderRole: senderRole,
      text: isDeleted ? 'This message was deleted' : text,
      imageUrl: imageUrl,
      timestamp: timestamp,
      isMe: isMe,
      type: (imageUrl != null && imageUrl.isNotEmpty) ? MessageType.image : MessageType.text,
      status: status,
      replyToId: data['replyToId'] as String?,
      replyText: data['replyText'] as String?,
      replyIsImage: data['replyIsImage'] as bool?,
      reaction: data['reaction'] as String?,
      isDeleted: isDeleted,
      deletedFor: deletedFor,
      isRead: status == MessageStatus.read,
      metadata: data['metadata'] != null ? Map<String, dynamic>.from(data['metadata'] as Map) : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'senderId': senderId,
      'senderRole': senderRole ?? (isMe ? 'user' : 'admin'),
      'text': text,
      'imageUrl': imageUrl,
      'timestamp': Timestamp.fromDate(timestamp),
      'status': status.name,
      'replyToId': replyToId,
      'replyText': replyText,
      'replyIsImage': replyIsImage,
      'reaction': reaction,
      'isDeleted': isDeleted,
      'deletedFor': deletedFor,
      'metadata': metadata,
    };
  }
}
