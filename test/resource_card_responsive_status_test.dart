import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:mirror_laikipia/providers/providers.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/services/resource_service.dart';
import 'package:mirror_laikipia/widgets/resource_card.dart';

class MockUserProfileNotifier extends UserProfileNotifier {
  MockUserProfileNotifier() {
    state = UserProfile(
      uid: 'uploader_uid',
      username: 'Test Uploader',
      institution: 'Laikipia University',
      universityLocation: 'Main Campus',
      program: 'Computer Science',
      programCode: 'COMP',
      year: 'Year 4',
      semester: 'Semester 1',
      phone: '+254712345678',
      email: 'uploader@laikipia.ac.ke',
    );
  }
}

Resource createTestResource({
  required String id,
  required String title,
  required String status,
}) {
  return Resource(
    id: id,
    title: title,
    unitName: 'Chemistry II',
    unitCode: 'CHEM 212',
    year: '2026',
    uploadYear: '2026',
    publicationYear: '2026',
    yearOfStudy: 'Year 2',
    semester: 'Semester 1',
    lecturers: ['Dr. Lecturer'],
    type: 'Notes',
    thumbnailUrl: 'https://example.com/thumb.png',
    fileUrl: 'https://example.com/chem.pdf',
    fileId: 'file_$id',
    uploaderId: 'uploader_uid',
    uploadedBy: 'Test Uploader',
    uploaderRole: 'Student',
    uploadDate: DateTime.now(),
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
    ResourceService.resetInstance();
  });

  tearDown(() {
    ResourceService.resetInstance();
  });

  Widget buildTestCard(Resource resource, {double screenWidth = 360, double screenHeight = 800}) {
    return ProviderScope(
      overrides: [
        userProfileProvider.overrideWith((ref) => MockUserProfileNotifier()),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(screenWidth, screenHeight),
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                // Simulating a 2-column grid item on a narrow screen (360 - 32 padding - 12 spacing) / 2 = 158px width
                width: (screenWidth - 32 - 12) / 2,
                height: ((screenWidth - 32 - 12) / 2) / 0.72,
                child: ResourceCard(
                  key: ValueKey(resource.id),
                  resource: resource,
                  forceShowStatusTag: true,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Pending Admin Approval tag does not cause RenderFlex overflow on narrow screen', (tester) async {
    final pendingRes = createTestResource(
      id: 'res_pending_1',
      title: 'Very Long Title For Chemistry II Comprehensive Study Guide',
      status: 'pending',
    );

    await tester.pumpWidget(buildTestCard(pendingRes, screenWidth: 360));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Pending Admin Approval'), findsOneWidget);
    expect(find.byIcon(Icons.access_time_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Extra narrow device (320px width) does not cause RenderFlex overflow for Pending Admin Approval', (tester) async {
    final pendingRes = createTestResource(
      id: 'res_pending_narrow',
      title: 'Physics Advanced Mechanics',
      status: 'pending',
    );

    // Card width will be (320 - 32 - 12) / 2 = 138px
    await tester.pumpWidget(buildTestCard(pendingRes, screenWidth: 320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Pending Admin Approval'), findsOneWidget);
    expect(find.byIcon(Icons.access_time_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Approved, Rejected, and Modified status tags render without overflow on narrow screen', (tester) async {
    final statuses = [
      ('approved', 'Approved', Icons.check_circle_rounded),
      ('modified', 'Modified', Icons.edit_note_rounded),
      ('rejected', 'Rejected', Icons.cancel_rounded),
    ];

    for (final (status, expectedLabel, expectedIcon) in statuses) {
      final res = createTestResource(
        id: 'res_$status',
        title: 'Computer Architecture and Operating Systems Laboratory',
        status: status,
      );

      await tester.pumpWidget(buildTestCard(res, screenWidth: 360));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text(expectedLabel), findsOneWidget);
      expect(find.byIcon(expectedIcon), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
