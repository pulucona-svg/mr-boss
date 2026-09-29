import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/models/notification.dart';
import 'package:mirror_laikipia/services/notification_service.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/widgets/notification_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
    NotificationService.resetInstance();
  });

  tearDown(() {
    NotificationService().clearNotifications();
    NotificationService.resetInstance();
  });

  group('AppNotification Model & Serialization Tests', () {
    test('Correctly parses adminGlobal notification type', () {
      final map = {
        'type': 'adminGlobal',
        'title': 'Library Closure',
        'message': 'The main library will close early today at 5 PM.',
        'senderName': 'Admin',
        'senderType': 'admin',
        'createdAt': DateTime(2026, 9, 29, 14, 0).millisecondsSinceEpoch,
        'createdBy': 'admin_uid_123',
        'target': 'all',
      };

      final notification = AppNotification.fromMap(map, 'notif_global_1');

      expect(notification.id, 'notif_global_1');
      expect(notification.type, NotificationType.adminAnnouncement);
      expect(notification.title, 'Library Closure');
      expect(notification.message, 'The main library will close early today at 5 PM.');
      expect(notification.senderName, 'Admin');
      expect(notification.senderType, 'admin');
      expect(notification.createdBy, 'admin_uid_123');
      expect(notification.target, 'all');
      expect(notification.isRead, false);
    });

    test('Correctly parses adminAnnouncement legacy type', () {
      final map = {
        'type': 'adminAnnouncement',
        'title': 'Exam Timetable Out',
        'message': 'Check portal for semester 2 exam dates.',
        'senderName': 'Admin',
      };

      final notification = AppNotification.fromMap(map, 'notif_ann_2');
      expect(notification.type, NotificationType.adminAnnouncement);
      expect(notification.title, 'Exam Timetable Out');
    });

    test('Preserves backwards compatibility for moderation notifications', () {
      final map = {
        'type': 'materialApproved',
        'resourceTitle': 'Calculus Notes Chapter 4',
        'senderName': 'Admin',
        'materialId': 'mat_123',
      };

      final notification = AppNotification.fromMap(map, 'notif_mod_3');
      expect(notification.type, NotificationType.materialApproved);
      expect(notification.resourceTitle, 'Calculus Notes Chapter 4');
      expect(notification.materialId, 'mat_123');
    });

    test('Serializes admin announcement to map with adminGlobal type', () {
      final notification = AppNotification(
        id: 'notif_test_4',
        type: NotificationType.adminAnnouncement,
        senderName: 'Admin',
        resourceTitle: 'Power Interruption',
        title: 'Power Interruption',
        message: 'Maintenance scheduled for Block B.',
        timestamp: DateTime(2026, 9, 29, 12, 0),
        senderType: 'admin',
        createdBy: 'admin_master',
        target: 'all',
      );

      final map = notification.toMap();
      expect(map['type'], 'adminGlobal');
      expect(map['title'], 'Power Interruption');
      expect(map['message'], 'Maintenance scheduled for Block B.');
      expect(map['senderType'], 'admin');
      expect(map['createdBy'], 'admin_master');
      expect(map['target'], 'all');
    });
  });

  group('NotificationService Deduplication & State Management Tests', () {
    test('Initial load populates notifications without triggering new alert', () {
      final service = NotificationService();
      bool alertTriggered = false;
      service.onNewNotificationArrival = (_) {
        alertTriggered = true;
      };

      final initialItems = [
        AppNotification(
          id: 'existing_1',
          type: NotificationType.adminAnnouncement,
          senderName: 'Admin',
          resourceTitle: 'Welcome Back',
          title: 'Welcome Back',
          message: 'Welcome to the new academic year!',
          timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        AppNotification(
          id: 'existing_2',
          type: NotificationType.adminAnnouncement,
          senderName: 'Admin',
          resourceTitle: 'Library Pass',
          title: 'Library Pass',
          message: 'Remember to collect your library pass.',
          timestamp: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      ];

      // Simulate initial snapshot
      service.handleTestSnapshot(initialItems);

      expect(service.notifications.length, 2);
      expect(service.unreadCount, 2);
      // Ensure NO sound or popup triggered on initial snapshot
      expect(alertTriggered, false);
      expect(service.seenIds.contains('existing_1'), true);
      expect(service.seenIds.contains('existing_2'), true);
    });

    test('Realtime new arrival triggers alert callback once and deduplicates on reconnect', () {
      final service = NotificationService();
      int alertCount = 0;
      AppNotification? lastReceived;

      service.onNewNotificationArrival = (notif) {
        alertCount++;
        lastReceived = notif;
      };

      final initialItems = [
        AppNotification(
          id: 'init_1',
          type: NotificationType.adminAnnouncement,
          senderName: 'Admin',
          resourceTitle: 'Initial',
          title: 'Initial',
          timestamp: DateTime.now(),
        ),
      ];

      // Initial snapshot
      service.handleTestSnapshot(initialItems);
      expect(alertCount, 0);

      // New announcement arrives in realtime
      final newAnnouncement = AppNotification(
        id: 'new_broadcast_99',
        type: NotificationType.adminAnnouncement,
        senderName: 'Admin',
        resourceTitle: 'Emergency Notice',
        title: 'Emergency Notice',
        message: 'Main hall closed due to repairs.',
        timestamp: DateTime.now(),
      );

      service.handleTestSnapshot([newAnnouncement, ...initialItems]);

      expect(alertCount, 1);
      expect(lastReceived?.id, 'new_broadcast_99');
      expect(service.notifications.length, 2);
      expect(service.unreadCount, 2);

      // Simulate stream reconnect / identical snapshot delivery
      service.handleTestSnapshot([newAnnouncement, ...initialItems]);

      // Should NOT re-trigger alert for already seen notification!
      expect(alertCount, 1);
    });

    test('markAsRead updates item, decrements unread count, and persists read state', () async {
      final service = NotificationService();

      final items = [
        AppNotification(
          id: 'item_1',
          type: NotificationType.adminAnnouncement,
          senderName: 'Admin',
          resourceTitle: 'Notice 1',
          timestamp: DateTime.now(),
        ),
        AppNotification(
          id: 'item_2',
          type: NotificationType.adminAnnouncement,
          senderName: 'Admin',
          resourceTitle: 'Notice 2',
          timestamp: DateTime.now(),
        ),
      ];

      service.handleTestSnapshot(items);
      expect(service.unreadCount, 2);

      service.markAsRead('item_1');
      expect(service.unreadCount, 1);
      expect(service.notifications.firstWhere((n) => n.id == 'item_1').isRead, true);
      expect(service.notifications.firstWhere((n) => n.id == 'item_2').isRead, false);
      expect(service.readIds.contains('item_1'), true);

      // Verify persistence in PersistenceService
      final persisted = PersistenceService().getStringList('read_notifications_anonymous');
      expect(persisted, isNotNull);
      expect(persisted!.contains('item_1'), true);
    });

    test('markAllAsRead marks all notifications as read', () {
      final service = NotificationService();

      final items = [
        AppNotification(
          id: 'item_A',
          type: NotificationType.adminAnnouncement,
          senderName: 'Admin',
          resourceTitle: 'Notice A',
          timestamp: DateTime.now(),
        ),
        AppNotification(
          id: 'item_B',
          type: NotificationType.adminAnnouncement,
          senderName: 'Admin',
          resourceTitle: 'Notice B',
          timestamp: DateTime.now(),
        ),
      ];

      service.handleTestSnapshot(items);
      expect(service.unreadCount, 2);

      service.markAllAsRead();
      expect(service.unreadCount, 0);
      expect(service.notifications.every((n) => n.isRead), true);
    });

    test('Existing moderation and user notifications work in harmony with admin global', () {
      final service = NotificationService();

      service.addNotification(
        type: NotificationType.like,
        senderName: 'Jane Doe',
        resourceTitle: 'Physics I Past Paper',
      );

      service.addModerationNotification(
        type: NotificationType.materialApproved,
        resourceTitle: 'Chemistry Notes 2026',
        materialId: 'chem_001',
      );

      final globalNotif = AppNotification(
        id: 'global_campus_alert',
        type: NotificationType.adminAnnouncement,
        senderName: 'Admin',
        resourceTitle: 'Campus Wi-Fi Upgrade',
        title: 'Campus Wi-Fi Upgrade',
        timestamp: DateTime.now(),
      );

      service.handleTestSnapshot([globalNotif]);

      expect(service.notifications.length, 3);
      expect(service.unreadCount, 3);
      expect(service.notifications.any((n) => n.type == NotificationType.like), true);
      expect(service.notifications.any((n) => n.type == NotificationType.materialApproved), true);
      expect(service.notifications.any((n) => n.type == NotificationType.adminAnnouncement), true);
    });
  });

  group('NotificationModal Widget Tests', () {
    testWidgets('Renders admin announcement with ADMIN chip, title, message, and timestamp',
        (tester) async {
      final service = NotificationService();
      final announcement = AppNotification(
        id: 'modal_test_1',
        type: NotificationType.adminAnnouncement,
        senderName: 'Admin',
        resourceTitle: 'Fee Payment Deadline',
        title: 'Fee Payment Deadline',
        message: 'All semester fees must be cleared by Friday 5 PM.',
        timestamp: DateTime.now(),
        isRead: false,
      );

      service.handleTestSnapshot([announcement]);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NotificationModal(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('ADMIN'), findsOneWidget);
      expect(find.text('Fee Payment Deadline'), findsOneWidget);
      expect(find.text('All semester fees must be cleared by Friday 5 PM.'), findsOneWidget);
      expect(find.text('Mark all as read'), findsOneWidget);

      // Tap announcement to mark as read
      await tester.tap(find.text('Fee Payment Deadline'));
      await tester.pumpAndSettle();

      expect(service.unreadCount, 0);
    });

    testWidgets('Tapping Mark all as read updates all items in modal', (tester) async {
      final service = NotificationService();
      final items = [
        AppNotification(
          id: 'notif_10',
          type: NotificationType.adminAnnouncement,
          senderName: 'Admin',
          resourceTitle: 'Notice 10',
          title: 'Notice 10',
          message: 'Message 10',
          timestamp: DateTime.now(),
          isRead: false,
        ),
        AppNotification(
          id: 'notif_20',
          type: NotificationType.adminAnnouncement,
          senderName: 'Admin',
          resourceTitle: 'Notice 20',
          title: 'Notice 20',
          message: 'Message 20',
          timestamp: DateTime.now(),
          isRead: false,
        ),
      ];

      service.handleTestSnapshot(items);
      expect(service.unreadCount, 2);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NotificationModal(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark all as read'));
      await tester.pumpAndSettle();

      expect(service.unreadCount, 0);
    });
  });
}
