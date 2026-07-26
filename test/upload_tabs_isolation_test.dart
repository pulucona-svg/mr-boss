import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/providers/upload_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
  });

  group('Upload Menu Form Isolation Tests', () {
    test('1. Material and Timetable providers are completely isolated', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final materialNotifier = container.read(materialUploadProvider.notifier);
      final timetableNotifier = container.read(timetableUploadProvider.notifier);

      // Modify Material tab state
      materialNotifier.updateUnitName('Organic Chemistry');
      materialNotifier.updateUnitCode('CHEM210');
      materialNotifier.toggleProgram('BSc Chemistry');

      // Modify Timetable tab state
      timetableNotifier.updateProgram('BSc Computer Science');
      timetableNotifier.updateYearOfStudy('2nd Year');

      final materialState = container.read(materialUploadProvider);
      final timetableState = container.read(timetableUploadProvider);

      // Verify Material tab values
      expect(materialState.material.unitName, equals('Organic Chemistry'));
      expect(materialState.material.unitCode, equals('CHEM210'));
      expect(materialState.material.programs, contains('BSc Chemistry'));
      expect(materialState.uploadMode, equals('material'));

      // Verify Timetable tab values are NOT polluted by Material tab
      expect(timetableState.material.unitName, equals(''));
      expect(timetableState.material.unitCode, equals(''));
      expect(timetableState.material.programs, contains('BSc Computer Science'));
      expect(timetableState.material.programs, isNot(contains('BSc Chemistry')));
      expect(timetableState.uploadMode, equals('timetable'));
    });

    test('2. Timetable validation succeeds with program, code, year, semester and file', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(timetableUploadProvider.notifier);

      notifier.updateProgram('Computer Science');
      notifier.updateProgramCode('COMP');
      notifier.updateYearOfStudy('1st Year');
      notifier.updateSemester('Semester 1');

      var state = container.read(timetableUploadProvider);
      expect(state.isValid, isFalse); // False because file is missing

      // Simulate timetable image pick
      notifier.state = state.copyWith(
        material: state.material.copyWith(
          file: File('dummy_timetable.png'),
          thumbnail: File('dummy_timetable.png'),
          fileFormat: 'Image',
        ),
      );

      state = container.read(timetableUploadProvider);
      expect(state.isValid, isTrue); // Should be valid!
    });
  });
}
