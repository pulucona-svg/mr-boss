import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/models/message.dart';
import 'package:mirror_laikipia/models/notification.dart';
import 'package:mirror_laikipia/services/chat_service.dart';
import 'package:mirror_laikipia/services/notification_service.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/widgets/notification_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
    NotificationService.resetInstance();
    ChatService.resetInstance();
  });

  tearDown(() {
    NotificationService().clearNotifications();
    NotificationService.resetInstance();
    ChatService().clear();
    ChatService.resetInstance();
  });

  group('Admin Message Read State & Unread Badge Tests (ChatService)', () {
    test('1. Unread incoming admin messages become read in memory when markAllAsRead is called', () {
      final chatService = ChatService();
      final now = DateTime.now();

      final incomingAdminMsg1 = Message(
        id: 'admin_msg_1',
        senderId: 'admin_uid',
        senderRole: 'admin',
        text: 'Hello, how can we assist you today?',
        timestamp: now.subtract(const Duration(minutes: 5)),
        isMe: false,
        status: MessageStatus.delivered,
        isRead: false,
      );

      final incomingAdminMsg2 = Message(
        id: 'admin_msg_2',
        senderId: 'admin_uid',
        senderRole: 'admin',
        text: 'Please provide your admission number.',
        timestamp: now.subtract(const Duration(minutes: 2)),
        isMe: false,
        status: MessageStatus.delivered,
        isRead: false,
      );

      chatService.setTestMessages(
        [incomingAdminMsg1, incomingAdminMsg2],
        userUnreadCount: 2,
        currentUserId: 'test_user_1',
      );

      expect(chatService.unreadCount, 2);
      expect(chatService.messages.first.isRead, false);
      expect(chatService.messages.last.isRead, false);

      // Execute markAllAsRead
      chatService.markAllAsRead();

      // Assert in-memory states are updated to read
      expect(chatService.messages.first.isRead, true);
      expect(chatService.messages.first.status, MessageStatus.read);
      expect(chatService.messages.last.isRead, true);
      expect(chatService.messages.last.status, MessageStatus.read);
    });

    test('2. The chat unread count remains zero after marking messages read', () {
      final chatService = ChatService();
      final now = DateTime.now();

      final incomingAdminMsg = Message(
        id: 'admin_msg_single',
        senderId: 'admin_uid',
        senderRole: 'admin',
        text: 'Your request has been processed.',
        timestamp: now,
        isMe: false,
        status: MessageStatus.delivered,
        isRead: false,
      );

      chatService.setTestMessages(
        [incomingAdminMsg],
        userUnreadCount: 1,
        currentUserId: 'test_user_1',
      );

      expect(chatService.unreadCount, 1);

      chatService.markAllAsRead();

      // unreadCount must be 0 immediately and remain 0
      expect(chatService.unreadCount, 0);

      // Verify that unreadCount getter does not evaluate fallback unread count
      final unreadFromFallback = chatService.messages.where((m) => !m.isMe && !m.isRead).length;
      expect(unreadFromFallback, 0);
      expect(chatService.unreadCount, 0);
    });

    test('3. Outgoing user messages are not incorrectly marked read', () {
      final chatService = ChatService();
      final now = DateTime.now();

      final outgoingUserMsg = Message(
        id: 'user_outgoing_1',
        senderId: 'test_user_1',
        senderRole: 'user',
        text: 'I submitted my assignment yesterday.',
        timestamp: now.subtract(const Duration(minutes: 10)),
        isMe: true,
        status: MessageStatus.sent,
        isRead: false,
      );

      final incomingAdminMsg = Message(
        id: 'admin_incoming_1',
        senderId: 'admin_uid',
        senderRole: 'admin',
        text: 'We received it successfully.',
        timestamp: now.subtract(const Duration(minutes: 5)),
        isMe: false,
        status: MessageStatus.delivered,
        isRead: false,
      );

      chatService.setTestMessages(
        [outgoingUserMsg, incomingAdminMsg],
        userUnreadCount: 1,
        currentUserId: 'test_user_1',
      );

      chatService.markAllAsRead();

      // Outgoing message status should be preserved (not modified to read by user side)
      final preservedUserMsg = chatService.messages.firstWhere((m) => m.id == 'user_outgoing_1');
      expect(preservedUserMsg.isMe, true);
      expect(preservedUserMsg.status, MessageStatus.sent);
      expect(preservedUserMsg.isRead, false);

      // Incoming admin message must be marked read
      final updatedAdminMsg = chatService.messages.firstWhere((m) => m.id == 'admin_incoming_1');
      expect(updatedAdminMsg.isMe, false);
      expect(updatedAdminMsg.status, MessageStatus.read);
      expect(updatedAdminMsg.isRead, true);

      expect(chatService.unreadCount, 0);
    });

    test('4. Firestore read-state updates target only the intended incoming admin messages', () {
      final now = DateTime.now();

      final messages = [
        Message(
          id: 'admin_1',
          senderId: 'admin',
          senderRole: 'admin',
          text: 'Notice',
          timestamp: now,
          isMe: false,
          status: MessageStatus.delivered,
          isRead: false,
        ),
        Message(
          id: 'admin_already_read',
          senderId: 'admin',
          senderRole: 'admin',
          text: 'Earlier Notice',
          timestamp: now.subtract(const Duration(hours: 1)),
          isMe: false,
          status: MessageStatus.read,
          isRead: true,
        ),
        Message(
          id: 'user_1',
          senderId: 'user_123',
          senderRole: 'user',
          text: 'Thanks',
          timestamp: now,
          isMe: true,
          status: MessageStatus.sent,
          isRead: false,
        ),
      ];

      // Simulate filtering logic used in markAllAsRead for Firestore batch update:
      // Must filter: senderRole == 'admin' && status != 'read'
      final unreadAdminDocIds = messages
          .where((m) => !m.isMe && m.senderRole == 'admin' && m.status != MessageStatus.read)
          .map((m) => m.id)
          .toList();

      expect(unreadAdminDocIds, ['admin_1']);
      expect(unreadAdminDocIds.contains('admin_already_read'), false);
      expect(unreadAdminDocIds.contains('user_1'), false);
    });

    test('5. Batch limits and chunking logic handles large datasets safely below 500 limit', () {
      // Generate 1000 message IDs to simulate large conversation history
      final docIds = List.generate(1000, (i) => 'msg_$i');
      const int batchLimit = 450;

      final chunks = <List<String>>[];
      for (int i = 0; i < docIds.length; i += batchLimit) {
        chunks.add(docIds.sublist(
          i,
          (i + batchLimit > docIds.length) ? docIds.length : i + batchLimit,
        ));
      }

      // 1000 items with chunk limit of 450 produces 3 chunks: 450, 450, 100
      expect(chunks.length, 3);
      expect(chunks[0].length, 450);
      expect(chunks[1].length, 450);
      expect(chunks[2].length, 100);
      expect(chunks.every((c) => c.length <= 500), true);
    });
  });

  group('New Account Historical Notification Boundary Tests (NotificationService)', () {
    test('6. Global announcements published before account creation are filtered out', () {
      final service = NotificationService();
      final registrationTime = DateTime(2026, 10, 15, 12, 0, 0);
      service.setTestUserId('new_user_101');
      service.setTestAccountCreationTime(registrationTime);

      final oldAnnouncement = AppNotification(
        id: 'announcement_old_1',
        type: NotificationType.adminAnnouncement,
        senderName: 'Admin',
        resourceTitle: 'Welcome to Semester 1',
        title: 'Welcome to Semester 1',
        message: 'Published in September before account was created',
        timestamp: DateTime(2026, 9, 1, 10, 0, 0),
        target: 'all',
      );

      service.handleTestSnapshot([oldAnnouncement]);

      // Historical announcement must NOT be delivered to the newly registered account
      expect(service.notifications.isEmpty, true);
      expect(service.unreadCount, 0);
    });

    test('7. Global announcements published after account creation remain visible', () {
      final service = NotificationService();
      final registrationTime = DateTime(2026, 10, 15, 12, 0, 0);
      service.setTestUserId('new_user_101');
      service.setTestAccountCreationTime(registrationTime);

      final newAnnouncement = AppNotification(
        id: 'announcement_new_1',
        type: NotificationType.adminAnnouncement,
        senderName: 'Admin',
        resourceTitle: 'Campus Wi-Fi Upgrade',
        title: 'Campus Wi-Fi Upgrade',
        message: 'Published 2 hours after registration',
        timestamp: DateTime(2026, 10, 15, 14, 0, 0),
        target: 'all',
      );

      service.handleTestSnapshot([newAnnouncement]);

      // Post-registration announcement must be delivered
      expect(service.notifications.length, 1);
      expect(service.notifications.first.id, 'announcement_new_1');
      expect(service.unreadCount, 1);
    });

    test('8. Targeted notifications for the current user remain visible even when predating global boundary', () {
      final service = NotificationService();
      final registrationTime = DateTime(2026, 10, 15, 12, 0, 0);
      service.setTestUserId('new_user_101');
      service.setTestAccountCreationTime(registrationTime);

      // Targeted moderation notification created around or slightly before official metadata time
      final targetedModerationNotif = AppNotification(
        id: 'notif_mat_approved_101',
        type: NotificationType.materialApproved,
        senderName: 'Admin',
        resourceTitle: 'Engineering Physics Notes',
        timestamp: DateTime(2026, 10, 15, 11, 55, 0),
        target: 'new_user_101',
      );

      service.handleTestSnapshot([targetedModerationNotif]);

      // Targeted notifications intended specifically for this user MUST remain visible
      expect(service.notifications.length, 1);
      expect(service.notifications.first.id, 'notif_mat_approved_101');
      expect(service.unreadCount, 1);
    });

    test('9. Notifications targeted to another user remain strictly hidden', () {
      final service = NotificationService();
      final registrationTime = DateTime(2026, 10, 15, 12, 0, 0);
      service.setTestUserId('new_user_101');
      service.setTestAccountCreationTime(registrationTime);

      final otherUserNotif = AppNotification(
        id: 'notif_other_user_private',
        type: NotificationType.materialRejected,
        senderName: 'Admin',
        resourceTitle: 'Private Upload',
        timestamp: DateTime(2026, 10, 15, 13, 0, 0),
        target: 'completely_different_user',
      );

      service.handleTestSnapshot([otherUserNotif]);

      // Must be completely excluded from new_user_101
      expect(service.notifications.isEmpty, true);
      expect(service.unreadCount, 0);
    });

    test('10. Missing or malformed timestamps and unavailable account creation metadata follow safe fallback', () {
      final service = NotificationService();
      // No account creation time set (null metadata)
      service.setTestUserId('fallback_user');
      service.setTestAccountCreationTime(null);

      final announcement = AppNotification(
        id: 'announcement_fallback',
        type: NotificationType.adminAnnouncement,
        senderName: 'Admin',
        resourceTitle: 'General Announcement',
        timestamp: DateTime(2026, 1, 1),
        target: 'all',
      );

      service.handleTestSnapshot([announcement]);

      // Safe fallback: when account age metadata is unavailable, notifications are safely preserved
      expect(service.notifications.length, 1);
      expect(service.notifications.first.id, 'announcement_fallback');
      expect(service.unreadCount, 1);
    });
  });

  group('Notification Panel Viewing & Read State Persistence Tests', () {
    testWidgets('11. Opening the notification panel clears its unread indicator immediately', (tester) async {
      final service = NotificationService();
      final announcement = AppNotification(
        id: 'panel_announcement_1',
        type: NotificationType.adminAnnouncement,
        senderName: 'Admin',
        resourceTitle: 'Holiday Schedule',
        title: 'Holiday Schedule',
        message: 'Campus offices will be closed on Monday.',
        timestamp: DateTime.now(),
        isRead: false,
      );

      service.handleTestSnapshot([announcement]);
      expect(service.unreadCount, 1);
      expect(service.notifications.first.isRead, false);

      // Open the NotificationModal
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NotificationModal(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Opening and viewing NotificationModal must mark all current notifications as read
      expect(service.unreadCount, 0);
      expect(service.notifications.first.isRead, true);
      expect(service.readIds.contains('panel_announcement_1'), true);
    });

    test('12. Existing read IDs and notification tap behavior remain intact', () {
      final service = NotificationService();
      final notif1 = AppNotification(
        id: 'tap_notif_1',
        type: NotificationType.adminAnnouncement,
        senderName: 'Admin',
        resourceTitle: 'Tap Test 1',
        timestamp: DateTime.now(),
      );
      final notif2 = AppNotification(
        id: 'tap_notif_2',
        type: NotificationType.adminAnnouncement,
        senderName: 'Admin',
        resourceTitle: 'Tap Test 2',
        timestamp: DateTime.now(),
      );

      service.handleTestSnapshot([notif1, notif2]);
      expect(service.unreadCount, 2);

      // Tap specific notification
      service.markAsRead('tap_notif_1');

      expect(service.unreadCount, 1);
      expect(service.notifications.firstWhere((n) => n.id == 'tap_notif_1').isRead, true);
      expect(service.notifications.firstWhere((n) => n.id == 'tap_notif_2').isRead, false);
      expect(service.readIds.contains('tap_notif_1'), true);

      // Re-triggering snapshot does not revert read status
      service.handleTestSnapshot([notif1, notif2]);
      expect(service.unreadCount, 1);
      expect(service.notifications.firstWhere((n) => n.id == 'tap_notif_1').isRead, true);
    });
  });
}
