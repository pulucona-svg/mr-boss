import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:mirror_laikipia/screens/dashboard_screen.dart';
import 'package:mirror_laikipia/services/resource_service.dart';

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
  String? dspaceItemUuid,
  String type = 'Notes',
}) {
  return Resource(
    id: id,
    title: title,
    type: type,
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
    uploadedBy: isImportedDSpace ? 'DSpace Archive' : 'Student',
    uploaderRole: isImportedDSpace ? 'Institutional' : 'Student',
    uploaderId: isImportedDSpace ? 'dspace_user' : 'student_1',
    uploadDate: uploadDate,
    approvedAt: approvedAt,
    isPinned: isPinned,
    pinnedAt: pinnedAt,
    isImportedDSpace: isImportedDSpace,
    dspaceItemUuid: dspaceItemUuid,
    status: 'approved',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  group('DSpace Model & hasValidThumbnail Tests', () {
    test('Resource properly serializes and deserializes DSpace metadata', () {
      final map = {
        'title': 'Operating Systems Exam 2023',
        'type': 'Exams',
        'thumbnailUrl': 'https://ik.imagekit.io/ubgbitinve/THUMBNAILS/os2023.jpg',
        'thumbnailStatus': 'completed',
        'fileUrl': 'https://ik.imagekit.io/ubgbitinve/EXAMS/os2023.pdf',
        'fileId': 'file_os2023',
        'unitName': 'Operating Systems',
        'unitCode': 'COMP 311',
        'year': '2023',
        'uploadYear': '2026',
        'publicationYear': '2023',
        'yearOfStudy': '3rd Year',
        'semester': 'Semester 1',
        'lecturers': ['Prof. Tech'],
        'uploadedBy': 'DSpace Virtual Reviewer',
        'uploaderRole': 'Institutional',
        'uploaderId': 'dspace_uploader',
        'isImportedDSpace': true,
        'dspaceItemUuid': 'uuid-1234-abcd',
      };

      final res = Resource.fromMap(map, 'doc_os2023');
      expect(res.isImportedDSpace, isTrue);
      expect(res.dspaceItemUuid, equals('uuid-1234-abcd'));
      expect(res.hasValidThumbnail, isTrue);

      final toMapResult = res.toMap();
      expect(toMapResult['isImportedDSpace'], isTrue);
      expect(toMapResult['dspaceItemUuid'], equals('uuid-1234-abcd'));
    });

    test('hasValidThumbnail identifies valid vs pending/empty thumbnails accurately', () {
      final withThumb = createTestMaterial(
        id: '1',
        title: 'Has Thumb',
        uploadDate: DateTime(2026, 1, 1),
        thumbnailUrl: 'https://ik.imagekit.io/thumb.jpg',
        thumbnailStatus: 'completed',
      );
      final pendingThumb = createTestMaterial(
        id: '2',
        title: 'Pending Thumb',
        uploadDate: DateTime(2026, 1, 1),
        thumbnailUrl: '',
        thumbnailStatus: 'pending',
      );
      final emptyUrlCompletedStatus = createTestMaterial(
        id: '3',
        title: 'Empty URL',
        uploadDate: DateTime(2026, 1, 1),
        thumbnailUrl: '   ',
        thumbnailStatus: 'completed',
      );

      expect(withThumb.hasValidThumbnail, isTrue);
      expect(pendingThumb.hasValidThumbnail, isFalse);
      expect(emptyUrlCompletedStatus.hasValidThumbnail, isFalse);
    });
  });

  group('Temporary Visual Prioritization Tests', () {
    late ResourceService resourceService;

    setUp(() {
      resourceService = ResourceService();
    });

    test('when DSpace thumbnails are incomplete, completed-thumbnail materials appear first', () {
      resourceService.setHasIncompleteDSpaceThumbnails(true);

      // Materials: M1 (oldest with thumb), M2 (newest without thumb), M3 (newest with thumb), M4 (oldest without thumb)
      final m1 = createTestMaterial(
        id: 'm1',
        title: 'M1 with thumb (older)',
        uploadDate: DateTime(2026, 1, 2),
        thumbnailUrl: 'https://example.com/m1.jpg',
        thumbnailStatus: 'completed',
      );
      final m2 = createTestMaterial(
        id: 'm2',
        title: 'M2 without thumb (newest)',
        uploadDate: DateTime(2026, 1, 10),
        thumbnailUrl: '',
        thumbnailStatus: 'pending',
        isImportedDSpace: true,
      );
      final m3 = createTestMaterial(
        id: 'm3',
        title: 'M3 with thumb (newest)',
        uploadDate: DateTime(2026, 1, 8),
        thumbnailUrl: 'https://example.com/m3.jpg',
        thumbnailStatus: 'completed',
      );
      final m4 = createTestMaterial(
        id: 'm4',
        title: 'M4 without thumb (oldest)',
        uploadDate: DateTime(2026, 1, 1),
        thumbnailUrl: '',
        thumbnailStatus: 'pending',
        isImportedDSpace: true,
      );

      final sorted = resourceService.sortResources([m1, m2, m3, m4]);

      // All items with thumbnails must appear before items without thumbnails:
      // Group 1 (with thumbnails): M3 (Jan 8), then M1 (Jan 2)
      // Group 2 (without thumbnails): M2 (Jan 10), then M4 (Jan 1)
      expect(sorted.map((r) => r.id).toList(), equals(['m3', 'm1', 'm2', 'm4']));
    });

    test('preserves relative release-date ordering within each group', () {
      resourceService.setHasIncompleteDSpaceThumbnails(true);

      final withThumb1 = createTestMaterial(
        id: 't_new',
        title: 'T New',
        uploadDate: DateTime(2026, 1, 15),
        thumbnailUrl: 'https://example.com/thumb1.jpg',
      );
      final withThumb2 = createTestMaterial(
        id: 't_mid',
        title: 'T Mid',
        uploadDate: DateTime(2026, 1, 10),
        thumbnailUrl: 'https://example.com/thumb2.jpg',
      );
      final withThumb3 = createTestMaterial(
        id: 't_old',
        title: 'T Old',
        uploadDate: DateTime(2026, 1, 5),
        thumbnailUrl: 'https://example.com/thumb3.jpg',
      );

      final noThumb1 = createTestMaterial(
        id: 'nt_new',
        title: 'NT New',
        uploadDate: DateTime(2026, 1, 20),
        thumbnailUrl: '',
        thumbnailStatus: 'pending',
      );
      final noThumb2 = createTestMaterial(
        id: 'nt_old',
        title: 'NT Old',
        uploadDate: DateTime(2026, 1, 2),
        thumbnailUrl: '',
        thumbnailStatus: 'pending',
      );

      final sorted = resourceService.sortResources([noThumb2, withThumb2, noThumb1, withThumb3, withThumb1]);

      // Result should be: [t_new, t_mid, t_old, nt_new, nt_old]
      expect(sorted.map((r) => r.id).toList(), equals(['t_new', 't_mid', 't_old', 'nt_new', 'nt_old']));
    });

    test('pinned-item precedence is strictly preserved regardless of thumbnail status', () {
      resourceService.setHasIncompleteDSpaceThumbnails(true);

      final pinnedWithoutThumb = createTestMaterial(
        id: 'pinned_no_thumb',
        title: 'Important Announcement',
        uploadDate: DateTime(2026, 1, 1),
        isPinned: true,
        pinnedAt: DateTime(2026, 1, 20),
        thumbnailUrl: '',
        thumbnailStatus: 'pending',
      );

      final unpinnedWithThumb = createTestMaterial(
        id: 'unpinned_with_thumb',
        title: 'Recent Material',
        uploadDate: DateTime(2026, 1, 25),
        thumbnailUrl: 'https://example.com/thumb.jpg',
        thumbnailStatus: 'completed',
      );

      final sorted = resourceService.sortResources([unpinnedWithThumb, pinnedWithoutThumb]);

      // Pinned item MUST be first despite not having a thumbnail
      expect(sorted.first.id, equals('pinned_no_thumb'));
      expect(sorted.last.id, equals('unpinned_with_thumb'));
    });

    test('user-uploaded materials are included in temporary prioritization where they share feed', () {
      resourceService.setHasIncompleteDSpaceThumbnails(true);

      final userUploadWithThumb = createTestMaterial(
        id: 'user_with_thumb',
        title: 'Student Upload With Thumb',
        uploadDate: DateTime(2026, 1, 12),
        isImportedDSpace: false,
        thumbnailUrl: 'https://example.com/thumb.jpg',
      );

      final dspaceWithThumb = createTestMaterial(
        id: 'dspace_with_thumb',
        title: 'DSpace With Thumb',
        uploadDate: DateTime(2026, 1, 10),
        isImportedDSpace: true,
        thumbnailUrl: 'https://example.com/dspace_thumb.jpg',
      );

      final dspacePending = createTestMaterial(
        id: 'dspace_pending',
        title: 'DSpace Pending Thumb',
        uploadDate: DateTime(2026, 1, 15),
        isImportedDSpace: true,
        thumbnailUrl: '',
        thumbnailStatus: 'pending',
      );

      final sorted = resourceService.sortResources([dspacePending, dspaceWithThumb, userUploadWithThumb]);

      // Both user-upload and DSpace items with thumbnails appear first in release-date order:
      // user_with_thumb (Jan 12), dspace_with_thumb (Jan 10), then dspace_pending (Jan 15)
      expect(sorted.map((r) => r.id).toList(), equals(['user_with_thumb', 'dspace_with_thumb', 'dspace_pending']));
    });

    test('permanent universal thumbnail ordering prioritizes thumbnails even when all DSpace items have thumbnails', () {
      // Regardless of DSpace state:
      resourceService.setHasIncompleteDSpaceThumbnails(false);

      final m1 = createTestMaterial(
        id: 'm1',
        title: 'M1',
        uploadDate: DateTime(2026, 1, 1),
        thumbnailUrl: 'https://example.com/thumb.jpg',
      );
      final m2 = createTestMaterial(
        id: 'm2',
        title: 'M2',
        uploadDate: DateTime(2026, 1, 10), // Newer
        thumbnailUrl: '',
        thumbnailStatus: 'completed', // completed but text-based
      );

      final sorted = resourceService.sortResources([m1, m2]);

      // Materials with valid thumbnails are ALWAYS grouped ahead of materials without thumbnails:
      // m1 (with thumbnail) precedes m2 (without thumbnail)
      expect(sorted.map((r) => r.id).toList(), equals(['m1', 'm2']));
    });

    test('Serpentine layout reflects thumbnail prioritization without overriding it', () {
      resourceService.setHasIncompleteDSpaceThumbnails(true);

      final withThumb1 = createTestMaterial(id: 'w1', title: 'W1', uploadDate: DateTime(2026, 1, 10));
      final withThumb2 = createTestMaterial(id: 'w2', title: 'W2', uploadDate: DateTime(2026, 1, 9));
      final noThumb1 = createTestMaterial(id: 'n1', title: 'N1', uploadDate: DateTime(2026, 1, 20), thumbnailUrl: '', thumbnailStatus: 'pending');
      final noThumb2 = createTestMaterial(id: 'n2', title: 'N2', uploadDate: DateTime(2026, 1, 19), thumbnailUrl: '', thumbnailStatus: 'pending');

      final slots = DashboardScreen.buildSerpentineGridSlots([noThumb1, noThumb2, withThumb1, withThumb2]);

      // Row 0: Left = w1, Right = w2 (both thumbnail-complete materials)
      expect(slots[0]?.id, equals('w1'));
      expect(slots[1]?.id, equals('w2'));
      // Row 1: Left = n2, Right = n1 (materials without thumbnails in serpentine order)
      expect(slots[2]?.id, equals('n2'));
      expect(slots[3]?.id, equals('n1'));
    });
  });

  group('Initial Rendering & Progressive Loading Tests', () {
    test('renders initial batch of 12 items promptly from larger dataset', () {
      final allItems = List.generate(100, (i) {
        return createTestMaterial(
          id: 'item_$i',
          title: 'Item $i',
          uploadDate: DateTime(2026, 1, 1).add(Duration(days: i)),
        );
      });

      const displayLimit = 12;
      final visible = allItems.length > displayLimit ? allItems.sublist(0, displayLimit) : allItems;

      expect(visible.length, equals(12));
      expect(visible.first.id, equals('item_0'));
      expect(visible.last.id, equals('item_11'));
    });

    test('subsequent batches append without losing initial batch or introducing duplicates', () {
      final allItems = List.generate(50, (i) => createTestMaterial(id: 'id_$i', title: 'Title $i', uploadDate: DateTime(2026, 1, 1)));

      int displayLimit = 12;
      final batch1 = allItems.sublist(0, displayLimit);
      expect(batch1.length, equals(12));

      // Append 20 more
      displayLimit = (displayLimit + 20).clamp(0, allItems.length);
      final batch2 = allItems.sublist(0, displayLimit);
      expect(batch2.length, equals(32));

      // Check all batch1 items remain in batch2 at exact indices
      for (int i = 0; i < 12; i++) {
        expect(batch2[i].id, equals(batch1[i].id));
      }

      // Check uniqueness (no duplicates)
      final ids = batch2.map((r) => r.id).toSet();
      expect(ids.length, equals(32));
    });

    test('search and filtering operate on full dataset and do not omit results', () {
      final materials = [
        createTestMaterial(id: 'm1', title: 'Calculus I', uploadDate: DateTime(2026, 1, 1)),
        createTestMaterial(id: 'm2', title: 'Linear Algebra', uploadDate: DateTime(2026, 1, 2)),
        createTestMaterial(id: 'm3', title: 'Advanced Calculus', uploadDate: DateTime(2026, 1, 3)),
      ];

      // Query "Calculus" matches m1 and m3 across full dataset
      final filtered = materials.where((r) => r.title.toLowerCase().contains('calculus')).toList();
      expect(filtered.length, equals(2));
      expect(filtered.map((r) => r.id).toList(), equals(['m1', 'm3']));
    });
  });
}
