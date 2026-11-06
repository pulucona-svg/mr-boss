import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:mirror_laikipia/models/material_model.dart';
import 'package:mirror_laikipia/providers/providers.dart';
import 'package:mirror_laikipia/services/download_service.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/widgets/resource_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockUserProfileNotifier extends UserProfileNotifier {
  MockUserProfileNotifier() {
    state = UserProfile(
      uid: 'user_123',
      username: 'Test User',
      institution: 'Laikipia University',
      universityLocation: 'Main Campus',
      program: 'Medicine',
      programCode: 'BMED',
      year: 'Year 2',
      semester: 'Semester 1',
      phone: '+254712345678',
      email: 'test@laikipia.ac.ke',
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
    DownloadService().downloadedResources.clear();
  });

  test('DownloadService distinguishes resources with identical titles and unit codes by ID', () async {
    final downloadService = DownloadService();

    final resource1 = {
      'id': 'res_bmed_01',
      'title': 'Basic Medical Microbiology',
      'unitCode': 'BMED 212',
      'fileUrl': 'https://example.com/bmed_01.pdf',
    };
    final resource2 = {
      'id': 'res_bmed_02',
      'title': 'Basic Medical Microbiology',
      'unitCode': 'BMED 212',
      'fileUrl': 'https://example.com/bmed_02.pdf',
    };

    // Initially neither is downloaded
    expect(downloadService.isDownloaded('res_bmed_01'), isFalse);
    expect(downloadService.isDownloaded('res_bmed_02'), isFalse);

    // Download resource 2 only
    downloadService.addDownloadedResourceForTesting(resource2);

    // Resource 2 has downloaded state, Resource 1 does not
    expect(downloadService.isDownloaded('res_bmed_02'), isTrue);
    expect(downloadService.isDownloaded('res_bmed_01'), isFalse);

    // Querying by resource 2's id confirms it is downloaded
    expect(downloadService.isDownloaded(resource2['id']!), isTrue);
    expect(downloadService.isDownloaded(resource1['id']!), isFalse);
  });

  testWidgets('ResourceCard displays green check ONLY for the downloaded resource among duplicates', (WidgetTester tester) async {
    final downloadService = DownloadService();

    final res1 = Resource(
      id: 'res_bmed_01',
      title: 'Basic Medical Microbiology',
      fileName: 'doc1.pdf',
      type: 'Notes',
      thumbnailUrl: '',
      thumbnailStatus: 'completed',
      fileUrl: 'https://example.com/doc1.pdf',
      fileId: 'file1',
      unitName: 'Basic Medical Microbiology',
      unitCode: 'BMED 212',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: 'Year 2',
      semester: 'Semester 1',
      lecturers: ['Dr. Smith'],
      uploadedBy: 'Admin',
      uploaderRole: 'Lecturer',
      uploaderId: 'lecturer_1',
      targetPrograms: ['Medicine'],
      programCodes: ['BMED'],
      materialFormat: 'PDF',
      uploadDate: DateTime.now(),
    );

    final res2 = Resource(
      id: 'res_bmed_02',
      title: 'Basic Medical Microbiology',
      fileName: 'doc2.pdf',
      type: 'CATs',
      thumbnailUrl: '',
      thumbnailStatus: 'completed',
      fileUrl: 'https://example.com/doc2.pdf',
      fileId: 'file2',
      unitName: 'Basic Medical Microbiology',
      unitCode: 'BMED 212',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: 'Year 2',
      semester: 'Semester 1',
      lecturers: ['Dr. Jones'],
      uploadedBy: 'Admin',
      uploaderRole: 'Lecturer',
      uploaderId: 'lecturer_2',
      targetPrograms: ['Medicine'],
      programCodes: ['BMED'],
      materialFormat: 'PDF',
      uploadDate: DateTime.now(),
    );

    // Only res2 is downloaded
    downloadService.addDownloadedResourceForTesting({
      'id': 'res_bmed_02',
      'title': res2.title,
      'unitCode': res2.unitCode,
      'fileUrl': res2.fileUrl,
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith((ref) => MockUserProfileNotifier()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: 160,
                  height: 240,
                  child: ResourceCard(resource: res1, showDownload: true, onTap: () {}),
                ),
                SizedBox(
                  width: 160,
                  height: 240,
                  child: ResourceCard(resource: res2, showDownload: true, onTap: () {}),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify exactly one check icon exists across both cards (for res2)
    expect(find.byIcon(Icons.check), findsOneWidget);

    // Verify exactly one download icon exists across both cards (for res1)
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
  });
}
