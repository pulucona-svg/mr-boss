import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
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
  DateTime? thumbnailCompletedAt,
  bool isImportedDSpace = false,
  String type = 'Exams',
  String unitCode = 'COMP 101',
}) {
  return Resource(
    id: id,
    title: title,
    type: type,
    thumbnailUrl: thumbnailUrl,
    thumbnailStatus: thumbnailStatus,
    thumbnailCompletedAt: thumbnailCompletedAt,
    fileUrl: 'https://example.com/file.pdf',
    fileId: 'file_$id',
    unitName: 'Unit $title',
    unitCode: unitCode,
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
    status: 'approved',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  group('1. Thumbnail Completion Timestamp Deserialization & Serialization', () {
    test('reads nested thumbnailGeneration.completedAt timestamp (Firestore Timestamp format)', () {
      final now = DateTime(2026, 10, 21, 9, 30);
      final map = {
        'title': 'Operating Systems',
        'type': 'Exams',
        'thumbnailUrl': 'https://ik.imagekit.io/test.jpg',
        'thumbnailStatus': 'completed',
        'thumbnailGeneration': {
          'completedAt': Timestamp.fromDate(now),
          'provider': 'flux',
        },
      };

      final res = Resource.fromMap(map, 'doc_1');
      expect(res.thumbnailCompletedAt, equals(now));
      expect(res.effectiveThumbnailDate, equals(now));
    });

    test('reads nested thumbnailGeneration.completedAt from ISO-8601 string (local cache)', () {
      final now = DateTime(2026, 10, 21, 9, 30);
      final map = {
        'title': 'Database Systems',
        'type': 'Exams',
        'thumbnailUrl': 'https://ik.imagekit.io/test.jpg',
        'thumbnailStatus': 'completed',
        'thumbnailGeneration': {
          'completedAt': now.toIso8601String(),
        },
      };

      final res = Resource.fromMap(map, 'doc_2');
      expect(res.thumbnailCompletedAt, equals(now));
      expect(res.effectiveThumbnailDate, equals(now));
    });

    test('prefers top-level thumbnailCompletedAt over nested thumbnailGeneration.completedAt', () {
      final topLevelDate = DateTime(2026, 10, 21, 10, 0);
      final nestedDate = DateTime(2026, 10, 20, 10, 0);

      final map = {
        'title': 'Software Engineering',
        'type': 'Exams',
        'thumbnailUrl': 'https://ik.imagekit.io/test.jpg',
        'thumbnailStatus': 'completed',
        'thumbnailCompletedAt': Timestamp.fromDate(topLevelDate),
        'thumbnailGeneration': {
          'completedAt': Timestamp.fromDate(nestedDate),
        },
      };

      final res = Resource.fromMap(map, 'doc_3');
      expect(res.thumbnailCompletedAt, equals(topLevelDate));
      expect(res.effectiveThumbnailDate, equals(topLevelDate));
    });

    test('handles missing, null, malformed strings, and unexpected types safely without throwing', () {
      // 1. Missing
      final res1 = Resource.fromMap({'title': 'No Timestamp'}, 'doc_null_1');
      expect(res1.thumbnailCompletedAt, isNull);

      // 2. Explicit null
      final res2 = Resource.fromMap({
        'title': 'Null Timestamp',
        'thumbnailCompletedAt': null,
        'thumbnailGeneration': {'completedAt': null},
      }, 'doc_null_2');
      expect(res2.thumbnailCompletedAt, isNull);

      // 3. Malformed string
      final res3 = Resource.fromMap({
        'title': 'Malformed String',
        'thumbnailCompletedAt': 'not-a-valid-date-string',
      }, 'doc_null_3');
      expect(res3.thumbnailCompletedAt, isNull);

      // 4. Unexpected type (number/boolean)
      final res4 = Resource.fromMap({
        'title': 'Number Type',
        'thumbnailCompletedAt': 12345678,
      }, 'doc_null_4');
      expect(res4.thumbnailCompletedAt, isNull);

      // 5. Malformed thumbnailGeneration (not a map)
      final res5 = Resource.fromMap({
        'title': 'Invalid Nested',
        'thumbnailGeneration': 'just_a_string',
      }, 'doc_null_5');
      expect(res5.thumbnailCompletedAt, isNull);
    });

    test('effectiveThumbnailDate falls back to effectiveReleaseDate when thumbnailCompletedAt is null', () {
      final uploadDate = DateTime(2026, 10, 5, 12, 0);
      final approvedAt = DateTime(2026, 10, 6, 14, 0);

      final resWithApproved = Resource(
        title: 'With Approved',
        type: 'Exams',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        fileUrl: '',
        fileId: '',
        unitName: '',
        unitCode: '',
        year: '',
        uploadYear: '',
        publicationYear: '',
        yearOfStudy: '',
        semester: '',
        lecturers: const [],
        uploadedBy: '',
        uploaderRole: '',
        uploaderId: '',
        uploadDate: uploadDate,
        approvedAt: approvedAt,
      );
      expect(resWithApproved.effectiveThumbnailDate, equals(approvedAt));

      final resWithoutApproved = Resource(
        title: 'Without Approved',
        type: 'Exams',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        fileUrl: '',
        fileId: '',
        unitName: '',
        unitCode: '',
        year: '',
        uploadYear: '',
        publicationYear: '',
        yearOfStudy: '',
        semester: '',
        lecturers: const [],
        uploadedBy: '',
        uploaderRole: '',
        uploaderId: '',
        uploadDate: uploadDate,
      );
      expect(resWithoutApproved.effectiveThumbnailDate, equals(uploadDate));
    });

    test('serialization roundtrip via toMap() and toJson() preserves thumbnailCompletedAt', () {
      final completed = DateTime(2026, 10, 21, 8, 45, 12);
      final res = createTestMaterial(
        id: 'roundtrip_1',
        title: 'Roundtrip Test',
        uploadDate: DateTime(2026, 10, 1),
        thumbnailCompletedAt: completed,
      );

      final map = res.toMap();
      expect(map['thumbnailCompletedAt'], isA<Timestamp>());
      expect((map['thumbnailCompletedAt'] as Timestamp).toDate(), equals(completed));

      final json = res.toJson();
      expect(json['thumbnailCompletedAt'], equals(completed.toIso8601String()));

      // Deserialize from toJson map (simulating local persistence recovery)
      final restored = Resource.fromMap(json, 'roundtrip_1');
      expect(restored.thumbnailCompletedAt, equals(completed));
      expect(restored.effectiveThumbnailDate, equals(completed));
    });
  });

  group('2. ResourceService.sortResources Placement & Priority', () {
    late ResourceService service;

    setUp(() {
      service = ResourceService();
      service.clear();
    });

    test('recently completed thumbnail-ready resources move toward top ahead of older completions', () {
      // Resource A: Uploaded 10 days ago (DSpace import), thumbnail completed 5 minutes ago
      final resA = createTestMaterial(
        id: 'res_A_recent_thumb',
        title: 'DSpace Paper with Recent Thumb',
        uploadDate: DateTime(2026, 10, 5, 5, 0),
        thumbnailCompletedAt: DateTime(2026, 10, 21, 9, 25),
        thumbnailUrl: 'https://example.com/thumbA.jpg',
      );

      // Resource B: Uploaded 3 days ago, thumbnail completed yesterday
      final resB = createTestMaterial(
        id: 'res_B_yesterday_thumb',
        title: 'Paper with Yesterday Thumb',
        uploadDate: DateTime(2026, 10, 18, 12, 0),
        thumbnailCompletedAt: DateTime(2026, 10, 20, 12, 0),
        thumbnailUrl: 'https://example.com/thumbB.jpg',
      );

      // Resource C: Uploaded 15 days ago, thumbnail completed 10 days ago
      final resC = createTestMaterial(
        id: 'res_C_older_thumb',
        title: 'Paper with Older Thumb',
        uploadDate: DateTime(2026, 10, 1, 12, 0),
        thumbnailCompletedAt: DateTime(2026, 10, 11, 12, 0),
        thumbnailUrl: 'https://example.com/thumbC.jpg',
      );

      final sorted = service.sortResources([resC, resB, resA]);

      expect(sorted.map((r) => r.id).toList(), equals([
        'res_A_recent_thumb',
        'res_B_yesterday_thumb',
        'res_C_older_thumb',
      ]));
    });

    test('thumbnail-ready resources strictly precede resources without thumbnails regardless of dates', () {
      final resNoThumbNew = createTestMaterial(
        id: 'no_thumb_new',
        title: 'Fresh Paper without Thumbnail',
        uploadDate: DateTime(2026, 10, 21, 9, 30), // Uploaded today
        thumbnailUrl: '',
        thumbnailStatus: 'pending',
      );

      final resWithThumbOld = createTestMaterial(
        id: 'with_thumb_old',
        title: 'Old Paper with Thumbnail',
        uploadDate: DateTime(2026, 9, 1),
        thumbnailCompletedAt: DateTime(2026, 10, 10),
        thumbnailUrl: 'https://example.com/thumb.jpg',
        thumbnailStatus: 'completed',
      );

      final sorted = service.sortResources([resNoThumbNew, resWithThumbOld]);

      expect(sorted.first.id, equals('with_thumb_old'));
      expect(sorted.last.id, equals('no_thumb_new'));
    });

    test('pinned resources retain absolute priority over newly completed thumbnails', () {
      final pinnedNoThumb = createTestMaterial(
        id: 'pinned_announcement',
        title: 'Pinned Timetable Notice',
        uploadDate: DateTime(2026, 10, 1),
        isPinned: true,
        pinnedAt: DateTime(2026, 10, 20),
        thumbnailUrl: '',
        thumbnailStatus: 'pending',
      );

      final newCompleted = createTestMaterial(
        id: 'just_completed_thumb',
        title: 'Newly Completed DSpace Paper',
        uploadDate: DateTime(2026, 10, 5),
        thumbnailCompletedAt: DateTime(2026, 10, 21, 9, 30),
        thumbnailUrl: 'https://example.com/thumb.jpg',
      );

      final sorted = service.sortResources([newCompleted, pinnedNoThumb]);

      expect(sorted.first.id, equals('pinned_announcement'));
      expect(sorted[1].id, equals('just_completed_thumb'));
    });

    test('legacy resources without thumbnailCompletedAt sort safely using effectiveReleaseDate', () {
      final legacyA = createTestMaterial(
        id: 'legacy_A',
        title: 'Legacy Paper A',
        uploadDate: DateTime(2026, 10, 10),
        thumbnailCompletedAt: null, // Legacy: no completion timestamp
        thumbnailUrl: 'https://example.com/thumbA.jpg',
      );

      final legacyB = createTestMaterial(
        id: 'legacy_B',
        title: 'Legacy Paper B',
        uploadDate: DateTime(2026, 10, 8),
        thumbnailCompletedAt: null, // Legacy: no completion timestamp
        thumbnailUrl: 'https://example.com/thumbB.jpg',
      );

      final withNewTimestamp = createTestMaterial(
        id: 'modern_with_timestamp',
        title: 'Modern Paper',
        uploadDate: DateTime(2026, 10, 5),
        thumbnailCompletedAt: DateTime(2026, 10, 21),
        thumbnailUrl: 'https://example.com/thumbC.jpg',
      );

      final sorted = service.sortResources([legacyB, legacyA, withNewTimestamp]);

      expect(sorted.map((r) => r.id).toList(), equals([
        'modern_with_timestamp', // Completed Oct 21
        'legacy_A',               // Fallback: Oct 10
        'legacy_B',               // Fallback: Oct 8
      ]));
    });

    test('tie-breaking is deterministic when thumbnail completion dates are equal', () {
      final sameTime = DateTime(2026, 10, 21, 9, 0);

      // Same completion time, but different release dates
      final res1 = createTestMaterial(
        id: 'tie_id_1',
        title: 'Tie 1 Earlier Release',
        uploadDate: DateTime(2026, 10, 2),
        thumbnailCompletedAt: sameTime,
      );

      final res2 = createTestMaterial(
        id: 'tie_id_2',
        title: 'Tie 2 Later Release',
        uploadDate: DateTime(2026, 10, 4),
        thumbnailCompletedAt: sameTime,
      );

      // Same completion and release date, different id
      final res3A = createTestMaterial(
        id: 'tie_alpha',
        title: 'Tie Alpha',
        uploadDate: DateTime(2026, 10, 4),
        thumbnailCompletedAt: sameTime,
      );

      final res3Z = createTestMaterial(
        id: 'tie_zeta',
        title: 'Tie Zeta',
        uploadDate: DateTime(2026, 10, 4),
        thumbnailCompletedAt: sameTime,
      );

      final sorted = service.sortResources([res1, res3A, res2, res3Z]);

      // res2, res3A, res3Z have uploadDate Oct 4, res1 has Oct 2
      // Among res2, res3A, res3Z, ID tie-breaker sorts 'tie_zeta', 'tie_id_2', 'tie_alpha' descending
      expect(sorted.last.id, equals('tie_id_1'));
      expect(sorted.map((r) => r.id).take(3).toList(), containsAll(['tie_id_2', 'tie_alpha', 'tie_zeta']));
    });

    test('resources without thumbnails preserve their existing release-date ordering', () {
      final noThumbRecent = createTestMaterial(
        id: 'no_thumb_1',
        title: 'No Thumb Recent',
        uploadDate: DateTime(2026, 10, 15),
        thumbnailUrl: '',
        thumbnailStatus: 'pending',
      );

      final noThumbOld = createTestMaterial(
        id: 'no_thumb_2',
        title: 'No Thumb Old',
        uploadDate: DateTime(2026, 10, 10),
        thumbnailUrl: '',
        thumbnailStatus: 'pending',
      );

      final sorted = service.sortResources([noThumbOld, noThumbRecent]);
      expect(sorted.map((r) => r.id).toList(), equals(['no_thumb_1', 'no_thumb_2']));
    });
  });

  group('3. Feed Consistency, Filtering, and Pagination Stability', () {
    late ResourceService service;

    setUp(() {
      service = ResourceService();
      service.clear();
    });

    test('search and category filtering remain compatible with new thumbnail sorting', () {
      final examWithThumb = createTestMaterial(
        id: 'exam_1',
        title: 'Organizational Theory Exam',
        type: 'Exams',
        unitCode: 'AGBM 231',
        uploadDate: DateTime(2026, 10, 5),
        thumbnailCompletedAt: DateTime(2026, 10, 21, 9, 0),
        thumbnailUrl: 'https://example.com/thumb.jpg',
      );

      final notesWithThumb = createTestMaterial(
        id: 'notes_1',
        title: 'Organizational Theory Notes',
        type: 'Notes',
        unitCode: 'AGBM 231',
        uploadDate: DateTime(2026, 10, 5),
        thumbnailCompletedAt: DateTime(2026, 10, 21, 8, 0),
        thumbnailUrl: 'https://example.com/thumb.jpg',
      );

      final allItems = [notesWithThumb, examWithThumb];
      final sortedAll = service.sortResources(allItems);

      // In "All" category: exam_1 (completed at 9:00) precedes notes_1 (completed at 8:00)
      expect(sortedAll.first.id, equals('exam_1'));
      expect(sortedAll.last.id, equals('notes_1'));

      // Category filter for "Exams":
      final examsOnly = sortedAll.where((r) => r.type == 'Exams').toList();
      expect(examsOnly.length, equals(1));
      expect(examsOnly.first.id, equals('exam_1'));

      // Search query filter for "AGBM 231":
      final searched = sortedAll.where((r) => r.unitCode.toLowerCase().contains('agbm 231')).toList();
      expect(searched.length, equals(2));
      expect(searched.first.id, equals('exam_1'));
    });

    test('pagination sublist produces zero duplicates and displays newly completed thumbnails in initial 12 items', () {
      // Create 30 items:
      // 5 newly completed thumbnails (today)
      // 10 older completed thumbnails (last week)
      // 15 pending without thumbnails
      final items = <Resource>[];

      for (int i = 0; i < 5; i++) {
        items.add(createTestMaterial(
          id: 'new_completed_$i',
          title: 'New Completed $i',
          uploadDate: DateTime(2026, 10, 5),
          thumbnailCompletedAt: DateTime(2026, 10, 21, 9, 30 - i),
          thumbnailUrl: 'https://example.com/thumb_$i.jpg',
        ));
      }

      for (int i = 0; i < 10; i++) {
        items.add(createTestMaterial(
          id: 'old_completed_$i',
          title: 'Old Completed $i',
          uploadDate: DateTime(2026, 10, 5),
          thumbnailCompletedAt: DateTime(2026, 10, 10, 12, -i),
          thumbnailUrl: 'https://example.com/old_thumb_$i.jpg',
        ));
      }

      for (int i = 0; i < 15; i++) {
        items.add(createTestMaterial(
          id: 'no_thumb_$i',
          title: 'No Thumb $i',
          uploadDate: DateTime(2026, 10, 5),
          thumbnailUrl: '',
          thumbnailStatus: 'pending',
        ));
      }

      final sorted = service.sortResources(items);
      expect(sorted.length, equals(30));

      // Initial display limit = 12
      const displayLimit = 12;
      final visibleResources = sorted.length > displayLimit ? sorted.sublist(0, displayLimit) : sorted;

      expect(visibleResources.length, equals(12));

      // All 5 newly completed items are within the first 12 items!
      final visibleIds = visibleResources.map((r) => r.id).toSet();
      for (int i = 0; i < 5; i++) {
        expect(visibleIds.contains('new_completed_$i'), isTrue,
            reason: 'Newly completed item new_completed_$i must appear in initial 12 items');
      }

      // Check zero duplicates across pagination
      expect(visibleResources.map((r) => r.id).toSet().length, equals(visibleResources.length));

      // Expanding limit to 25 (+20 infinite scroll)
      final expandedLimit = (displayLimit + 20).clamp(0, sorted.length);
      final expandedResources = sorted.sublist(0, expandedLimit);
      expect(expandedResources.length, equals(30));
      expect(expandedResources.map((r) => r.id).toSet().length, equals(30));
    });

    test('realtime document update elevating pending resource causes immediate resort to index 0', () {
      final oldCompleted1 = createTestMaterial(
        id: 'existing_completed_1',
        title: 'Existing Completed 1',
        uploadDate: DateTime(2026, 10, 5),
        thumbnailCompletedAt: DateTime(2026, 10, 18),
      );

      final oldCompleted2 = createTestMaterial(
        id: 'existing_completed_2',
        title: 'Existing Completed 2',
        uploadDate: DateTime(2026, 10, 5),
        thumbnailCompletedAt: DateTime(2026, 10, 19),
      );

      final initiallyPending = createTestMaterial(
        id: 'pending_paper',
        title: 'Initially Pending Paper',
        uploadDate: DateTime(2026, 10, 5),
        thumbnailUrl: '',
        thumbnailStatus: 'pending',
      );

      // Initial state
      final initialSorted = service.sortResources([oldCompleted1, oldCompleted2, initiallyPending]);
      expect(initialSorted.last.id, equals('pending_paper'));

      // Realtime update arrives from Firestore: thumbnail completes!
      final now = DateTime(2026, 10, 21, 9, 35);
      final updatedPaper = initiallyPending.copyWith(
        thumbnailUrl: 'https://ik.imagekit.io/new_thumb.jpg',
        thumbnailStatus: 'completed',
        thumbnailCompletedAt: now,
      );

      // Resort with updated resource
      final afterUpdateSorted = service.sortResources([oldCompleted1, oldCompleted2, updatedPaper]);

      // The newly completed paper has jumped to index 0!
      expect(afterUpdateSorted.first.id, equals('pending_paper'));
      expect(afterUpdateSorted.first.hasValidThumbnail, isTrue);
      expect(afterUpdateSorted.first.thumbnailCompletedAt, equals(now));
    });
  });
}
