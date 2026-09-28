enum NotificationType {
  like,
  reply,
  materialApproved,
  materialModified,
  materialRejected,
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
  });
}
