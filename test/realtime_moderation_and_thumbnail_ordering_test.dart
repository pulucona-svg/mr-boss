import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/models/notification.dart';
import 'package:mirror_laikipia/models/message.dart';
import 'package:mirror_laikipia/services/resource_service.dart';
import 'package:mirror_laikipia/services/notification_service.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/services/chat_service.dart';

Resource createTestMaterial({
  required String id,
  required String title,
  required DateTime uploadDate,
  DateTime? approvedAt,
  bool isPinned = false,
  DateTime? pinnedAt,
  String thumbnailUrl = 'https://ik.imagekit.io/ubgbitinve/THUMBNAILS/test.jpg',
  String thumbnailStatus = 'completed',
  bool isImportedDSpace = false,
  String uploaderId = 'user_1',
  String uploadedBy = 'Student',
  String status = 'approved',
}) {
  return Resource(
    id: id,
    title: title,
    type: 'Notes',
    thumbnailUrl: thumbnailUrl,
    thumbnailStatus: thumbnailStatus,
    fileUrl: 'https://example.com/file.pdf',
    fileId: 'file_$id',
    unitName: 'Unit $title',
    unitCode: 'COMP 101',
    year: '2024',
    uploadYear: '2024',
    publicationYear: '2024',
    yearOfStudy: '1st Year',
    semester: 'Semester 1',
    lecturers: ['Dr. Lecturer'],
    uploadedBy: uploadedBy,
    uploaderRole: 'Student',
    uploaderId: uploaderId,
    uploadDate: uploadDate,
    approvedAt: approvedAt,
    isPinned: isPinned,
    pinnedAt: pinnedAt,
    isImportedDSpace: isImportedDSpace,
    status: status,
  );
}

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
    ResourceService().clear();
  });

  tearDown(() {
    NotificationService().clearNotifications();
    NotificationService.resetInstance();
    ResourceService().clear();
  });

  group('Permanent Universal Thumbnail Ordering Tests', () {
    test('Thumbnails are prioritized permanently for all sources regardless of DSpace flag', () {
      final service = ResourceService();

      // Ensure that whether incomplete flag is true or false, thumbnail prioritization is permanent
      service.setHasIncompleteDSpaceThumbnails(false);

      final withThumbDSpace = createTestMaterial(
        id: 'dspace_thumb',
        title: 'DSpace Exam',
        uploadDate: DateTime(2026, 1, 10),
        isImportedDSpace: true,
        thumbnailUrl: 'https://example.com/thumb1.jpg',
      );

      final withThumbStudent = createTestMaterial(
        id: 'student_thumb',
        title: 'Student Notes',
        uploadDate: DateTime(2026, 1, 12),
        isImportedDSpace: false,
        thumbnailUrl: 'https://example.com/thumb2.jpg',
      );

      final noThumbAdmin = createTestMaterial(
        id: 'admin_no_thumb',
        title: 'Admin Document (Newest)',
        uploadDate: DateTime(2026, 1, 20), // Newest date, but no thumbnail
        thumbnailUrl: '',
        thumbnailStatus: 'pending',
      );

      final noThumbDSpace = createTestMaterial(
        id: 'dspace_no_thumb',
        title: 'DSpace Without Thumbnail',
        uploadDate: DateTime(2026, 1, 18),
        thumbnailUrl: '',
        thumbnailStatus: 'pending',
        isImportedDSpace: true,
      );

      final sorted = service.sortResources([
        noThumbAdmin,
        withThumbDSpace,
        noThumbDSpace,
        withThumbStudent,
      ]);

      // Both items with thumbnails must precede all items without thumbnails:
      // Group 1: student_thumb (Jan 12), dspace_thumb (Jan 10)
      // Group 2: admin_no_thumb (Jan 20), dspace_no_thumb (Jan 18)
      expect(sorted.map((r) => r.id).toList(), equals([
        'student_thumb',
        'dspace_thumb',
        'admin_no_thumb',
        'dspace_no_thumb',
      ]));
    });

    test('Pinned items always remain strictly first, followed by thumbnail-prioritized items', () {
      final service = ResourceService();

      final pinnedWithoutThumb = createTestMaterial(
        id: 'pinned_no_thumb',
        title: 'Important Announcement',
        uploadDate: DateTime(2026, 1, 1),
        isPinned: true,
        pinnedAt: DateTime(2026, 1, 15),
        thumbnailUrl: '',
      );

      final unpinnedWithThumb = createTestMaterial(
        id: 'unpinned_with_thumb',
        title: 'Notes With Thumbnail',
        uploadDate: DateTime(2026, 1, 25),
        thumbnailUrl: 'https://example.com/thumb.jpg',
      );

      final unpinnedNoThumb = createTestMaterial(
        id: 'unpinned_no_thumb',
        title: 'Notes Without Thumbnail',
        uploadDate: DateTime(2026, 1, 24),
        thumbnailUrl: '',
      );

      final sorted = service.sortResources([
        unpinnedNoThumb,
        unpinnedWithThumb,
        pinnedWithoutThumb,
      ]);

      expect(sorted.map((r) => r.id).toList(), equals([
        'pinned_no_thumb',
        'unpinned_with_thumb',
        'unpinned_no_thumb',
      ]));
    });
  });

  group('Recipient Targeting & Moderation Notification Tests', () {
    test('Personal moderation notification is only received by matching target user', () {
      final service = NotificationService();
      service.setInitialLoadComplete();

      final notifForUserA = AppNotification(
        id: 'notif_approve_mat_1',
        type: NotificationType.materialApproved,
        senderName: 'Admin',
        resourceTitle: 'Linear Algebra Notes',
        timestamp: DateTime.now(),
        materialId: 'mat_1',
        target: 'user_A',
      );

      final globalNotif = AppNotification(
        id: 'notif_global_1',
        type: NotificationType.adminAnnouncement,
        senderName: 'Admin',
        resourceTitle: 'Maintenance Notice',
        timestamp: DateTime.now(),
        target: 'all',
      );

      // 1. When current user is user_A: receives both personal and global
      service.setTestUserId('user_A');
      service.handleTestSnapshot([notifForUserA, globalNotif]);

      expect(service.notifications.length, 2);
      expect(service.notifications.any((n) => n.id == 'notif_approve_mat_1'), true);
      expect(service.notifications.any((n) => n.id == 'notif_global_1'), true);

      // 2. When current user is user_B: only receives global, personal for user_A is ignored
      NotificationService.resetInstance();
      final serviceB = NotificationService();
      serviceB.setInitialLoadComplete();
      serviceB.setTestUserId('user_B');
      serviceB.handleTestSnapshot([notifForUserA, globalNotif]);

      expect(serviceB.notifications.length, 1);
      expect(serviceB.notifications.first.id, 'notif_global_1');
    });

    test('addModerationNotification sets deterministic ID and target', () {
      final service = NotificationService();
      service.addModerationNotification(
        type: NotificationType.materialApproved,
        resourceTitle: 'Computer Networks',
        id: 'notif_approve_net101',
        materialId: 'net101',
        remark: 'Great notes!',
        target: 'uploader_456',
      );

      final notif = service.notifications.firstWhere((n) => n.id == 'notif_approve_net101');
      expect(notif.type, NotificationType.materialApproved);
      expect(notif.target, 'uploader_456');
      expect(notif.remark, 'Great notes!');
      expect(notif.materialId, 'net101');
    });
  });

  group('ChatService Lifecycle & State Tests', () {
    test('ChatService is a singleton and clear resets state cleanly', () {
      final instance1 = ChatService();
      final instance2 = ChatService();
      expect(identical(instance1, instance2), true);

      expect(instance1.unreadCount, 0);

      instance1.clear();
      expect(instance1.messages.isEmpty, true);
      expect(instance1.isAdminTyping, false);
      expect(instance1.unreadCount, 0);
    });

    test('Message model correctly supports optimistic admin sending and reply fields', () {
      final now = DateTime.now();
      final optimisticMsg = Message(
        id: 'msg_temp_123',
        text: 'Hello from admin',
        isMe: true,
        timestamp: now,
        status: MessageStatus.sent,
        replyToId: 'user_msg_99',
        replyText: 'Can you help me?',
        senderRole: 'admin',
      );

      expect(optimisticMsg.id, 'msg_temp_123');
      expect(optimisticMsg.isMe, true);
      expect(optimisticMsg.senderRole, 'admin');
      expect(optimisticMsg.replyToId, 'user_msg_99');
      expect(optimisticMsg.replyText, 'Can you help me?');
      expect(optimisticMsg.status, MessageStatus.sent);
    });

    test('Message reconciliation drops optimistic local message once confirmed by remote', () {
      final now = DateTime.now();
      final pendingLocal = [
        Message(
          id: 'temp_1',
          text: 'Sending...',
          isMe: true,
          timestamp: now,
          status: MessageStatus.sent,
        ),
      ];

      final remoteMessages = [
        Message(
          id: 'temp_1', // Now confirmed by server with same id
          text: 'Sending...',
          isMe: true,
          timestamp: now,
          status: MessageStatus.delivered,
        ),
      ];

      final remoteIds = remoteMessages.map((m) => m.id).toSet();
      final unresolvedLocal = pendingLocal.where((m) => m.isMe && !remoteIds.contains(m.id)).toList();

      final merged = [...remoteMessages, ...unresolvedLocal];
      expect(merged.length, 1);
      expect(merged.first.status, MessageStatus.delivered);
    });
  });
}
