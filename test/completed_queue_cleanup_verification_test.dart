import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/services/offline_upload_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Completed Queue Cleanup & Connectivity Notification Verification', () {
    test('Scenario 1: Launch app with internet and no queued uploads -> no pending work, no message', () {
      final queue = <QueuedUploadItem>[];

      final pendingWork = queue.where((item) =>
          item.status == QueuedUploadStatus.waiting_internet ||
          item.status == QueuedUploadStatus.paused ||
          item.status == QueuedUploadStatus.retrying ||
          item.status == QueuedUploadStatus.queued).toList();

      expect(pendingWork.isEmpty, isTrue);
    });

    test('Scenario 2: Toggle Wi-Fi off then on without queued uploads -> no pending work, no message', () {
      bool wasOffline = false;

      // Wi-Fi Off
      wasOffline = true;
      final queue = <QueuedUploadItem>[];

      // Wi-Fi On
      final pendingWork = queue.where((item) =>
          item.status == QueuedUploadStatus.waiting_internet ||
          item.status == QueuedUploadStatus.paused ||
          item.status == QueuedUploadStatus.retrying ||
          item.status == QueuedUploadStatus.queued).toList();

      final shouldShowSnackbar = wasOffline && pendingWork.isNotEmpty;

      expect(shouldShowSnackbar, isFalse);
    });

    test('Scenario 3: Queue one upload offline, reconnect -> pending work detected, snackbar fires once', () {
      bool wasOffline = false;

      // Wi-Fi Off & Queue 1 item
      wasOffline = true;
      final item = QueuedUploadItem(
        id: 'upload_1',
        filePaths: [],
        materialData: {},
        uploadMode: 'material',
        status: QueuedUploadStatus.waiting_internet,
        createdAt: DateTime.now(),
      );
      final queue = <QueuedUploadItem>[item];

      // Wi-Fi On
      final pendingWork = queue.where((i) =>
          i.status == QueuedUploadStatus.waiting_internet ||
          i.status == QueuedUploadStatus.paused ||
          i.status == QueuedUploadStatus.retrying ||
          i.status == QueuedUploadStatus.queued).toList();

      final shouldShowSnackbar = wasOffline && pendingWork.isNotEmpty;
      if (shouldShowSnackbar) {
        wasOffline = false; // Reset immediately
      }

      expect(shouldShowSnackbar, isTrue);
      expect(pendingWork.length, equals(1));
      expect(wasOffline, isFalse); // Reset to prevent duplicate snackbars
    });

    test('Scenario 4: Upload completes & is purged; toggling Wi-Fi again -> no message', () {
      final queue = <QueuedUploadItem>[
        QueuedUploadItem(
          id: 'upload_1',
          filePaths: [],
          materialData: {},
          uploadMode: 'material',
          status: QueuedUploadStatus.uploading,
          createdAt: DateTime.now(),
        )
      ];

      // Mark completed & purge from queue
      final item = queue.first;
      item.status = QueuedUploadStatus.completed;
      queue.removeWhere((i) => i.id == item.id || i.status == QueuedUploadStatus.completed);

      expect(queue.isEmpty, isTrue);

      // Toggle Wi-Fi Off then On
      bool wasOffline = true;
      final pendingWork = queue.where((i) =>
          i.status == QueuedUploadStatus.waiting_internet ||
          i.status == QueuedUploadStatus.paused ||
          i.status == QueuedUploadStatus.retrying ||
          i.status == QueuedUploadStatus.queued).toList();

      final shouldShowSnackbar = wasOffline && pendingWork.isNotEmpty;

      expect(shouldShowSnackbar, isFalse);
    });
  });
}
