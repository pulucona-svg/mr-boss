import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:mirror_laikipia/screens/dashboard_screen.dart';
import 'package:mirror_laikipia/services/resource_service.dart';

Resource createTestResource({
  required String id,
  required String title,
  required DateTime uploadDate,
  DateTime? approvedAt,
  bool isPinned = false,
  DateTime? pinnedAt,
  String status = 'approved',
}) {
  return Resource(
    id: id,
    title: title,
    type: 'Notes',
    thumbnailUrl: 'https://example.com/thumb.jpg',
    fileUrl: 'https://example.com/file.pdf',
    fileId: 'file_$id',
    unitName: 'Test Unit',
    unitCode: 'COMP 101',
    year: '2024',
    uploadYear: '2024',
    publicationYear: '2024',
    yearOfStudy: '1st Year',
    semester: 'Semester 1',
    lecturers: ['Dr. Test'],
    uploadedBy: 'Tester',
    uploaderRole: 'Student',
    uploaderId: 'user_1',
    uploadDate: uploadDate,
    approvedAt: approvedAt,
    isPinned: isPinned,
    pinnedAt: pinnedAt,
    status: status,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });
  group('Home Material Release Ordering & Serpentine Layout Tests', () {
    test('effectiveReleaseDate prefers approvedAt over uploadDate and falls back to uploadDate', () {
      final uploadTime = DateTime(2026, 1, 10);
      final approveTime = DateTime(2026, 1, 25);

      final withApproval = createTestResource(
        id: 'r1',
        title: 'With Approval',
        uploadDate: uploadTime,
        approvedAt: approveTime,
      );

      final withoutApproval = createTestResource(
        id: 'r2',
        title: 'Without Approval',
        uploadDate: uploadTime,
        approvedAt: null,
      );

      expect(withApproval.effectiveReleaseDate, equals(approveTime));
      expect(withoutApproval.effectiveReleaseDate, equals(uploadTime));
    });

    test('Serpentine visual mapping for even counts (4 items)', () {
      // 4 items ordered newest first: M1 (newest), M2, M3, M4
      final m1 = createTestResource(id: '1', title: 'M1', uploadDate: DateTime(2026, 1, 4));
      final m2 = createTestResource(id: '2', title: 'M2', uploadDate: DateTime(2026, 1, 3));
      final m3 = createTestResource(id: '3', title: 'M3', uploadDate: DateTime(2026, 1, 2));
      final m4 = createTestResource(id: '4', title: 'M4', uploadDate: DateTime(2026, 1, 1));

      final slots = DashboardScreen.buildSerpentineGridSlots([m1, m2, m3, m4]);

      expect(slots.length, equals(4));
      // Row 0: Left = 1, Right = 2
      expect(slots[0]?.id, equals('1'));
      expect(slots[1]?.id, equals('2'));
      // Row 1: Left = 4, Right = 3 (reversed!)
      expect(slots[2]?.id, equals('4'));
      expect(slots[3]?.id, equals('3'));
    });

    test('Serpentine visual mapping for 8 items alternates every row', () {
      final items = List.generate(8, (i) {
        final id = '${i + 1}';
        return createTestResource(
          id: id,
          title: 'M$id',
          uploadDate: DateTime(2026, 1, 1).add(Duration(days: 8 - i)), // 1 is newest, 8 is oldest
        );
      });

      final slots = DashboardScreen.buildSerpentineGridSlots(items);

      expect(slots.length, equals(8));
      // Row 0: 1 | 2
      expect(slots[0]?.id, equals('1'));
      expect(slots[1]?.id, equals('2'));
      // Row 1: 4 | 3
      expect(slots[2]?.id, equals('4'));
      expect(slots[3]?.id, equals('3'));
      // Row 2: 5 | 6
      expect(slots[4]?.id, equals('5'));
      expect(slots[5]?.id, equals('6'));
      // Row 3: 8 | 7
      expect(slots[6]?.id, equals('8'));
      expect(slots[7]?.id, equals('7'));
    });

    test('Odd count: 3 items places 3rd item at Row 1 Right without breaking', () {
      final m1 = createTestResource(id: '1', title: 'M1', uploadDate: DateTime(2026, 1, 3));
      final m2 = createTestResource(id: '2', title: 'M2', uploadDate: DateTime(2026, 1, 2));
      final m3 = createTestResource(id: '3', title: 'M3', uploadDate: DateTime(2026, 1, 1));

      final slots = DashboardScreen.buildSerpentineGridSlots([m1, m2, m3]);

      expect(slots.length, equals(4)); // 2 rows of 2
      // Row 0: 1 | 2
      expect(slots[0]?.id, equals('1'));
      expect(slots[1]?.id, equals('2'));
      // Row 1: null (Left) | 3 (Right)
      expect(slots[2], isNull);
      expect(slots[3]?.id, equals('3'));
    });

    test('Odd count: 1 item places item at Row 0 Left', () {
      final m1 = createTestResource(id: '1', title: 'M1', uploadDate: DateTime(2026, 1, 1));

      final slots = DashboardScreen.buildSerpentineGridSlots([m1]);

      expect(slots.length, equals(2));
      expect(slots[0]?.id, equals('1'));
      expect(slots[1], isNull);
    });

    test('Odd count: 5 items correctly maps 3 rows', () {
      final items = List.generate(5, (i) {
        final id = '${i + 1}';
        return createTestResource(id: id, title: 'M$id', uploadDate: DateTime(2026, 1, 1).add(Duration(days: 5 - i)));
      });

      final slots = DashboardScreen.buildSerpentineGridSlots(items);

      expect(slots.length, equals(6)); // 3 rows
      // Row 0: 1 | 2
      expect(slots[0]?.id, equals('1'));
      expect(slots[1]?.id, equals('2'));
      // Row 1: 4 | 3
      expect(slots[2]?.id, equals('4'));
      expect(slots[3]?.id, equals('3'));
      // Row 2: 5 | null
      expect(slots[4]?.id, equals('5'));
      expect(slots[5], isNull);
    });

    test('Odd count: 7 items correctly places 7th item at Row 3 Right', () {
      final items = List.generate(7, (i) {
        final id = '${i + 1}';
        return createTestResource(id: id, title: 'M$id', uploadDate: DateTime(2026, 1, 1).add(Duration(days: 7 - i)));
      });

      final slots = DashboardScreen.buildSerpentineGridSlots(items);

      expect(slots.length, equals(8)); // 4 rows
      // Row 0: 1 | 2
      expect(slots[0]?.id, equals('1'));
      expect(slots[1]?.id, equals('2'));
      // Row 1: 4 | 3
      expect(slots[2]?.id, equals('4'));
      expect(slots[3]?.id, equals('3'));
      // Row 2: 5 | 6
      expect(slots[4]?.id, equals('5'));
      expect(slots[5]?.id, equals('6'));
      // Row 3: null | 7
      expect(slots[6], isNull);
      expect(slots[7]?.id, equals('7'));
    });

    test('Pinned materials strictly precede unpinned releases and unpinned starts on fresh row', () {
      final p1 = createTestResource(id: 'p1', title: 'Pinned 1', uploadDate: DateTime(2026, 1, 1), isPinned: true, pinnedAt: DateTime(2026, 1, 10));
      final m1 = createTestResource(id: 'm1', title: 'New Unpinned', uploadDate: DateTime(2026, 1, 20));
      final m2 = createTestResource(id: 'm2', title: 'Old Unpinned', uploadDate: DateTime(2026, 1, 15));

      final slots = DashboardScreen.buildSerpentineGridSlots([m1, p1, m2]);

      // p1 is single pinned item -> Row 0 Left = p1, Row 0 Right = null
      expect(slots[0]?.id, equals('p1'));
      expect(slots[1], isNull);
      // Row 1 starts unpinned releases: Left = m1, Right = m2
      expect(slots[2]?.id, equals('m1'));
      expect(slots[3]?.id, equals('m2'));
    });

    test('Multiple pinned materials follow standard order before serpentine unpinned', () {
      final p1 = createTestResource(id: 'p1', title: 'Pinned 1', uploadDate: DateTime(2026, 1, 1), isPinned: true, pinnedAt: DateTime(2026, 1, 10));
      final p2 = createTestResource(id: 'p2', title: 'Pinned 2', uploadDate: DateTime(2026, 1, 2), isPinned: true, pinnedAt: DateTime(2026, 1, 9));
      final m1 = createTestResource(id: 'm1', title: 'M1', uploadDate: DateTime(2026, 1, 20));
      final m2 = createTestResource(id: 'm2', title: 'M2', uploadDate: DateTime(2026, 1, 19));
      final m3 = createTestResource(id: 'm3', title: 'M3', uploadDate: DateTime(2026, 1, 18));
      final m4 = createTestResource(id: 'm4', title: 'M4', uploadDate: DateTime(2026, 1, 17));

      final slots = DashboardScreen.buildSerpentineGridSlots([m4, p2, m1, p1, m3, m2]);

      // Row 0: Pinned 1 | Pinned 2
      expect(slots[0]?.id, equals('p1'));
      expect(slots[1]?.id, equals('p2'));
      // Row 1: M1 | M2
      expect(slots[2]?.id, equals('m1'));
      expect(slots[3]?.id, equals('m2'));
      // Row 2: M4 | M3
      expect(slots[4]?.id, equals('m4'));
      expect(slots[5]?.id, equals('m3'));
    });

    test('ResourceService _sortResources uses effectiveReleaseDate', () {
      final service = ResourceService();
      // Material A uploaded 10 days ago, approved 1 day ago (effective date: 1 day ago)
      final resA = createTestResource(
        id: 'A',
        title: 'Uploaded early, approved late',
        uploadDate: DateTime.now().subtract(const Duration(days: 10)),
        approvedAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      // Material B uploaded 5 days ago, approved 5 days ago (effective date: 5 days ago)
      final resB = createTestResource(
        id: 'B',
        title: 'Uploaded & approved 5 days ago',
        uploadDate: DateTime.now().subtract(const Duration(days: 5)),
        approvedAt: DateTime.now().subtract(const Duration(days: 5)),
      );

      service.setAllResources([resB, resA]);

      final sorted = service.allResources;
      expect(sorted.first.id, equals('A'), reason: 'Material A was approved more recently so it should be first');
      expect(sorted.last.id, equals('B'));
    });
  });
}
