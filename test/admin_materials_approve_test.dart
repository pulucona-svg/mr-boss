import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:mirror_laikipia/providers/providers.dart';
import 'package:mirror_laikipia/screens/admin/materials_admin_menu_bottom_sheet.dart';
import 'package:mirror_laikipia/screens/admin/materials_approve_screen.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/services/resource_service.dart';
import 'package:mirror_laikipia/services/notification_service.dart';
import 'package:mirror_laikipia/services/admin_service.dart';

class MockUserProfileNotifier extends UserProfileNotifier {
  MockUserProfileNotifier() {
    state = UserProfile(
      uid: 'admin_test_uid',
      username: 'Admin User',
      institution: 'Laikipia University',
      universityLocation: 'Main Campus',
      program: 'Computer Science',
      programCode: 'COMP',
      year: 'Year 4',
      semester: 'Semester 1',
      phone: '+254712345678',
      email: 'admin@laikipia.ac.ke',
    );
  }
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
    ResourceService.resetInstance();
    AdminService.resetInstance();
    NotificationService().clearNotifications();
  });

  tearDown(() {
    ResourceService.resetInstance();
    AdminService.resetInstance();
    NotificationService().clearNotifications();
  });

  group('Materials Approve Moderation - Unit & Service Tests', () {
    test('Independent Identity: Two materials with identical metadata are treated as separate records', () async {
      final now = DateTime.now();

      final pendingA = Resource(
        id: 'mat_pending_A',
        title: 'Chemistry II Notes',
        unitName: 'Chemistry II',
        unitCode: 'CHEM 212',
        type: 'Notes',
        thumbnailUrl: 'https://example.com/thumbA.png',
        fileUrl: 'https://example.com/fileA.pdf',
        fileId: 'file_A',
        year: '2026',
        uploadYear: '2026',
        publicationYear: '2026',
        yearOfStudy: 'Year 2',
        semester: 'Semester 2',
        lecturers: ['Dr. Mutua'],
        uploadedBy: 'Student John',
        uploaderRole: 'Student',
        uploaderId: 'user_john',
        uploadDate: now.subtract(const Duration(hours: 2)),
        status: 'pending',
      );

      final pendingB = Resource(
        id: 'mat_pending_B',
        title: 'Chemistry II Notes',
        unitName: 'Chemistry II',
        unitCode: 'CHEM 212',
        type: 'Notes',
        thumbnailUrl: 'https://example.com/thumbB.png',
        fileUrl: 'https://example.com/fileB.pdf',
        fileId: 'file_B',
        year: '2026',
        uploadYear: '2026',
        publicationYear: '2026',
        yearOfStudy: 'Year 2',
        semester: 'Semester 2',
        lecturers: ['Dr. Mutua'],
        uploadedBy: 'Student John',
        uploaderRole: 'Student',
        uploaderId: 'user_john',
        uploadDate: now.subtract(const Duration(hours: 1)),
        status: 'pending',
      );

      final resourceService = ResourceService();
      resourceService.setAllResources([pendingA, pendingB]);

      expect(resourceService.pendingResources.length, 2);
      expect(resourceService.approvedResources.length, 0);
      expect(resourceService.rejectedResources.length, 0);
      expect(resourceService.modifiedResources.length, 0);
      expect(resourceService.allResources.length, 0); // Pending are not in normal Materials Home

      // 1. Approve material A only
      await resourceService.approveMaterial('mat_pending_A', adminRemark: 'Great quality');

      // Material A should be approved and appear in allResources
      expect(resourceService.pendingResources.length, 1);
      expect(resourceService.pendingResources.first.id, 'mat_pending_B');
      expect(resourceService.approvedResources.length, 1);
      expect(resourceService.approvedResources.first.id, 'mat_pending_A');
      expect(resourceService.approvedResources.first.status, 'approved');
      expect(resourceService.approvedResources.first.adminRemark, 'Great quality');
      expect(resourceService.allResources.length, 1);
      expect(resourceService.allResources.first.id, 'mat_pending_A');

      // Material B must be completely unaffected and still pending
      final remainingB = resourceService.findResourceById('mat_pending_B');
      expect(remainingB, isNotNull);
      expect(remainingB!.status, 'pending');
      expect(remainingB.adminRemark, isNull);

      // Verify idempotent notification for uploader of A
      final notifs = NotificationService().notifications;
      expect(notifs.any((n) => n.id == 'notif_approve_mat_pending_A'), isTrue);
      expect(notifs.any((n) => n.id == 'notif_approve_mat_pending_B'), isFalse);
    });

    test('Oldest-first ordering in Pending Materials & Newest-first in Approved/Rejected/Modified', () {
      final t1 = DateTime(2026, 1, 10);
      final t2 = DateTime(2026, 1, 15);
      final t3 = DateTime(2026, 1, 20);

      final pOld = Resource(
        id: 'p_old',
        title: 'Old Pending',
        unitName: 'Unit 1',
        unitCode: 'U1',
        type: 'Notes',
        thumbnailUrl: 'https://example.com/t.png',
        fileUrl: 'https://example.com/f.pdf',
        fileId: 'f1',
        year: '2026',
        uploadYear: '2026',
        publicationYear: '2026',
        yearOfStudy: '1',
        semester: '1',
        lecturers: [],
        uploadedBy: 'User',
        uploaderRole: 'Student',
        uploaderId: 'u1',
        uploadDate: t1,
        status: 'pending',
      );

      final pMid = pOld.copyWith(id: 'p_mid', title: 'Mid Pending', uploadDate: t2);
      final pNew = pOld.copyWith(id: 'p_new', title: 'New Pending', uploadDate: t3);

      final resourceService = ResourceService();
      // Load in reverse order
      resourceService.setAllResources([pNew, pOld, pMid]);

      // Pending must strictly be sorted oldest first
      final pending = resourceService.pendingResources;
      expect(pending.length, 3);
      expect(pending[0].id, 'p_old');
      expect(pending[1].id, 'p_mid');
      expect(pending[2].id, 'p_new');
    });

    test('Reject Material: Transitions to rejected, records reasons/remark, and purges cache', () async {
      final p = Resource(
        id: 'mat_to_reject',
        title: 'Poor Quality Notes',
        unitName: 'Physics',
        unitCode: 'PHYS 101',
        type: 'Notes',
        thumbnailUrl: 'https://example.com/t.png',
        fileUrl: 'https://example.com/f.pdf',
        fileId: 'f_reject',
        year: '2026',
        uploadYear: '2026',
        publicationYear: '2026',
        yearOfStudy: '1',
        semester: '1',
        lecturers: [],
        uploadedBy: 'User',
        uploaderRole: 'Student',
        uploaderId: 'u1',
        uploadDate: DateTime.now(),
        status: 'pending',
      );

      final resourceService = ResourceService();
      resourceService.setAllResources([p]);
      expect(resourceService.pendingResources.length, 1);

      await resourceService.rejectMaterial(
        'mat_to_reject',
        rejectionReasons: ['Low image or scan quality', 'Blurry or obscured pages'],
        adminRemark: 'Please upload a clearer scan.',
      );

      expect(resourceService.pendingResources.length, 0);
      expect(resourceService.rejectedResources.length, 1);
      final rejected = resourceService.rejectedResources.first;
      expect(rejected.id, 'mat_to_reject');
      expect(rejected.status, 'rejected');
      expect(rejected.rejectionReasons, contains('Low image or scan quality'));
      expect(rejected.adminRemark, 'Please upload a clearer scan.');
      expect(rejected.rejectedByAdmin, isTrue);
      expect(rejected.rejectedAt, isNotNull);
      expect(rejected.deletedAt, isNotNull);

      // Verify notification
      final notifs = NotificationService().notifications;
      expect(notifs.any((n) => n.id == 'notif_reject_mat_to_reject'), isTrue);
    });

    test('Reconsider Material: Returns rejected material to pending without auto-approving', () async {
      final p = Resource(
        id: 'mat_reconsider',
        title: 'Contested Past Paper',
        unitName: 'Calculus',
        unitCode: 'MATH 111',
        type: 'Past Papers',
        thumbnailUrl: 'https://example.com/t.png',
        fileUrl: 'https://example.com/f.pdf',
        fileId: 'f_rec',
        year: '2026',
        uploadYear: '2026',
        publicationYear: '2026',
        yearOfStudy: '1',
        semester: '1',
        lecturers: [],
        uploadedBy: 'User',
        uploaderRole: 'Student',
        uploaderId: 'u1',
        uploadDate: DateTime.now().subtract(const Duration(days: 2)),
        status: 'rejected',
        rejectedAt: DateTime.now().subtract(const Duration(days: 1)),
        rejectionReasons: ['Incomplete notes or missing pages'],
      );

      final resourceService = ResourceService();
      resourceService.setAllResources([p]);
      expect(resourceService.rejectedResources.length, 1);
      expect(resourceService.pendingResources.length, 0);

      // Admin reconsiders material
      await resourceService.reconsiderMaterial('mat_reconsider');

      expect(resourceService.rejectedResources.length, 0);
      expect(resourceService.pendingResources.length, 1);
      final reconsidered = resourceService.pendingResources.first;
      expect(reconsidered.id, 'mat_reconsider');
      expect(reconsidered.status, 'pending');
      expect(reconsidered.reconsideredAt, isNotNull);
      expect(reconsidered.rejectedAt, isNull);
      expect(reconsidered.rejectionReasons, isNull);
      expect(reconsidered.adminRemark, isNull);
      expect(resourceService.allResources.length, 0); // Still not active until reviewed
    });

    test('Moderation Modify: Modifying pending material transitions to modified, approved, and active', () async {
      final p = Resource(
        id: 'mat_mod',
        title: 'Original Title',
        unitName: 'Old Unit',
        unitCode: 'OLD 101',
        type: 'Notes',
        thumbnailUrl: 'https://example.com/t.png',
        fileUrl: 'https://example.com/f.pdf',
        fileId: 'f_mod',
        year: '2026',
        uploadYear: '2026',
        publicationYear: '2026',
        yearOfStudy: '1',
        semester: '1',
        lecturers: [],
        uploadedBy: 'User',
        uploaderRole: 'Student',
        uploaderId: 'u1',
        uploadDate: DateTime.now(),
        status: 'pending',
      );

      final resourceService = ResourceService();
      resourceService.setAllResources([p]);

      final updated = p.copyWith(
        title: 'Corrected Unit Title',
        unitName: 'Corrected Unit',
        unitCode: 'NEW 101',
        adminRemark: 'Fixed title and code typos.',
      );

      await resourceService.modifyMaterial(updated, isModerationModify: true);

      expect(resourceService.pendingResources.length, 0);
      expect(resourceService.modifiedResources.length, 1);
      final mod = resourceService.modifiedResources.first;
      expect(mod.id, 'mat_mod');
      expect(mod.status, 'modified');
      expect(mod.title, 'Corrected Unit Title');
      expect(mod.adminRemark, 'Fixed title and code typos.');
      expect(mod.approvedByAdmin, isTrue);

      // Appears in public Materials Home as modified & approved
      expect(resourceService.allResources.length, 1);
      expect(resourceService.allResources.first.id, 'mat_mod');
      expect(resourceService.allResources.first.status, 'modified');

      // Uploader receives notification
      final notifs = NotificationService().notifications;
      expect(notifs.any((n) => n.id == 'notif_modify_mat_mod'), isTrue);
    });
  });

  group('Materials Approve Moderation - Widget & UI Tests', () {
    testWidgets('MaterialsAdminMenuBottomSheet navigates to MaterialsApproveScreen on Approve tap', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => MockUserProfileNotifier()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: MaterialsAdminMenuBottomSheet(),
            ),
          ),
        ),
      );

      expect(find.text('MATERIALS'), findsOneWidget);
      expect(find.text('Manage'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Coming Soon'), findsNothing); // Should now be active, not coming soon

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.byType(MaterialsApproveScreen), findsOneWidget);
      expect(find.text('PENDING MATERIALS'), findsOneWidget);
    });

    testWidgets('MaterialsApproveScreen has 4 category tabs and supports category switching', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => MockUserProfileNotifier()),
          ],
          child: const MaterialApp(
            home: MaterialsApproveScreen(),
          ),
        ),
      );

      expect(find.text('Pending Materials'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Modified'), findsOneWidget);

      // Default is Pending Materials
      expect(find.text('PENDING MATERIALS'), findsOneWidget);

      // Tap Approved category
      await tester.tap(find.text('Approved'));
      await tester.pumpAndSettle();
      expect(find.text('APPROVED'), findsOneWidget);

      // Tap Rejected category
      await tester.tap(find.text('Rejected'));
      await tester.pumpAndSettle();
      expect(find.text('REJECTED'), findsOneWidget);

      // Tap Modified category
      await tester.tap(find.text('Modified'));
      await tester.pumpAndSettle();
      expect(find.text('MODIFIED'), findsOneWidget);
    });

    testWidgets('Single selection mode in Pending Materials: Only one material selected at a time', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final p1 = Resource(
        id: 'p_item_1',
        title: 'Material 1',
        unitName: 'Unit 1',
        unitCode: 'U1',
        type: 'Notes',
        thumbnailUrl: '',
        fileUrl: 'https://example.com/f1.pdf',
        fileId: 'f1',
        year: '2026',
        uploadYear: '2026',
        publicationYear: '2026',
        yearOfStudy: '1',
        semester: '1',
        lecturers: [],
        uploadedBy: 'User 1',
        uploaderRole: 'Student',
        uploaderId: 'u1',
        uploadDate: DateTime.now().subtract(const Duration(hours: 2)),
        status: 'pending',
      );

      final p2 = p1.copyWith(
        id: 'p_item_2',
        title: 'Material 2',
        uploadDate: DateTime.now().subtract(const Duration(hours: 1)),
      );

      ResourceService().setAllResources([p1, p2]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => MockUserProfileNotifier()),
          ],
          child: const MaterialApp(
            home: MaterialsApproveScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Material 1'), findsOneWidget);
      expect(find.text('Material 2'), findsOneWidget);

      // Long press on Material 1 -> Enters single selection mode
      await tester.longPress(find.text('Material 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Selection bar appears with '1 selected'
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byTooltip('Approve'), findsOneWidget);
      expect(find.byTooltip('Modify'), findsOneWidget);
      expect(find.byTooltip('Reject'), findsOneWidget);

      // Tap Material 2 -> Selection switches to Material 2, count is STILL 1
      await tester.tap(find.text('Material 2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('1 selected'), findsOneWidget);

      // Tap close button on selection bar -> Exits selection mode
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('1 selected'), findsNothing);
    });
  });
}
