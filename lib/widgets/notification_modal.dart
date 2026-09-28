import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../models/notification.dart';

class NotificationModal extends StatelessWidget {
  const NotificationModal({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF141232),
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Notifications',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () => NotificationService().markAllAsRead(),
                      child: const Text(
                        'Mark all as read',
                        style: TextStyle(color: Color(0xFF20C8FF), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          
          // Notifications List
          Expanded(
            child: ListenableBuilder(
              listenable: NotificationService(),
              builder: (context, child) {
                final notifications = NotificationService().notifications;
                if (notifications.isEmpty) {
                  return const Center(
                    child: Text(
                      'No notifications yet',
                      style: TextStyle(color: Colors.white24),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: notifications.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final n = notifications[index];
                    return GestureDetector(
                      onTap: () => NotificationService().markAsRead(n.id),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: n.isRead ? Colors.transparent : Colors.white.withAlpha(13),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: n.isRead ? Colors.white10 : const Color(0xFF20C8FF).withAlpha(77),
                            width: 0.5,
                          ),
                          ),
                          child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _getIconBackgroundColor(n.type),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _getNotificationIcon(n.type),
                                color: _getIconColor(n.type),
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildNotificationText(n),
                                  if (n.remark != null && n.remark!.trim().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Remark: ${n.remark!}',
                                      style: const TextStyle(color: Colors.white60, fontSize: 11, fontStyle: FontStyle.italic),
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatTimestamp(n.timestamp),
                                    style: const TextStyle(color: Colors.white24, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            if (!n.isRead)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF20C8FF),
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _getIconBackgroundColor(NotificationType type) {
    switch (type) {
      case NotificationType.like:
        return const Color(0xFFFF8A00).withAlpha(51);
      case NotificationType.reply:
        return const Color(0xFF20C8FF).withAlpha(51);
      case NotificationType.materialApproved:
        return const Color(0xFF00E676).withAlpha(51);
      case NotificationType.materialModified:
        return const Color(0xFF20C8FF).withAlpha(51);
      case NotificationType.materialRejected:
        return const Color(0xFFFF5252).withAlpha(51);
    }
  }

  IconData _getNotificationIcon(NotificationType type) {
    switch (type) {
      case NotificationType.like:
        return Icons.favorite;
      case NotificationType.reply:
        return Icons.reply;
      case NotificationType.materialApproved:
        return Icons.check_circle_rounded;
      case NotificationType.materialModified:
        return Icons.edit_note_rounded;
      case NotificationType.materialRejected:
        return Icons.cancel_rounded;
    }
  }

  Color _getIconColor(NotificationType type) {
    switch (type) {
      case NotificationType.like:
        return const Color(0xFFFF8A00);
      case NotificationType.reply:
        return const Color(0xFF20C8FF);
      case NotificationType.materialApproved:
        return const Color(0xFF00E676);
      case NotificationType.materialModified:
        return const Color(0xFF20C8FF);
      case NotificationType.materialRejected:
        return const Color(0xFFFF5252);
    }
  }

  Widget _buildNotificationText(AppNotification n) {
    if (n.type == NotificationType.materialApproved) {
      return RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.white70, fontSize: 13),
          children: [
            const TextSpan(text: 'Your uploaded material '),
            TextSpan(
              text: '"${n.resourceTitle}"',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const TextSpan(text: ' was approved! Thank you for contributing.'),
          ],
        ),
      );
    } else if (n.type == NotificationType.materialModified) {
      return RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.white70, fontSize: 13),
          children: [
            const TextSpan(text: 'Your uploaded material '),
            TextSpan(
              text: '"${n.resourceTitle}"',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const TextSpan(text: ' was modified and approved by an admin.'),
          ],
        ),
      );
    } else if (n.type == NotificationType.materialRejected) {
      final reasonsText = n.rejectionReasons != null && n.rejectionReasons!.isNotEmpty
          ? '\nReason: ${n.rejectionReasons!.join(", ")}'
          : '';
      return RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.white70, fontSize: 13),
          children: [
            const TextSpan(text: 'Your uploaded material '),
            TextSpan(
              text: '"${n.resourceTitle}"',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const TextSpan(text: ' was not approved.'),
            if (reasonsText.isNotEmpty)
              TextSpan(
                text: reasonsText,
                style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 12),
              ),
          ],
        ),
      );
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.white70, fontSize: 13),
        children: [
          TextSpan(
            text: n.senderName,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          TextSpan(
            text: n.type == NotificationType.like
                ? ' liked your comment on '
                : ' replied to your comment on ',
          ),
          TextSpan(
            text: n.resourceTitle,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
