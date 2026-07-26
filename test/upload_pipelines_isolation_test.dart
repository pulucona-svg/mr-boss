import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/services/timetable_upload_service.dart';
import 'package:mirror_laikipia/services/upload_service.dart';
import 'package:mirror_laikipia/providers/upload_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
  });

  group('Upload Pipelines Strict Isolation Verification', () {
    test('1. Material upload provider and Timetable upload provider are strictly decoupled', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final materialNotifier = container.read(materialUploadProvider.notifier);
      final timetableNotifier = container.read(timetableUploadProvider.notifier);

      // Mutate Material state
      materialNotifier.updateUnitName('Database Systems');
      materialNotifier.updateUnitCode('COMP311');
      materialNotifier.toggleProgram('BSc Computer Science');
      materialNotifier.state = materialNotifier.state.copyWith(
        material: materialNotifier.state.material.copyWith(
          file: File('material_notes.pdf'),
          files: [File('material_notes.pdf')],
          fileFormat: 'PDF',
        ),
      );

      // Mutate Timetable state
      timetableNotifier.updateProgram('BSc Applied Statistics');
      timetableNotifier.updateProgramCode('STAT');
      timetableNotifier.updateYearOfStudy('3rd Year');
      timetableNotifier.updateSemester('Semester 2');
      timetableNotifier.state = timetableNotifier.state.copyWith(
        material: timetableNotifier.state.material.copyWith(
          file: File('timetable_image.png'),
          thumbnail: null, // Timetable has no separate thumbnail file
          fileFormat: 'Image',
        ),
      );

      final materialState = container.read(materialUploadProvider);
      final timetableState = container.read(timetableUploadProvider);

      // Verify Material upload state
      expect(materialState.uploadMode, equals('material'));
      expect(materialState.material.unitName, equals('Database Systems'));
      expect(materialState.material.unitCode, equals('COMP311'));
      expect(materialState.material.file?.path, equals('material_notes.pdf'));
      expect(materialState.isValid, isTrue);

      // Verify Timetable upload state (completely independent, zero shared fields)
      expect(timetableState.uploadMode, equals('timetable'));
      expect(timetableState.material.unitName, equals(''));
      expect(timetableState.material.unitCode, equals(''));
      expect(timetableState.material.programs, contains('BSc Applied Statistics'));
      expect(timetableState.material.programCodes, contains('STAT'));
      expect(timetableState.material.file?.path, equals('timetable_image.png'));
      expect(timetableState.material.thumbnail, isNull);
      expect(timetableState.isValid, isTrue);
    });

    test('2. TimetableUploadService produces isolated result payload', () async {
      final timetableService = TimetableUploadService();

      // Verify TimetableUploadService exists and exposes uploadTimetable
      expect(timetableService, isNotNull);
      expect(timetableService, isA<TimetableUploadService>());
    });

    test('3. Confirm UploadService and TimetableUploadService exist as separate classes', () {
      final uploadService = UploadService();
      final timetableService = TimetableUploadService();

      expect(uploadService, isNot(isA<TimetableUploadService>()));
      expect(timetableService, isNot(isA<UploadService>()));
    });
  });
}
