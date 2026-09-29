import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/models/curriculum_model.dart';
import 'package:mirror_laikipia/services/course_service.dart';

void main() {
  group('CurriculumRecord Model Tests', () {
    test('generateId creates deterministic, normalized unique identifier', () {
      final id1 = CurriculumRecord.generateId(
        programCode: 'COMS',
        unitCode: 'COMP 111',
        yearOfStudy: '1',
        semester: '1',
      );
      final id2 = CurriculumRecord.generateId(
        programCode: ' coms ',
        unitCode: 'comp-111 ',
        yearOfStudy: ' 1 ',
        semester: ' 1 ',
      );
      final id3 = CurriculumRecord.generateId(
        programCode: 'COMS',
        unitCode: 'COMP 112',
        yearOfStudy: '1',
        semester: '2',
      );

      expect(id1, equals('coms_comp111_y1_s1'));
      expect(id2, equals(id1));
      expect(id3, equals('coms_comp112_y1_s2'));
      expect(id1, isNot(equals(id3)));
    });

    test('isValidForActivation enforces all 6 core fields (lecturer optional)', () {
      final validWithLecturer = CurriculumRecord(
        id: 'test_1',
        programCode: 'COMS',
        programName: 'Bachelor of Science in Computer Science',
        unitCode: 'COMP 111',
        unitName: 'Introduction to Programming',
        yearOfStudy: '1',
        semester: '1',
        lecturerName: 'Dr. Jane Doe',
      );
      expect(validWithLecturer.isValidForActivation, isTrue);

      final validWithoutLecturer = validWithLecturer.copyWith(lecturerName: '');
      expect(validWithoutLecturer.isValidForActivation, isTrue);

      // Blank programCode
      expect(validWithLecturer.copyWith(programCode: '   ').isValidForActivation, isFalse);
      // Blank programName
      expect(validWithLecturer.copyWith(programName: '').isValidForActivation, isFalse);
      // Blank unitCode
      expect(validWithLecturer.copyWith(unitCode: '').isValidForActivation, isFalse);
      // Blank unitName
      expect(validWithLecturer.copyWith(unitName: '').isValidForActivation, isFalse);
      // Blank yearOfStudy
      expect(validWithLecturer.copyWith(yearOfStudy: '').isValidForActivation, isFalse);
      // Blank semester
      expect(validWithLecturer.copyWith(semester: '').isValidForActivation, isFalse);
    });

    test('toMap and fromMap roundtrip preserves data', () {
      final now = DateTime.now();
      final record = CurriculumRecord(
        id: 'coms_comp111_y1_s1',
        programCode: 'COMS',
        programName: 'Computer Science',
        unitCode: 'COMP 111',
        unitName: 'Intro to CS',
        yearOfStudy: '1',
        semester: '1',
        lecturerName: 'Prof. Smith',
        isActive: true,
        createdAt: now,
        updatedAt: now,
        updatedBy: 'admin_user',
      );

      final map = record.toMap();
      final restored = CurriculumRecord.fromMap(map, record.id);

      expect(restored.id, equals(record.id));
      expect(restored.programCode, equals('COMS'));
      expect(restored.programName, equals('Computer Science'));
      expect(restored.unitCode, equals('COMP 111'));
      expect(restored.unitName, equals('Intro to CS'));
      expect(restored.yearOfStudy, equals('1'));
      expect(restored.semester, equals('1'));
      expect(restored.lecturerName, equals('Prof. Smith'));
      expect(restored.isActive, isTrue);
      expect(restored.updatedBy, equals('admin_user'));
    });
  });

  group('CourseUnit Model Tests', () {
    test('CourseUnit.fromCurriculumRecord correctly maps all fields', () {
      final record = CurriculumRecord(
        id: 'coms_comp111_y1_s1',
        programCode: 'COMS',
        programName: 'B.Sc. Computer Science',
        unitCode: 'COMP 111',
        unitName: 'Intro to Programming',
        yearOfStudy: '1',
        semester: '1',
        lecturerName: 'Dr. Jane',
        isActive: false,
      );

      final unit = CourseUnit.fromCurriculumRecord(record);
      expect(unit.id, equals('coms_comp111_y1_s1'));
      expect(unit.programCode, equals('COMS'));
      expect(unit.programName, equals('B.Sc. Computer Science'));
      expect(unit.unitCode, equals('COMP 111'));
      expect(unit.unitName, equals('Intro to Programming'));
      expect(unit.yearOfStudy, equals('1'));
      expect(unit.semester, equals('1'));
      expect(unit.lecturerName, equals('Dr. Jane'));
      expect(unit.isActive, isFalse);
    });

    test('CourseUnit.fromJson handles lessons.json format and default isActive', () {
      final json = {
        'Program Code': 'COMS',
        'Program Name': 'B.Sc. CS',
        'Unit Code': 'COMP 111',
        'Unit Name': 'Intro to CS',
        'Year of Study': '1',
        'Semester': '1',
        "Lecturer's Name": 'Prof. Oak',
      };

      final unit = CourseUnit.fromJson(json, 'doc_123');
      expect(unit.id, equals('doc_123'));
      expect(unit.unitCode, equals('COMP 111'));
      expect(unit.unitName, equals('Intro to CS'));
      expect(unit.isActive, isTrue);
    });
  });

  group('CourseService Active Filtering & Sync Tests', () {
    late CourseService courseService;

    setUp(() {
      courseService = CourseService();
      courseService.clearForTesting();
    });

    test('syncFromCurriculumRecords filters out inactive units from public selectors', () {
      final List<CurriculumRecord> records = [
        CurriculumRecord(
          id: 'unit_1',
          programCode: 'COMS',
          programName: 'Computer Science',
          unitCode: 'COMP 111',
          unitName: 'Programming 101',
          yearOfStudy: '1',
          semester: '1',
          lecturerName: 'Dr. Active',
          isActive: true,
        ),
        CurriculumRecord(
          id: 'unit_2',
          programCode: 'COMS',
          programName: 'Computer Science',
          unitCode: 'COMP 211',
          unitName: 'Data Structures',
          yearOfStudy: '2',
          semester: '1',
          lecturerName: 'Dr. Inactive',
          isActive: false, // Inactive!
        ),
        CurriculumRecord(
          id: 'unit_3',
          programCode: 'BEDA',
          programName: 'Education Arts',
          unitCode: 'EDF 111',
          unitName: 'History of Education',
          yearOfStudy: '1',
          semester: '1',
          lecturerName: 'Prof. Active',
          isActive: true,
        ),
      ];

      courseService.syncFromCurriculumRecords(records);

      // allUnits getter returns only active units
      expect(courseService.allUnits.length, equals(2));
      expect(courseService.allUnits.map((u) => u.unitCode), containsAll(['COMP 111', 'EDF 111']));
      expect(courseService.allUnits.map((u) => u.unitCode), isNot(contains('COMP 211')));

      // allUnitsIncludingInactive retains all units
      expect(courseService.allUnitsIncludingInactive.length, equals(3));

      // courseNames only contains active unit names
      expect(courseService.courseNames, contains('Programming 101'));
      expect(courseService.courseNames, contains('History of Education'));
      expect(courseService.courseNames, isNot(contains('Data Structures')));

      // courseCodes only contains active unit codes
      expect(courseService.courseCodes, contains('COMP 111'));
      expect(courseService.courseCodes, contains('EDF 111'));
      expect(courseService.courseCodes, isNot(contains('COMP 211')));

      // lecturersList only contains active unit lecturers
      expect(courseService.lecturersList, contains('Dr. Active'));
      expect(courseService.lecturersList, contains('Prof. Active'));
      expect(courseService.lecturersList, isNot(contains('Dr. Inactive')));

      // getUnitsByCode only returns active unit
      expect(courseService.getUnitsByCode('COMP 111').length, equals(1));
      expect(courseService.getUnitsByCode('COMP 211').length, equals(0));

      // Reverse lookup maps
      expect(courseService.getCodeByName('Programming 101'), equals('COMP 111'));
      expect(courseService.getCodeByName('Data Structures'), isNull);
      expect(courseService.getNameByCode('COMP 111'), equals('Programming 101'));
      expect(courseService.getNameByCode('COMP 211'), isNull);
    });

    test('Deactivating a unit dynamically excludes it upon sync', () {
      final recordActive = CurriculumRecord(
        id: 'unit_1',
        programCode: 'COMS',
        programName: 'Computer Science',
        unitCode: 'COMP 111',
        unitName: 'Programming 101',
        yearOfStudy: '1',
        semester: '1',
        lecturerName: 'Dr. Active',
        isActive: true,
      );

      courseService.syncFromCurriculumRecords([recordActive]);
      expect(courseService.courseNames, contains('Programming 101'));
      expect(courseService.getUnitsByCode('COMP 111').length, equals(1));

      // Admin deactivates the record
      final recordDeactivated = recordActive.copyWith(isActive: false);
      courseService.syncFromCurriculumRecords([recordDeactivated]);

      expect(courseService.courseNames, isNot(contains('Programming 101')));
      expect(courseService.getUnitsByCode('COMP 111'), isEmpty);
      expect(courseService.allUnits, isEmpty);
      expect(courseService.allUnitsIncludingInactive.length, equals(1));
    });

    test('Slash-separated unit codes parse correctly for active units', () {
      final record = CurriculumRecord(
        id: 'unit_slash',
        programCode: 'COMS',
        programName: 'Computer Science',
        unitCode: 'COMP 111 / COSC 111',
        unitName: 'Computer Systems',
        yearOfStudy: '1',
        semester: '1',
        lecturerName: 'Dr. Jane',
        isActive: true,
      );

      courseService.syncFromCurriculumRecords([record]);

      // Both codes should resolve to the unit
      expect(courseService.getNameByCode('COMP 111'), equals('Computer Systems'));
      expect(courseService.getNameByCode('COSC 111'), equals('Computer Systems'));
      expect(courseService.getUnitsByCode('COMP 111').length, equals(1));
      expect(courseService.getUnitsByCode('COSC 111').length, equals(1));
    });
  });
}
