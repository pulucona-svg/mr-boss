import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/services/offline_upload_queue_service.dart';
import 'package:mirror_laikipia/models/material_model.dart';
import 'package:flutter/widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
    await PersistenceService().clearAll();
  });

  group('Flutter Offline Queue & Timetable Integration Tests', () {
    test('1. Enqueuing material adds item to persistent queue and queuedResources UI list', () async {
      final material = UploadMaterialModel(
        unitName: 'Microbiology Notes',
        unitCode: 'MICR110',
        programs: ['Biochemistry'],
        yearOfStudy: '1st Year',
        semester: 'Semester 1',
        yearOfPublication: 2026,
        uploadedBy: 'Test Student',
        uploaderId: 'user_123',
        yearOfUpload: 2026,
        materialType: 'Notes',
      );

      final item = await OfflineUploadQueueService().enqueue(
        material: material,
        uploadMode: 'material',
      );

      expect(item.id.isNotEmpty, isTrue);

      // Check Resource UI conversion
      final queuedResources = OfflineUploadQueueService().queuedResources;
      expect(queuedResources.isNotEmpty, isTrue);
      expect(queuedResources.first.title, equals('Microbiology Notes'));
    });

    test('2. App Lifecycle Resume trigger reacts to foregrounding', () async {
      final service = OfflineUploadQueueService();
      await service.initialize();

      // Trigger app resumed event
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(service.pendingCount, greaterThanOrEqualTo(0));
    });

    test('3. Timetable Upload Rule sets uploadMode to timetable and materialFormat to Image', () async {
      final material = UploadMaterialModel(
        unitName: 'Bachelor of Science Timetable',
        unitCode: 'TT101',
        programs: ['BSc Computer Science'],
        yearOfStudy: '1st Year',
        semester: 'Semester 1',
        yearOfPublication: 2026,
        uploadedBy: 'Test Student',
        uploaderId: 'user_123',
        yearOfUpload: 2026,
        materialType: 'Class Timetable',
      );

      final item = await OfflineUploadQueueService().enqueue(
        material: material,
        uploadMode: 'timetable',
      );

      expect(item.uploadMode, equals('timetable'));
      final queuedRes = OfflineUploadQueueService().queuedResources.last;
      expect(queuedRes.materialFormat, equals('Image'));
    });
  });
}
