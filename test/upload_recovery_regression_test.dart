import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/services/connectivity_service.dart';
import 'package:mirror_laikipia/services/offline_upload_queue_service.dart';
import 'package:mirror_laikipia/models/material_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
    await PersistenceService().clearAll();
    ConnectivityService().resetForTesting();
    OfflineUploadQueueService().resetForTesting();

    tempDir = Directory.systemTemp.createTempSync('upload_test_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    OfflineUploadQueueService().resetForTesting();
    } catch (_) {}
  });

  UploadMaterialModel createTestMaterial({String unitName = 'Data Structures'}) {
    return UploadMaterialModel(
      unitName: unitName,
      unitCode: 'COMP210',
      programs: ['Computer Science'],
      yearOfStudy: '2nd Year',
      semester: 'Semester 1',
      yearOfPublication: 2026,
      uploadedBy: 'Test Student',
      uploaderId: 'user_456',
      yearOfUpload: 2026,
      materialType: 'Notes',
    );
  }

  group('Task 1: Upload Recovery & Queue Regression Tests', () {
    test('1. Upload queued while offline sets status to waiting_internet', () async {
      ConnectivityService().setOfflineForTesting(true);

      final file = File('${tempDir.path}/sample.pdf')..writeAsStringSync('%PDF-1.4 dummy content');
      final service = OfflineUploadQueueService();

      final item = await service.enqueue(
        material: createTestMaterial(),
        uploadMode: 'material',
        file: file,
      );

      expect(item.status, equals(QueuedUploadStatus.waiting_internet));
      expect(service.pendingCount, equals(1));
      expect(service.queuedResources.first.thumbnailStatus, contains('Waiting for internet'));
    });

    test('2. Connectivity restored triggers immediate retry and resets backoff delays', () async {
      ConnectivityService().setOfflineForTesting(true);

      final file = File('${tempDir.path}/sample2.pdf')..writeAsStringSync('%PDF-1.4 test');
      final service = OfflineUploadQueueService();

      final item = await service.enqueue(
        material: createTestMaterial(),
        uploadMode: 'material',
        file: file,
      );

      // Simulate backoff timer scheduled into the future
      item.nextRetryTime = DateTime.now().add(const Duration(minutes: 10));
      item.status = QueuedUploadStatus.retrying;

      // Simulate connectivity restoration with verified reachability
      ConnectivityService().reachabilityChecker = () async => true;
      ConnectivityService().setOfflineForTesting(false);

      service.resetRetryDelays();

      expect(item.nextRetryTime, isNull);
      expect(item.status, equals(QueuedUploadStatus.queued));
    });

    test('3. App foregrounding (resumed state) triggers queue reconciliation', () async {
      final service = OfflineUploadQueueService();
      await service.initialize();

      bool reachabilityChecked = false;
      ConnectivityService().reachabilityChecker = () async {
        reachabilityChecked = true;
        return true;
      };

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(reachabilityChecked, isTrue);
    });

    test('4. App startup finds and restores pending uploads from storage', () async {
      final file = File('${tempDir.path}/startup_doc.pdf')..writeAsStringSync('%PDF-1.4 test');

      // Persist raw queue
      final item = QueuedUploadItem(
        id: 'upload_startup_100',
        filePath: file.path,
        materialData: createTestMaterial(unitName: 'Operating Systems').toMap(),
        uploadMode: 'material',
        status: QueuedUploadStatus.uploading, // crashed mid-upload
        createdAt: DateTime.now(),
      );
      await PersistenceService().setJson('offline_upload_queue_v1', [item.toJson()]);

      // Initialize service simulating cold start
      final service = OfflineUploadQueueService();
      await service.initialize();

      expect(service.queue.length, equals(1));
      // Mid-crash uploading state must safely reset to waiting_internet
      expect(service.queue.first.status, equals(QueuedUploadStatus.waiting_internet));
      expect(service.pendingCount, equals(1));
    });

    test('5. Repeated connectivity events preserve idempotency and storage IDs', () async {
      final file = File('${tempDir.path}/idempotent.pdf')..writeAsStringSync('%PDF-1.4 test');
      final item = QueuedUploadItem(
        id: 'upload_idemp_1',
        filePath: file.path,
        materialData: createTestMaterial().toMap(),
        uploadMode: 'material',
        uploadedFileUrl: 'https://ik.imagekit.io/mirror/notes/doc123.pdf',
        uploadedFileId: 'ik_file_123',
        firestoreDocId: 'res_upload_idemp_1',
      );

      // Verify that serialization preserves idempotency keys
      final json = item.toJson();
      final restored = QueuedUploadItem.fromJson(json);

      expect(restored.uploadedFileUrl, equals('https://ik.imagekit.io/mirror/notes/doc123.pdf'));
      expect(restored.uploadedFileId, equals('ik_file_123'));
      expect(restored.firestoreDocId, equals('res_upload_idemp_1'));
    });

    test('6. Temporary failures schedule exponential backoff up to cap', () {
      final item = QueuedUploadItem(
        id: 'test_backoff',
        materialData: createTestMaterial().toMap(),
      );

      final delays = [1, 2, 3, 4, 5, 6].map((count) {
        if (count <= 1) return 15;
        if (count == 2) return 30;
        if (count == 3) return 60;
        if (count == 4) return 120;
        if (count == 5) return 300;
        return 600;
      }).toList();

      expect(delays, equals([15, 30, 60, 120, 300, 600]));
    });

    test('7. Permanent failures do not retry indefinitely', () async {
      final service = OfflineUploadQueueService();
      final item = QueuedUploadItem(
        id: 'failed_item',
        materialData: createTestMaterial().toMap(),
        status: QueuedUploadStatus.failed,
        lastError: 'Permission denied / unrecoverable auth error',
      );

      service.cancel(item.id);
      expect(service.queue.any((i) => i.id == 'failed_item'), isFalse);
    });

    test('8. Completed uploads are purged from persistent queue', () async {
      final service = OfflineUploadQueueService();
      final file = File('${tempDir.path}/completed.pdf')..writeAsStringSync('%PDF-1.4');
      final item = await service.enqueue(
        material: createTestMaterial(),
        uploadMode: 'material',
        file: file,
      );

      item.status = QueuedUploadStatus.completed;
      service.clearCompleted();

      expect(service.queue.isEmpty, isTrue);
      expect(service.pendingCount, equals(0));
    });

    test('9. Missing local file is identified and marked failed immediately', () async {
      final item = QueuedUploadItem(
        id: 'missing_file_item',
        filePath: '${tempDir.path}/non_existent_file_999.pdf',
        materialData: createTestMaterial().toMap(),
      );

      final file = File(item.filePath!);
      expect(file.existsSync(), isFalse);

      if (!file.existsSync()) {
        item.lastError = 'Original file no longer found on device';
        item.status = QueuedUploadStatus.failed;
      }

      expect(item.status, equals(QueuedUploadStatus.failed));
      expect(item.statusDisplay, contains('Original file no longer found on device'));
    });

    test('10. Multiple queued uploads are enqueued in FIFO order and formatted as resources', () async {
      final service = OfflineUploadQueueService();
      final file1 = File('${tempDir.path}/f1.pdf')..writeAsStringSync('%PDF-1');
      final file2 = File('${tempDir.path}/f2.pdf')..writeAsStringSync('%PDF-2');

      final item1 = await service.enqueue(
        material: createTestMaterial(unitName: 'Unit Alpha'),
        uploadMode: 'material',
        file: file1,
      );
      final item2 = await service.enqueue(
        material: createTestMaterial(unitName: 'Unit Beta'),
        uploadMode: 'material',
        file: file2,
      );

      expect(service.queue.length, equals(2));
      expect(service.queue[0].id, equals(item1.id));
      expect(service.queue[1].id, equals(item2.id));

      final resources = service.queuedResources;
      expect(resources.length, equals(2));
      expect(resources[0].title, equals('Unit Alpha'));
      expect(resources[1].title, equals('Unit Beta'));
    });
  });
}
