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
import 'package:mirror_laikipia/widgets/resource_details_modal.dart';
import 'package:mirror_laikipia/screens/archive_trash_screen.dart';
import 'package:mirror_laikipia/screens/material_viewer_screen.dart';

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
      expect(find.text('Review, approve, modify, or reject user-uploaded materials'), findsOneWidget);
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

    testWidgets('12. Action Bar Modify Icon appears ONLY when exactly 1 material is selected and disappears when count is 0 or 2+', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp(const DashboardScreen(isAdminMode: true)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Initially no selection -> Modify icon does not exist
      expect(find.byIcon(Icons.edit_outlined), findsNothing);

      // Long press first item -> 1 selected
      await tester.longPress(find.text('Advanced Operating Systems Notes'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Modify icon MUST appear when exactly 1 material is selected
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

      // Verify the selection bar children order: Close, Count, Pin, Archive, Delete, Modify, 3-dot
      final headerFinder = find.byType(SliverPersistentHeader);
      expect(find.descendant(of: headerFinder, matching: find.byIcon(Icons.close)), findsOneWidget);
      expect(find.descendant(of: headerFinder, matching: find.byIcon(Icons.archive_outlined)), findsOneWidget);
      expect(find.descendant(of: headerFinder, matching: find.byIcon(Icons.delete_outline)), findsOneWidget);
      expect(find.descendant(of: headerFinder, matching: find.byIcon(Icons.edit_outlined)), findsOneWidget);
      expect(find.descendant(of: headerFinder, matching: find.byIcon(Icons.more_vert)), findsOneWidget);

      // Tap second item -> 2 selected -> Modify icon MUST disappear immediately
      await tester.tap(find.text('Computer Networks CAT 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.descendant(of: headerFinder, matching: find.text('2')), findsOneWidget);

      // Deselect second item -> back to 1 selected -> Modify icon reappears
      await tester.tap(find.text('Computer Networks CAT 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.descendant(of: headerFinder, matching: find.text('1')), findsOneWidget);

      // Deselect first item -> 0 selected -> selection mode exits, Modify icon gone
      await tester.tap(find.text('Advanced Operating Systems Notes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('13. Identical Metadata Isolation: Modifying, Archiving, Deleting Material A affects ONLY Material A by unique ID and leaves Material B untouched', (tester) async {
      // Create two materials with IDENTICAL metadata but unique IDs
      final chemA = Resource(
        id: 'chem_a',
        title: 'Chemistry II Notes',
        unitName: 'Chemistry II',
        unitCode: 'CHEM 212',
        type: 'Notes',
        thumbnailUrl: 'https://example.com/chem_a_thumb.png',
        fileUrl: 'https://example.com/chem_a_doc.pdf',
        fileId: 'file_chem_a',
        thumbnailId: 'thumb_chem_a',
        lecturers: ['Dr. Mole'],
        targetPrograms: ['Chemistry'],
        programCodes: ['CHEM'],
        year: '2026',
        uploadYear: '2026',
        publicationYear: '2026',
        yearOfStudy: 'Year 2',
        semester: 'Semester 2',
        uploadedBy: 'Student John',
        uploaderRole: 'Student',
        uploaderId: 'user_john',
        views: 2,
        likes: 1,
        uploadDate: DateTime(2026, 1, 10),
      );

      final chemB = Resource(
        id: 'chem_b',
        title: 'Chemistry II Notes',
        unitName: 'Chemistry II',
        unitCode: 'CHEM 212',
        type: 'Notes',
        thumbnailUrl: 'https://example.com/chem_b_thumb.png',
        fileUrl: 'https://example.com/chem_b_doc.pdf',
        fileId: 'file_chem_b',
        thumbnailId: 'thumb_chem_b',
        lecturers: ['Dr. Mole'],
        targetPrograms: ['Chemistry'],
        programCodes: ['CHEM'],
        year: '2026',
        uploadYear: '2026',
        publicationYear: '2026',
        yearOfStudy: 'Year 2',
        semester: 'Semester 2',
        uploadedBy: 'Student John',
        uploaderRole: 'Student',
        uploaderId: 'user_john',
        views: 5,
        likes: 3,
        uploadDate: DateTime(2026, 1, 12),
      );

      ResourceService().setAllResources([chemA, chemB]);

      expect(ResourceService().allResources.length, 2);
      expect(ResourceService().allResources.where((r) => r.id == 'chem_a').length, 1);
      expect(ResourceService().allResources.where((r) => r.id == 'chem_b').length, 1);

      // 1. MODIFY Material A (change type to CATs, change publication year to 2027)
      final modifiedChemA = chemA.copyWith(
        title: 'Chemistry II CAT 1',
        type: 'CATs',
        publicationYear: '2027',
        updatedByAdmin: true,
        updatedAt: DateTime.now(),
      );
      await ResourceService().modifyMaterial(modifiedChemA);

      // Verify Material A updated
      final currentChemA = ResourceService().allResources.firstWhere((r) => r.id == 'chem_a');
      expect(currentChemA.type, 'CATs');
      expect(currentChemA.publicationYear, '2027');
      expect(currentChemA.title, 'Chemistry II CAT 1');
      expect(currentChemA.updatedByAdmin, isTrue);

      // Verify Material B is COMPLETELY UNTOUCHED despite having had identical metadata
      final currentChemB = ResourceService().allResources.firstWhere((r) => r.id == 'chem_b');
      expect(currentChemB.type, 'Notes');
      expect(currentChemB.publicationYear, '2026');
      expect(currentChemB.title, 'Chemistry II Notes');
      expect(currentChemB.updatedByAdmin, isFalse);

      // 2. ARCHIVE Material A by ID
      ResourceService().archiveMaterialsById(['chem_a']);

      // Material A is in archives, NOT active
      expect(ResourceService().allResources.any((r) => r.id == 'chem_a'), isFalse);
      expect(ResourceService().archivedUploads.any((r) => r.id == 'chem_a'), isTrue);

      // Material B remains ACTIVE and untouched
      expect(ResourceService().allResources.any((r) => r.id == 'chem_b'), isTrue);
      expect(ResourceService().archivedUploads.any((r) => r.id == 'chem_b'), isFalse);

      // 3. DELETE Material B by ID
      ResourceService().deleteMaterialsById(['chem_b']);

      // Material B is in trash, NOT active
      expect(ResourceService().allResources.any((r) => r.id == 'chem_b'), isFalse);
      expect(ResourceService().trashedUploads.any((item) => (item['resource'] as Resource).id == 'chem_b'), isTrue);

      // Restore Material A from Archives
      ResourceService().restoreMaterialsById(['chem_a']);
      expect(ResourceService().allResources.any((r) => r.id == 'chem_a'), isTrue);

      // Permanently delete Material B from Trash
      ResourceService().permanentlyDeleteMaterialsById(['chem_b']);
      expect(ResourceService().trashedUploads.any((item) => (item['resource'] as Resource).id == 'chem_b'), isFalse);
      // Material A remains alive and active
      expect(ResourceService().allResources.any((r) => r.id == 'chem_a'), isTrue);
    });

    testWidgets('14. PDF replacement and cache reconciliation updates only target material downloads', (tester) async {
      DownloadService().addDownloadedResourceForTesting({
        'id': 'chem_a',
        'title': 'Chemistry II Notes',
        'fileUrl': 'https://example.com/chem_a_doc.pdf',
        'thumbnailUrl': 'https://example.com/chem_a_thumb.png',
      });
      DownloadService().addDownloadedResourceForTesting({
        'id': 'chem_b',
        'title': 'Chemistry II Notes',
        'fileUrl': 'https://example.com/chem_b_doc.pdf',
        'thumbnailUrl': 'https://example.com/chem_b_thumb.png',
      });

      expect(DownloadService().downloadedResources.length, 2);

      // Replace chem_a's PDF fileUrl
      final updatedChemA = Resource(
        id: 'chem_a',
        title: 'Chemistry II Notes',
        unitName: 'Chemistry II',
        unitCode: 'CHEM 212',
        type: 'Notes',
        thumbnailUrl: 'https://example.com/chem_a_new_thumb.png',
        fileUrl: 'https://example.com/chem_a_new_file.pdf',
        fileId: 'file_chem_a_new',
        year: '2026',
        uploadYear: '2026',
        publicationYear: '2026',
        yearOfStudy: 'Year 2',
        semester: 'Semester 2',
        lecturers: const [],
        uploadedBy: 'Student John',
        uploaderRole: 'Student',
        uploaderId: 'user_john',
        uploadDate: DateTime.now(),
        updatedByAdmin: true,
      );

      DownloadService().reconcileUpdatedResources([updatedChemA]);

      // Verify chem_a's downloaded entry has the new fileUrl & thumbnailUrl
      final chemADownload = DownloadService().downloadedResources.firstWhere((r) => r['id'] == 'chem_a');
      expect(chemADownload['fileUrl'], 'https://example.com/chem_a_new_file.pdf');
      expect(chemADownload['thumbnailUrl'], 'https://example.com/chem_a_new_thumb.png');

      // Verify chem_b's downloaded entry remains UNTOUCHED with old fileUrl
      final chemBDownload = DownloadService().downloadedResources.firstWhere((r) => r['id'] == 'chem_b');
      expect(chemBDownload['fileUrl'], 'https://example.com/chem_b_doc.pdf');
      expect(chemBDownload['thumbnailUrl'], 'https://example.com/chem_b_thumb.png');
    });

    testWidgets('15. ResourceDetailsModal displays (updated by admin) indicator correctly', (tester) async {
      // 1. Named uploader modified by admin
      await tester.pumpWidget(
        buildTestApp(
          const ResourceDetailsModal(
            title: 'Chemistry II Notes',
            type: 'Notes',
            thumbnailUrl: '',
            unitName: 'Chemistry II',
            unitCode: 'CHEM 212',
            materialFormat: 'PDF',
            uploadYear: '2026',
            publicationYear: '2026',
            yearOfStudy: 'Year 2',
            semester: 'Semester 2',
            lecturers: ['Dr. Mole'],
            uploadedBy: 'Alice',
            uploaderRole: 'Student',
            fileUrl: 'https://example.com/chem.pdf',
            updatedByAdmin: true,
            isAnonymous: false,
          ),
        ),
      );
      await tester.pump();

      // Must display "[Original Uploader] (updated by admin)"
      expect(find.text('Alice (updated by admin)'), findsOneWidget);

      // 2. Anonymous uploader modified by admin
      await tester.pumpWidget(
        buildTestApp(
          const ResourceDetailsModal(
            title: 'Chemistry II Notes',
            type: 'Notes',
            thumbnailUrl: '',
            unitName: 'Chemistry II',
            unitCode: 'CHEM 212',
            materialFormat: 'PDF',
            uploadYear: '2026',
            publicationYear: '2026',
            yearOfStudy: 'Year 2',
            semester: 'Semester 2',
            lecturers: ['Dr. Mole'],
            uploadedBy: 'Alice',
            uploaderRole: 'Student',
            fileUrl: 'https://example.com/chem.pdf',
            updatedByAdmin: true,
            isAnonymous: true,
          ),
        ),
      );
      await tester.pump();

      // Must display "Anonymous (updated by admin)"
      expect(find.text('Anonymous (updated by admin)'), findsOneWidget);

      // 3. Material NOT modified by admin
      await tester.pumpWidget(
        buildTestApp(
          const ResourceDetailsModal(
            title: 'Chemistry II Notes',
            type: 'Notes',
            thumbnailUrl: '',
            unitName: 'Chemistry II',
            unitCode: 'CHEM 212',
            materialFormat: 'PDF',
            uploadYear: '2026',
            publicationYear: '2026',
            yearOfStudy: 'Year 2',
            semester: 'Semester 2',
            lecturers: ['Dr. Mole'],
            uploadedBy: 'Alice',
            uploaderRole: 'Student',
            fileUrl: 'https://example.com/chem.pdf',
            updatedByAdmin: false,
            isAnonymous: false,
          ),
        ),
      );
      await tester.pump();

      // Does not contain (updated by admin)
      expect(find.text('Alice (updated by admin)'), findsNothing);
      expect(find.text('Alice (Student)'), findsOneWidget);
    });

    testWidgets('16. Selection bar fits with zero overflow when Modify icon is visible on mobile width (390px)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp(const DashboardScreen(isAdminMode: true)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Long press first item to select 1 material -> Modify icon shown
      final firstCardFinder = find.byType(ResourceCard).first;
      await tester.longPress(firstCardFinder, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Modify icon is present
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

      // Verify zero Flutter layout overflow anywhere
      expect(tester.takeException(), isNull);
    });

    testWidgets('17. Archives list: Modify icon appears ONLY when exactly 1 material is selected and disappears when 0 or 2+', (tester) async {
      final arch1 = testResource1.copyWith(id: 'arch_1', title: 'Archived Notes 1', status: 'archived');
      final arch2 = testResource2.copyWith(id: 'arch_2', title: 'Archived Notes 2', status: 'archived');
      ResourceService().setAllResources([arch1, arch2]);

      expect(ResourceService().archivedUploads.length, 2);

      await tester.pumpWidget(
        buildTestApp(
          const ArchiveTrashScreen(
            isDownloads: false,
            isTrash: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 0 selected: Modify icon not present
      expect(find.byIcon(Icons.edit_outlined), findsNothing);

      // Long press first item -> 1 selected
      await tester.longPress(find.text('Archived Notes 1'));
      await tester.pumpAndSettle();

      // Modify icon MUST appear
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);

      // Tap second item -> 2 selected
      await tester.tap(find.text('Archived Notes 2'));
      await tester.pumpAndSettle();

      // Modify icon MUST disappear
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.text('2 selected'), findsOneWidget);

      // Deselect second item -> 1 selected
      await tester.tap(find.text('Archived Notes 2'));
      await tester.pumpAndSettle();

      // Modify icon reappears
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);

      // Tap close -> 0 selected
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('18. Archives list: Modifying an archived material updates document in place by unique ID, remains in Archives, and does NOT appear in active Materials', (tester) async {
      final arch1 = testResource1.copyWith(id: 'arch_target', title: 'Original Archived Material', status: 'archived');
      ResourceService().setAllResources([arch1]);

      expect(ResourceService().archivedUploads.length, 1);
      expect(ResourceService().allResources.length, 0);

      // Modify the archived material
      final modifiedArch = arch1.copyWith(
        title: 'Updated Archived Material',
        unitName: 'Updated Unit',
        publicationYear: '2026',
        updatedByAdmin: true,
      );
      await ResourceService().modifyMaterial(modifiedArch);

      // Verify updated in place in Archives
      expect(ResourceService().archivedUploads.length, 1);
      final current = ResourceService().archivedUploads.first;
      expect(current.id, 'arch_target');
      expect(current.title, 'Updated Archived Material');
      expect(current.unitName, 'Updated Unit');
      expect(current.publicationYear, '2026');
      expect(current.status, 'archived');
      expect(current.updatedByAdmin, isTrue);

      // CRITICAL: Must NOT appear in active Materials Home
      expect(ResourceService().allResources.any((r) => r.id == 'arch_target'), isFalse);
    });

    testWidgets('19. Trash list: Modify icon appears ONLY when exactly 1 material is selected and disappears when 0 or 2+', (tester) async {
      final now = DateTime.now();
      final trash1 = testResource1.copyWith(id: 'trash_1', title: 'Trashed Item 1', status: 'trash', uploadDate: now, deletedAt: now);
      final trash2 = testResource2.copyWith(id: 'trash_2', title: 'Trashed Item 2', status: 'trash', uploadDate: now, deletedAt: now);
      ResourceService().setAllResources([trash1, trash2]);

      expect(ResourceService().trashedUploads.length, 2);

      await tester.pumpWidget(
        buildTestApp(
          const ArchiveTrashScreen(
            isDownloads: false,
            isTrash: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 0 selected: Modify icon not present
      expect(find.byIcon(Icons.edit_outlined), findsNothing);

      // Long press first item -> 1 selected
      await tester.longPress(find.text('Trashed Item 1'));
      await tester.pumpAndSettle();

      // Modify icon MUST appear
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);

      // Tap second item -> 2 selected
      await tester.tap(find.text('Trashed Item 2'));
      await tester.pumpAndSettle();

      // Modify icon MUST disappear
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.text('2 selected'), findsOneWidget);

      // Deselect second item -> 1 selected
      await tester.tap(find.text('Trashed Item 2'));
      await tester.pumpAndSettle();

      // Modify icon reappears
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);

      // Tap close -> 0 selected
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('20. Trash list: Modifying a trashed material updates document in place by unique ID, remains in Trash, retains retention, and does NOT appear in active Materials', (tester) async {
      final now = DateTime.now();
      final trash1 = testResource1.copyWith(id: 'trash_target', title: 'Original Trashed Material', status: 'trash', uploadDate: now, deletedAt: now);
      ResourceService().setAllResources([trash1]);

      expect(ResourceService().trashedUploads.length, 1);
      expect(ResourceService().allResources.length, 0);

      // Modify the trashed material
      final modifiedTrash = trash1.copyWith(
        title: 'Updated Trashed Material',
        unitCode: 'COMP 999',
        publicationYear: '2026',
        updatedByAdmin: true,
      );
      await ResourceService().modifyMaterial(modifiedTrash);

      // Verify updated in place in Trash
      expect(ResourceService().trashedUploads.length, 1);
      final item = ResourceService().trashedUploads.first;
      final current = item['resource'] as Resource;
      expect(current.id, 'trash_target');
      expect(current.title, 'Updated Trashed Material');
      expect(current.unitCode, 'COMP 999');
      expect(current.status, 'trash');
      expect(current.updatedByAdmin, isTrue);
      expect(item['deletedAt'], isNotNull);

      // CRITICAL: Must NOT appear in active Materials Home
      expect(ResourceService().allResources.any((r) => r.id == 'trash_target'), isFalse);
    });

    testWidgets('21. Admin can open and view archived materials normally; closing returns to Archives list with archived state unchanged', (tester) async {
      final arch1 = testResource1.copyWith(
        id: 'arch_view_test',
        title: 'Archived Exam Paper',
        fileUrl: 'https://example.com/archived.pdf',
        status: 'archived',
      );
      ResourceService().setAllResources([arch1]);

      await tester.pumpWidget(
        buildTestApp(
          const ArchiveTrashScreen(
            isDownloads: false,
            isTrash: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Card is present
      expect(find.text('Archived Exam Paper'), findsOneWidget);

      // Normal tap on card opens MaterialViewerScreen
      await tester.tap(find.text('Archived Exam Paper'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Viewer opened with material details
      expect(find.byType(MaterialViewerScreen), findsOneWidget);
      expect(find.text('Operating Systems (COMP 311)'), findsOneWidget);

      // Close / pop viewer
      final backButton = find.byType(BackButton).first;
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // Returned to Archives screen
      expect(find.byType(ArchiveTrashScreen), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);

      // Material remains in Archives
      expect(ResourceService().archivedUploads.any((r) => r.id == 'arch_view_test'), isTrue);
      expect(ResourceService().allResources.any((r) => r.id == 'arch_view_test'), isFalse);
    });

    testWidgets('22. Admin can open and view trashed materials normally; closing returns to Trash list with trash state unchanged', (tester) async {
      final now = DateTime.now();
      final trash1 = testResource1.copyWith(
        id: 'trash_view_test',
        title: 'Trashed CAT Paper',
        fileUrl: 'https://example.com/trashed.pdf',
        status: 'trash',
        uploadDate: now,
        deletedAt: now,
      );
      ResourceService().setAllResources([trash1]);

      await tester.pumpWidget(
        buildTestApp(
          const ArchiveTrashScreen(
            isDownloads: false,
            isTrash: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Card is present
      expect(find.text('Trashed CAT Paper'), findsOneWidget);

      // Normal tap on card opens MaterialViewerScreen
      await tester.tap(find.text('Trashed CAT Paper'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Viewer opened with material details
      expect(find.byType(MaterialViewerScreen), findsOneWidget);
      expect(find.text('Operating Systems (COMP 311)'), findsOneWidget);

      // Close / pop viewer
      final backButton = find.byType(BackButton).first;
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // Returned to Trash screen
      expect(find.byType(ArchiveTrashScreen), findsOneWidget);
      expect(find.text('Trash'), findsOneWidget);

      // Material remains in Trash
      expect(ResourceService().trashedUploads.any((item) => (item['resource'] as Resource).id == 'trash_view_test'), isTrue);
      expect(ResourceService().allResources.any((r) => r.id == 'trash_view_test'), isFalse);
    });

    testWidgets('23. Identical Metadata Isolation in Archives: modifying one archived material affects only its unique ID and leaves identical material untouched', (tester) async {
      final archA = testResource1.copyWith(id: 'arch_iso_a', title: 'Chem Notes', status: 'archived');
      final archB = testResource1.copyWith(id: 'arch_iso_b', title: 'Chem Notes', status: 'archived');
      ResourceService().setAllResources([archA, archB]);

      expect(ResourceService().archivedUploads.length, 2);

      // Modify arch_iso_a only
      final updatedA = archA.copyWith(title: 'Updated Chem Notes A', updatedByAdmin: true);
      await ResourceService().modifyMaterial(updatedA);

      final currentA = ResourceService().archivedUploads.firstWhere((r) => r.id == 'arch_iso_a');
      final currentB = ResourceService().archivedUploads.firstWhere((r) => r.id == 'arch_iso_b');

      expect(currentA.title, 'Updated Chem Notes A');
      expect(currentA.updatedByAdmin, isTrue);

      expect(currentB.title, 'Chem Notes');
      expect(currentB.updatedByAdmin, isFalse);
    });
  });
}
