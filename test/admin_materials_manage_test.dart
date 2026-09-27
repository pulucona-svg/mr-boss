import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:mirror_laikipia/providers/providers.dart';
import 'package:mirror_laikipia/screens/admin/materials_admin_menu_bottom_sheet.dart';
import 'package:mirror_laikipia/screens/dashboard_screen.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/services/resource_service.dart';
import 'package:mirror_laikipia/services/download_service.dart';
import 'package:mirror_laikipia/services/view_service.dart';
import 'package:mirror_laikipia/services/comment_service.dart';
import 'package:mirror_laikipia/services/admin_service.dart';
import 'package:mirror_laikipia/widgets/resource_card.dart';

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

  final testResource1 = Resource(
    id: 'mat_1',
    title: 'Advanced Operating Systems Notes',
    unitName: 'Operating Systems',
    unitCode: 'COMP 311',
    type: 'Notes',
    thumbnailUrl: 'https://example.com/thumb1.png',
    fileUrl: 'https://example.com/file1.pdf',
    fileId: 'file_1',
    lecturers: ['Dr. Smith'],
    targetPrograms: ['Computer Science'],
    programCodes: ['COMP'],
    year: '2025',
    uploadYear: '2025',
    publicationYear: '2024',
    yearOfStudy: 'Year 3',
    semester: 'Semester 1',
    uploadedBy: 'Admin',
    uploaderRole: 'Lecturer',
    uploaderId: 'admin_test_uid',
    views: 10,
    likes: 5,
    comments: 0,
    materialFormat: 'PDF',
    isLiked: false,
    uploadDate: DateTime(2025, 1, 1),
  );

  final testResource2 = Resource(
    id: 'mat_2',
    title: 'Computer Networks CAT 1',
    unitName: 'Computer Networks',
    unitCode: 'COMP 312',
    type: 'CATs',
    thumbnailUrl: 'https://example.com/thumb2.png',
    fileUrl: 'https://example.com/file2.pdf',
    fileId: 'file_2',
    lecturers: ['Prof. Davis'],
    targetPrograms: ['Computer Science'],
    programCodes: ['COMP'],
    year: '2025',
    uploadYear: '2025',
    publicationYear: '2024',
    yearOfStudy: 'Year 3',
    semester: 'Semester 1',
    uploadedBy: 'Admin',
    uploaderRole: 'Lecturer',
    uploaderId: 'admin_test_uid',
    views: 15,
    likes: 8,
    comments: 0,
    materialFormat: 'PDF',
    isLiked: false,
    uploadDate: DateTime(2025, 1, 2),
  );

  setUp(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
    ResourceService.resetInstance();
    DownloadService.resetInstance();
    ViewService.resetInstance();
    CommentService.resetInstance();
    AdminService.resetInstance();
    ResourceService().setAllResources([testResource1, testResource2]);
    DashboardScreen.resetLoadedState(loaded: true);
  });

  Widget buildTestApp(Widget home) {
    return ProviderScope(
      overrides: [
        userProfileProvider.overrideWith((ref) => MockUserProfileNotifier()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: home,
        ),
      ),
    );
  }

  group('Materials Admin Menu & Manage Step 1 Tests', () {
    testWidgets('1. MaterialsAdminMenuBottomSheet contains exactly Manage and Approve', (tester) async {
      await tester.pumpWidget(buildTestApp(const MaterialsAdminMenuBottomSheet()));
      await tester.pumpAndSettle();

      // Check Header
      expect(find.text('MATERIALS'), findsOneWidget);
      expect(find.text('Academic Materials Administration'), findsOneWidget);

      // Check Exactly Manage and Approve
      expect(find.text('Manage'), findsOneWidget);
      expect(find.text('Open Materials Home to organize and manage materials'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Coming Soon'), findsOneWidget);
    });

    testWidgets('2. Tapping Manage opens DashboardScreen in Admin Mode', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  builder: (_) => const MaterialsAdminMenuBottomSheet(),
                );
              },
              child: const Text('Open Menu'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open bottom sheet
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      // Tap Manage
      await tester.tap(find.text('Manage'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verifies existing Materials Home (Dashboard) is opened
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Advanced Operating Systems Notes'), findsOneWidget);
      expect(find.byType(DashboardScreen), findsOneWidget);
    });

    testWidgets('3. Normal user (isAdminMode: false) long-press does NOT enter selection mode', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp(const DashboardScreen(isAdminMode: false)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Cards are rendered
      final cardFinder = find.byType(ResourceCard).first;
      expect(cardFinder, findsOneWidget);

      // Long press card as normal user
      await tester.longPress(cardFinder, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify NO selection mode, NO selection bar, NO check icon
      expect(find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.check && w.size == 16), findsNothing);
      expect(find.byType(SliverPersistentHeader), findsNothing);
    });

    testWidgets('4. Admin mode (isAdminMode: true) long-press enters selection mode with highlighting & action bar', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp(const DashboardScreen(isAdminMode: true)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Find the first material card
      final firstCardFinder = find.byType(ResourceCard).first;
      expect(firstCardFinder, findsOneWidget);

      // Long press as admin
      await tester.longPress(firstCardFinder, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final checkFinder = find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.check && w.size == 16);

      // Selection mode active: Check mark appears on selected card
      expect(checkFinder, findsOneWidget);
      expect(find.byType(SliverPersistentHeader), findsOneWidget);

      // Selection action bar appears with count '1'
      expect(find.descendant(of: find.byType(SliverPersistentHeader), matching: find.text('1')), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
      expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);

      // Multi-selection: tap the second material card
      final secondCardFinder = find.byType(ResourceCard).last;
      await tester.tap(secondCardFinder, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Count becomes '2' and both show check mark
      expect(find.descendant(of: find.byType(SliverPersistentHeader), matching: find.text('2')), findsOneWidget);
      expect(checkFinder, findsNWidgets(2));

      // Deselect second card
      await tester.tap(secondCardFinder, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.descendant(of: find.byType(SliverPersistentHeader), matching: find.text('1')), findsOneWidget);

      // Tap close on selection bar exits selection mode
      await tester.tap(find.descendant(of: find.byType(SliverPersistentHeader), matching: find.byIcon(Icons.close)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Selection mode exited
      expect(checkFinder, findsNothing);
      expect(find.byType(SliverPersistentHeader), findsNothing);
    });

    testWidgets('5. PopScope cancellation exits selection mode on back', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DashboardScreen(isAdminMode: true),
                  ),
                );
              },
              child: const Text('Open Materials Home'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open DashboardScreen in Admin Mode
      await tester.tap(find.text('Open Materials Home'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final firstCardFinder = find.byType(ResourceCard).first;
      await tester.longPress(firstCardFinder, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.descendant(of: find.byType(SliverPersistentHeader), matching: find.text('1')), findsOneWidget);

      // Simulate back button via back button in header or Navigator pop invoke
      final backButton = find.byTooltip('Back to Admin');
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // First back exits selection mode while remaining on Dashboard
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.check && w.size == 16), findsNothing);

      // Second back pops to previous screen
      await tester.tap(backButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Open Materials Home'), findsOneWidget);
    });

    testWidgets('6. Pin action bar icon pins selected material, moves to top, and unpins on toggle', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp(const DashboardScreen(isAdminMode: true)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Long press second material (Computer Networks CAT 1)
      final netCard = find.text('Computer Networks CAT 1');
      expect(netCard, findsOneWidget);
      await tester.longPress(netCard, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Pin icon is outlined (not yet pinned)
      final pinButtonOutlined = find.byIcon(Icons.push_pin_outlined);
      expect(pinButtonOutlined, findsOneWidget);

      // Tap Pin
      await tester.tap(pinButtonOutlined);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Computer Networks CAT 1 is now pinned and at the top
      expect(ResourceService().isPinned('Computer Networks CAT 1'), isTrue);
      expect(ResourceService().allResources.first.title, 'Computer Networks CAT 1');

      // Select it again to test unpin
      await tester.longPress(find.text('Computer Networks CAT 1'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Pin icon is now solid Icons.push_pin
      final pinButtonSolid = find.byIcon(Icons.push_pin);
      expect(pinButtonSolid, findsOneWidget);

      // Tap Unpin
      await tester.tap(pinButtonSolid);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(ResourceService().isPinned('Computer Networks CAT 1'), isFalse);
    });

    testWidgets('7. Multi-selection preserves pin ordering at the top', (tester) async {
      // Pin in order: Net 1st, OS 2nd
      ResourceService().pinMultiple([
        'Computer Networks CAT 1',
        'Advanced Operating Systems Notes',
      ]);

      expect(ResourceService().isPinned('Computer Networks CAT 1'), isTrue);
      expect(ResourceService().isPinned('Advanced Operating Systems Notes'), isTrue);

      final resources = ResourceService().allResources;
      expect(resources[0].title, 'Computer Networks CAT 1');
      expect(resources[1].title, 'Advanced Operating Systems Notes');
    });

    testWidgets('8. Archive moves material to archives, removes from active, and restore brings it back', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp(const DashboardScreen(isAdminMode: true)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Long press Advanced Operating Systems Notes
      await tester.longPress(find.text('Advanced Operating Systems Notes'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Archive icon
      final archiveButton = find.byIcon(Icons.archive_outlined);
      expect(archiveButton, findsOneWidget);
      await tester.tap(archiveButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Removed from active materials
      expect(ResourceService().allResources.any((r) => r.title == 'Advanced Operating Systems Notes'), isFalse);
      // Added to archives
      expect(ResourceService().archivedUploads.any((r) => r.title == 'Advanced Operating Systems Notes'), isTrue);

      // Restore it
      ResourceService().restoreMultiple(['Advanced Operating Systems Notes']);
      expect(ResourceService().allResources.any((r) => r.title == 'Advanced Operating Systems Notes'), isTrue);
      expect(ResourceService().archivedUploads.any((r) => r.title == 'Advanced Operating Systems Notes'), isFalse);
    });

    testWidgets('9. Delete icon exists beside Archive, moves to Trash, and restore brings it back', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp(const DashboardScreen(isAdminMode: true)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Long press Advanced Operating Systems Notes
      await tester.longPress(find.text('Advanced Operating Systems Notes'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Both Archive and Delete icons exist in selection bar
      expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
      final deleteButton = find.byIcon(Icons.delete_outline);
      expect(deleteButton, findsOneWidget);

      // Tap Delete
      await tester.tap(deleteButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Removed from active materials
      expect(ResourceService().allResources.any((r) => r.title == 'Advanced Operating Systems Notes'), isFalse);
      // Added to Trash
      expect(ResourceService().trashedUploads.any((item) => (item['resource'] as Resource).title == 'Advanced Operating Systems Notes'), isTrue);

      // Restore from Trash
      ResourceService().restoreMultiple(['Advanced Operating Systems Notes']);
      expect(ResourceService().allResources.any((r) => r.title == 'Advanced Operating Systems Notes'), isTrue);
      expect(ResourceService().trashedUploads.any((item) => (item['resource'] as Resource).title == 'Advanced Operating Systems Notes'), isFalse);
    });

    testWidgets('10. Critical Security Requirement: Archiving or Trashing purges user offline downloads upon server sync', (tester) async {
      // Simulate normal user with two downloaded resources
      DownloadService().addDownloadedResourceForTesting({'title': 'Advanced Operating Systems Notes'});
      DownloadService().addDownloadedResourceForTesting({'title': 'Computer Networks CAT 1'});

      expect(DownloadService().isDownloaded('Advanced Operating Systems Notes'), isTrue);
      expect(DownloadService().isDownloaded('Computer Networks CAT 1'), isTrue);

      // Admin archives 'Advanced Operating Systems Notes'
      ResourceService().archiveMultiple(['Advanced Operating Systems Notes']);

      // The archived material is immediately purged from user's downloads
      expect(DownloadService().isDownloaded('Advanced Operating Systems Notes'), isFalse);
      // Unrelated material remains completely unaffected
      expect(DownloadService().isDownloaded('Computer Networks CAT 1'), isTrue);

      // Admin trashes 'Computer Networks CAT 1'
      ResourceService().deleteMultiple(['Computer Networks CAT 1']);
      expect(DownloadService().isDownloaded('Computer Networks CAT 1'), isFalse);
    });

    testWidgets('11. 3-dot menu contains Archives, Trash, and Select All', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp(const DashboardScreen(isAdminMode: true)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.longPress(find.text('Advanced Operating Systems Notes'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap 3-dot popup menu on the selection bar
      final moreButton = find.descendant(
        of: find.byType(SliverPersistentHeader),
        matching: find.byIcon(Icons.more_vert),
      );
      expect(moreButton, findsOneWidget);
      await tester.tap(moreButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Archives'), findsOneWidget);
      expect(find.text('Trash'), findsOneWidget);
      expect(find.text('Select All'), findsOneWidget);

      // Tap Select All
      await tester.tap(find.text('Select All'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Selection count should now be 2
      expect(find.descendant(of: find.byType(SliverPersistentHeader), matching: find.text('2')), findsOneWidget);
    });
  });
}
