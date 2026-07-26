import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/models/material_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Category Filtering Verification Tests', () {
    final sampleResources = [
      Resource(
        id: '1',
        title: 'Organic Chemistry Notes',
        fileName: 'chem.pdf',
        type: 'Notes',
        thumbnailUrl: 'https://example.com/thumb1.jpg',
        fileUrl: 'https://example.com/chem.pdf',
        fileId: 'file_1',
        unitName: 'Organic Chemistry',
        unitCode: 'CHEM210',
        year: '2026',
        uploadYear: '2026',
        publicationYear: '2026',
        yearOfStudy: '2nd Year',
        semester: 'Semester 1',
        uploadedBy: 'Test',
        uploaderRole: 'Student',
        uploaderId: '123',
        lecturers: ['Dr. Smith'],
        uploadDate: DateTime.now(),
      ),
      Resource(
        id: '2',
        title: 'Physics CAT 1',
        fileName: 'physics_cat.pdf',
        type: 'CATs',
        thumbnailUrl: 'https://example.com/thumb2.jpg',
        fileUrl: 'https://example.com/physics.pdf',
        fileId: 'file_2',
        unitName: 'Physics I',
        unitCode: 'PHYS110',
        year: '2026',
        uploadYear: '2026',
        publicationYear: '2026',
        yearOfStudy: '1st Year',
        semester: 'Semester 1',
        uploadedBy: 'Test',
        uploaderRole: 'Student',
        uploaderId: '123',
        lecturers: ['Prof. Adams'],
        uploadDate: DateTime.now(),
      ),
      Resource(
        id: '3',
        title: 'Calculus Main Exam',
        fileName: 'calc_exam.pdf',
        type: 'Exams',
        thumbnailUrl: 'https://example.com/thumb3.jpg',
        fileUrl: 'https://example.com/calc.pdf',
        fileId: 'file_3',
        unitName: 'Calculus I',
        unitCode: 'MATH120',
        year: '2026',
        uploadYear: '2026',
        publicationYear: '2026',
        yearOfStudy: '1st Year',
        semester: 'Semester 2',
        uploadedBy: 'Test',
        uploaderRole: 'Student',
        uploaderId: '123',
        lecturers: ['Dr. Jones'],
        uploadDate: DateTime.now(),
      ),
      Resource(
        id: '4',
        title: 'Biology Lab Manual',
        fileName: 'bio_lab.pdf',
        type: 'Prac Manual',
        thumbnailUrl: 'https://example.com/thumb4.jpg',
        fileUrl: 'https://example.com/lab.pdf',
        fileId: 'file_4',
        unitName: 'Biology I',
        unitCode: 'BIOL101',
        year: '2026',
        uploadYear: '2026',
        publicationYear: '2026',
        yearOfStudy: '1st Year',
        semester: 'Semester 1',
        uploadedBy: 'Test',
        uploaderRole: 'Student',
        uploaderId: '123',
        lecturers: ['Dr. Green'],
        uploadDate: DateTime.now(),
      ),
      Resource(
        id: '5',
        title: 'Computer Science Class Timetable',
        fileName: 'cs_timetable.png',
        type: 'Class Timetable',
        thumbnailUrl: 'https://example.com/cs_timetable.png',
        fileUrl: 'https://example.com/cs_timetable.png',
        fileId: 'file_5',
        unitName: 'Computer Science Timetable',
        unitCode: 'COMP',
        year: '2026',
        uploadYear: '2026',
        publicationYear: '2026',
        yearOfStudy: '1st Year',
        semester: 'Semester 1',
        uploadedBy: 'Test',
        uploaderRole: 'Student',
        uploaderId: '123',
        lecturers: ['TBD'],
        uploadDate: DateTime.now(),
      ),
      Resource(
        id: '6',
        title: 'Engineering Exam Timetable',
        fileName: 'eng_exam_tt.png',
        type: 'EXAM Timetable',
        thumbnailUrl: 'https://example.com/eng_exam_tt.png',
        fileUrl: 'https://example.com/eng_exam_tt.png',
        fileId: 'file_6',
        unitName: 'Engineering Exam Timetable',
        unitCode: 'ENG',
        year: '2026',
        uploadYear: '2026',
        publicationYear: '2026',
        yearOfStudy: '4th Year',
        semester: 'Semester 2',
        uploadedBy: 'Test',
        uploaderRole: 'Student',
        uploaderId: '123',
        lecturers: ['TBD'],
        uploadDate: DateTime.now(),
      ),
    ];

    test('1. Category "All" includes Notes, CATs, Exams, Practicals, and Timetables in unified list', () {
      const category = 'All';

      final filtered = sampleResources.where((res) {
        final isTimetableType = res.type.toLowerCase().contains('timetable') ||
            res.type.toLowerCase().contains('time tables') ||
            res.type.toLowerCase().contains('time table');

        final isAllCategory = category == 'All';
        final isTimetableCategory = category == 'Time tables';

        if (isAllCategory) {
          return true; // Unified "All" includes every uploaded resource
        } else if (isTimetableCategory) {
          return isTimetableType;
        } else {
          return res.type == category;
        }
      }).toList();

      expect(filtered.length, equals(6));
      expect(filtered.map((r) => r.type), containsAll([
        'Notes',
        'CATs',
        'Exams',
        'Prac Manual',
        'Class Timetable',
        'EXAM Timetable',
      ]));
    });

    test('2. Category "Time tables" includes ONLY timetable resources', () {
      const category = 'Time tables';

      final filtered = sampleResources.where((res) {
        final isTimetableType = res.type.toLowerCase().contains('timetable') ||
            res.type.toLowerCase().contains('time tables') ||
            res.type.toLowerCase().contains('time table');

        final isAllCategory = category == 'All';
        final isTimetableCategory = category == 'Time tables';

        if (isAllCategory) {
          return true;
        } else if (isTimetableCategory) {
          return isTimetableType;
        } else {
          return res.type == category;
        }
      }).toList();

      expect(filtered.length, equals(2));
      expect(filtered.map((r) => r.type), containsAll(['Class Timetable', 'EXAM Timetable']));
      expect(filtered.map((r) => r.type), isNot(contains('Notes')));
    });
  });
}
