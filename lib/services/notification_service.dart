import 'package:flutter/material.dart';
import '../models/notification.dart';

class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final List<AppNotification> _notifications = [];

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  void addNotification({
    required NotificationType type,
    required String senderName,
    required String resourceTitle,
  }) {
    final notification = AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      senderName: senderName,
      resourceTitle: resourceTitle,
      timestamp: DateTime.now(),
    );
    _notifications.insert(0, notification);
    notifyListeners();
  }

  void addModerationNotification({
    required NotificationType type,
    required String resourceTitle,
    String? id,
    String? title,
    String? message,
    String? materialId,
    String? remark,
    List<String>? rejectionReasons,
  }) {
    // Prevent duplicate notification if id matches
    if (id != null && _notifications.any((n) => n.id == id)) {
      return;
    }
    final notification = AppNotification(
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      senderName: 'Admin',
      resourceTitle: resourceTitle,
      timestamp: DateTime.now(),
      title: title,
      message: message,
      materialId: materialId,
      remark: remark,
      rejectionReasons: rejectionReasons,
    );
    _notifications.insert(0, notification);
    notifyListeners();
  }

  void markAsRead(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index != -1) {
      _notifications[index].isRead = true;
      notifyListeners();
    }
  }

  void markAllAsRead() {
    for (var n in _notifications) {
      n.isRead = true;
    }
    notifyListeners();
  }

  void clearNotifications() {
    _notifications.clear();
    notifyListeners();
  }
}
