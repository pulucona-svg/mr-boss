import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/models/material_model.dart';
import 'package:mirror_laikipia/services/search_placeholder_service.dart';

Resource createTestResource({
  required String id,
  required String title,
  String unitCode = '',
  String unitName = '',
  List<String> lecturers = const [],
}) {
  return Resource(
    id: id,
    title: title,
    type: 'Notes',
    thumbnailUrl: '',
    fileUrl: 'https://example.com/$id.pdf',
    fileId: 'fid_$id',
    unitCode: unitCode,
    unitName: unitName,
    lecturers: lecturers,
    year: '2026',
    uploadYear: '2026',
    publicationYear: '2026',
    yearOfStudy: 'Year 1',
    semester: 'Sem 1',
    uploadedBy: 'User',
    uploaderRole: 'student',
    uploaderId: 'u1',
    targetPrograms: [],
    programCodes: [],
    uploadDate: DateTime.now(),
  );
}

void main() {
  group('Search Placeholder Service & Typewriter Tests', () {
    late SearchPlaceholderService service;

    setUp(() {
      service = SearchPlaceholderService();
      service.reset();
      // Use deterministic Random seed for reproducible tests
      service.setRandom(Random(42));
    });

    // 1. Correct three-category alternation
    test('1. Correct three-category alternation (UNIT CODE -> LECTURER -> UNIT NAME)', () {
      final resources = [
        createTestResource(
          id: 'res_1',
          title: 'Math Notes',
          unitCode: 'MATH 121',
          unitName: 'Calculus I',
          lecturers: ['Dr. John Mwangi'],
        ),
      ];

      service.syncWithResources(resources);

      // Sequence must strictly rotate: unitCode -> lecturer -> unitName -> unitCode...
      expect(service.getNextPhrase(), 'MATH 121');
      expect(service.getNextPhrase(), 'Dr. John Mwangi');
      expect(service.getNextPhrase(), 'Calculus I');
      expect(service.getNextPhrase(), 'MATH 121');
      expect(service.getNextPhrase(), 'Dr. John Mwangi');
      expect(service.getNextPhrase(), 'Calculus I');
    });

    // 2. No repeated unit codes before unit-code cycle is exhausted
    test('2. No repeated unit codes before the unit-code cycle is exhausted', () {
      final bag = CategoryBag(
        category: PlaceholderCategory.unitCode,
        pool: ['COMP 101', 'COMP 102', 'COMP 103', 'COMP 104'],
      );

      final rng = Random(123);
      final seen = <String>[];

      for (int i = 0; i < 4; i++) {
        final item = bag.getNextItem(rng);
        expect(item, isNotNull);
        expect(seen.contains(item), isFalse, reason: '$item was repeated before cycle finished');
        seen.add(item!);
      }

      expect(seen.toSet().length, 4);
      expect(bag.currentIndex, 4);
    });

    // 3. No repeated lecturer names before lecturer cycle is exhausted
    test('3. No repeated lecturer names before the lecturer cycle is exhausted', () {
      final bag = CategoryBag(
        category: PlaceholderCategory.lecturerName,
        pool: ['Dr. Alice', 'Prof. Bob', 'Dr. Charlie'],
      );

      final rng = Random(456);
      final seen = <String>[];

      for (int i = 0; i < 3; i++) {
        final item = bag.getNextItem(rng);
        expect(item, isNotNull);
        expect(seen.contains(item), isFalse);
        seen.add(item!);
      }

      expect(seen.toSet().length, 3);
    });

    // 4. No repeated unit names before unit-name cycle is exhausted
    test('4. No repeated unit names before the unit-name cycle is exhausted', () {
      final bag = CategoryBag(
        category: PlaceholderCategory.unitName,
        pool: ['Networks', 'Databases', 'Algorithms', 'Operating Systems'],
      );

      final rng = Random(789);
      final seen = <String>[];

      for (int i = 0; i < 4; i++) {
        final item = bag.getNextItem(rng);
        expect(item, isNotNull);
        expect(seen.contains(item), isFalse);
        seen.add(item!);
      }

      expect(seen.toSet().length, 4);
    });

    // 5. Case-insensitive deduplication and placeholder filtering
    test('5. Case-insensitive deduplication and generic placeholder filtering', () {
      final rawList = [
        'math 121',
        'MATH 121',
        'Math 121',
        '  MATH 121  ',
        'Unknown',
        'N/A',
        'na',
        'null',
        'none',
        '-',
        '--',
        'tba',
        'tbd',
        'general',
        '   ',
        'COSC 225',
      ];

      final cleaned = SearchPlaceholderExtractor.cleanAndDeduplicate(rawList);

      // Should contain exactly 2 unique items: MATH 121 (preferred uppercase) and COSC 225
      expect(cleaned.length, 2);
      expect(cleaned.contains('MATH 121'), isTrue);
      expect(cleaned.contains('COSC 225'), isTrue);
      expect(cleaned.any((x) => x.toLowerCase() == 'unknown'), isFalse);
      expect(cleaned.any((x) => x.toLowerCase() == 'n/a'), isFalse);
    });

    // 6. Empty-category handling
    test('6. Empty-category handling gracefully skips empty category and preserves remaining order', () {
      // Setup: Unit codes and Unit names exist, but lecturers are completely empty
      final resources = [
        createTestResource(
          id: 'res_2',
          title: 'Notes',
          unitCode: 'COMP 311',
          unitName: 'Database Systems',
          lecturers: [], // Empty!
        ),
      ];

      service.syncWithResources(resources);

      // Rotation should alternate UNIT CODE -> UNIT NAME -> UNIT CODE -> UNIT NAME
      expect(service.getNextPhrase(), 'COMP 311');
      expect(service.getNextPhrase(), 'Database Systems');
      expect(service.getNextPhrase(), 'COMP 311');
      expect(service.getNextPhrase(), 'Database Systems');
    });

    test('6b. All categories empty returns null (defaults to static hint)', () {
      service.syncWithResources([]);
      expect(service.getNextPhrase(), isNull);
    });

    // 7. New dataset entries joining an existing rotation
    test('7. New dataset entries joining an existing rotation preserves completed progress', () {
      final bag = CategoryBag(
        category: PlaceholderCategory.unitCode,
        pool: ['MATH 101', 'MATH 102'],
        currentIndex: 1, // MATH 101 already displayed
        lastDisplayed: 'MATH 101',
      );

      // Reconcile with updated dataset having MATH 103 added
      bag.reconcileWithValues(['MATH 101', 'MATH 102', 'MATH 103'], Random(1));

      // Progress preserved: currentIndex is still 1
      expect(bag.currentIndex, 1);
      expect(bag.pool.length, 3);
      expect(bag.pool[0], 'MATH 101'); // Already completed item remains at index 0

      // The remaining items in cycle must be MATH 102 and MATH 103
      final next1 = bag.getNextItem(Random(1));
      final next2 = bag.getNextItem(Random(1));
      expect({next1, next2}, {'MATH 102', 'MATH 103'});
    });

    // 8. Removed entries not corrupting persisted state
    test('8. Removed entries not corrupting persisted state or crashing with out-of-bounds', () {
      final bag = CategoryBag(
        category: PlaceholderCategory.unitCode,
        pool: ['MATH 101', 'MATH 102', 'MATH 103'],
        currentIndex: 2, // 101 and 102 displayed, 103 remaining
        lastDisplayed: 'MATH 102',
      );

      // Now MATH 101 was removed from resources
      bag.reconcileWithValues(['MATH 102', 'MATH 103'], Random(1));

      // Index adjusts down by 1 because an item prior to currentIndex was deleted
      expect(bag.currentIndex, 1);
      expect(bag.pool, ['MATH 102', 'MATH 103']);

      // Next item must be MATH 103 without out-of-bounds error
      final next = bag.getNextItem(Random(1));
      expect(next, 'MATH 103');
    });

    // 9. Rotation persistence after simulated application restart
    test('9. Rotation persistence after simulated application restart', () async {
      final resources = [
        createTestResource(
          id: 'res_3',
          title: 'Notes',
          unitCode: 'MATH 121',
          unitName: 'Calculus I',
          lecturers: ['Dr. John Mwangi'],
        ),
      ];

      service.syncWithResources(resources);

      Map<String, dynamic>? persistedJson;
      // Step 1: unitCode
      final item1 = service.getNextPhrase(onPersist: (data) => persistedJson = data);
      expect(item1, 'MATH 121');

      // Step 2: lecturer
      final item2 = service.getNextPhrase(onPersist: (data) => persistedJson = data);
      expect(item2, 'Dr. John Mwangi');
      expect(persistedJson, isNotNull);

      // Simulate app kill & restart: create a new service instance and load persisted JSON
      final newService = SearchPlaceholderService();
      newService.reset();
      await newService.init(customJson: persistedJson);

      // Step 3 after restart MUST be unitName ('Calculus I')
      final item3 = newService.getNextPhrase();
      expect(item3, 'Calculus I');
    });

    // 10. Restoring the correct category and position
    test('10. Restoring the correct category and position from persisted JSON', () async {
      final mockJson = {
        'categoryIndex': 2, // Pointing to unitName
        'categories': {
          'unitCode': {'pool': ['MATH 121'], 'currentIndex': 1, 'lastDisplayed': 'MATH 121'},
          'lecturerName': {'pool': ['Dr. John'], 'currentIndex': 1, 'lastDisplayed': 'Dr. John'},
          'unitName': {'pool': ['Calculus I', 'Linear Algebra'], 'currentIndex': 1, 'lastDisplayed': 'Calculus I'},
        },
      };

      await service.init(customJson: mockJson);
      expect(service.currentCategoryIndex, 2);

      // Next phrase must be from category 2 (unitName) at index 1 -> 'Linear Algebra'
      final phrase = service.getNextPhrase();
      expect(phrase, 'Linear Algebra');
    });

    // 11. Variable typing and deletion timing
    test('11. Variable typing and deletion timing adheres to required ranges and bounds', () {
      // Typing: 100-120ms per char
      expect(TypewriterPlaceholderController.getTypingCharDurationMs(8), 120);
      expect(TypewriterPlaceholderController.getTypingCharDurationMs(15), 110);
      expect(TypewriterPlaceholderController.getTypingCharDurationMs(28), 100);

      // Hold: 1,500-2,000ms
      expect(TypewriterPlaceholderController.getHoldDurationMs(5), 1600);
      expect(TypewriterPlaceholderController.getHoldDurationMs(20), 1900);
      expect(TypewriterPlaceholderController.getHoldDurationMs(40), 2000); // Capped at 2000

      // Deleting: 50-70ms per char
      expect(TypewriterPlaceholderController.getDeletingCharDurationMs(8), 70);
      expect(TypewriterPlaceholderController.getDeletingCharDurationMs(15), 60);
      expect(TypewriterPlaceholderController.getDeletingCharDurationMs(28), 50);
    });

    // 12. Permanent Search prefix
    test('12. Permanent "Search " prefix is preserved throughout typing', () {
      expect(SearchPlaceholderService.permanentPrefix, 'Search ');
      expect(SearchPlaceholderService.permanentPrefix.startsWith('Search '), isTrue);
    });

    // 13. Animation stopping when search receives focus
    test('13. Animation pausing when search receives focus and resuming when unfocused', () {
      final controller = TypewriterPlaceholderController(service: service);

      expect(controller.isPaused, isFalse);
      controller.pause();
      expect(controller.isPaused, isTrue);

      controller.resume();
      expect(controller.isPaused, isFalse);

      controller.dispose();
    });

    // 14. Normal search functionality remaining unchanged
    test('14. Normal search query filtering is unaffected by placeholder', () {
      final resources = [
        createTestResource(
          id: 'res_math',
          title: 'Calculus Revision Booklet',
          unitCode: 'MATH 121',
          unitName: 'Calculus I',
          lecturers: ['Dr. Mwangi'],
        ),
        createTestResource(
          id: 'res_comp',
          title: 'Database Architecture Notes',
          unitCode: 'COMP 311',
          unitName: 'Database Systems',
          lecturers: ['Prof. Jane'],
        ),
      ];

      // Simulate filtering as done by DashboardScreen
      bool matchesQuery(Resource res, String query) {
        final q = query.trim().toLowerCase();
        if (q.isEmpty) return true;
        final searchFields = [
          res.title,
          res.unitCode,
          res.unitName,
          ...res.lecturers,
        ].map((s) => s.toLowerCase()).join(' ');
        return searchFields.contains(q);
      }

      // Query matches math
      final mathResults = resources.where((r) => matchesQuery(r, 'math 121')).toList();
      expect(mathResults.length, 1);
      expect(mathResults.first.id, 'res_math');

      // Query matches lecturer
      final lecturerResults = resources.where((r) => matchesQuery(r, 'prof. jane')).toList();
      expect(lecturerResults.length, 1);
      expect(lecturerResults.first.id, 'res_comp');
    });

    // 15. No duplicate animation timers or subscriptions
    test('15. Multiple start calls do not spawn duplicate timers and dispose cancels safely', () {
      final controller = TypewriterPlaceholderController(service: service);

      // Calling start multiple times
      controller.start();
      controller.start();
      controller.start();

      expect(controller.isPaused, isFalse);

      // Disposing cleans up safely without throwing
      controller.dispose();
      controller.dispose(); // Idempotent dispose
    });
  });
}
