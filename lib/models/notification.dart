import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  like,
  reply,
  materialApproved,
  materialModified,
  materialRejected,
  adminAnnouncement,
}

class AppNotification {
  final String id;
  final NotificationType type;
  final String senderName;
  final String resourceTitle;
  final DateTime timestamp;
  bool isRead;
  final String? title;
  final String? message;
  final String? materialId;
  final String? remark;
  final List<String>? rejectionReasons;
  final String? senderType;
  final String? createdBy;
  final String? target;

  AppNotification({
    required this.id,
    required this.type,
    required this.senderName,
    required this.resourceTitle,
    required this.timestamp,
    this.isRead = false,
    this.title,
    this.message,
    this.materialId,
    this.remark,
    this.rejectionReasons,
    this.senderType,
    this.createdBy,
    this.target,
  });

  factory AppNotification.fromFirestore(DocumentSnapshot doc, {bool isRead = false}) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return AppNotification.fromMap(data, doc.id, isRead: isRead);
  }

  factory AppNotification.fromMap(Map<String, dynamic> data, String id, {bool isRead = false}) {
    final rawType = (data['type'] as String?) ?? '';
    NotificationType resolvedType;
    switch (rawType) {
      case 'adminGlobal':
      case 'adminAnnouncement':
      case 'admin':
        resolvedType = NotificationType.adminAnnouncement;
        break;
      case 'like':
        resolvedType = NotificationType.like;
        break;
      case 'reply':
        resolvedType = NotificationType.reply;
        break;
      case 'materialApproved':
        resolvedType = NotificationType.materialApproved;
        break;
      case 'materialModified':
        resolvedType = NotificationType.materialModified;
        break;
      case 'materialRejected':
        resolvedType = NotificationType.materialRejected;
        break;
      default:
        resolvedType = NotificationType.adminAnnouncement;
    }

    DateTime parsedDate;
    final rawCreatedAt = data['createdAt'] ?? data['timestamp'];
    if (rawCreatedAt is Timestamp) {
      parsedDate = rawCreatedAt.toDate();
    } else if (rawCreatedAt is int) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(rawCreatedAt);
    } else if (rawCreatedAt is String) {
      parsedDate = DateTime.tryParse(rawCreatedAt) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return AppNotification(
      id: id,
      type: resolvedType,
      senderName: data['senderName'] as String? ?? 'Admin',
      resourceTitle: data['resourceTitle'] as String? ?? (data['title'] as String? ?? 'Announcement'),
      timestamp: parsedDate,
      isRead: isRead,
      title: data['title'] as String?,
      message: data['message'] as String?,
      materialId: data['materialId'] as String?,
      remark: data['remark'] as String?,
      rejectionReasons: (data['rejectionReasons'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      senderType: data['senderType'] as String? ?? 'admin',
      createdBy: data['createdBy'] as String?,
      target: data['target'] as String? ?? 'all',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type == NotificationType.adminAnnouncement ? 'adminGlobal' : type.name,
      'title': title ?? resourceTitle,
      'message': message,
      'senderName': senderName,
      'senderType': senderType ?? (type == NotificationType.adminAnnouncement ? 'admin' : 'user'),
      'resourceTitle': resourceTitle,
      'createdAt': Timestamp.fromDate(timestamp),
      'materialId': materialId,
      'remark': remark,
      'rejectionReasons': rejectionReasons,
      'createdBy': createdBy,
      'target': target ?? 'all',
    };
  }
}
