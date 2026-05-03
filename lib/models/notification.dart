enum NotificationType { like, reply }

class AppNotification {
  final String id;
  final NotificationType type;
  final String senderName;
  final String resourceTitle;
  final DateTime timestamp;
  bool isRead;

  AppNotification({
    required this.id,
    required this.type,
    required this.senderName,
    required this.resourceTitle,
    required this.timestamp,
    this.isRead = false,
  });
}
