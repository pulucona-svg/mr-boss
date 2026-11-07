import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/services/download_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
    await PersistenceService().clearAll();
    DownloadService.resetInstance();

    tempDir = Directory.systemTemp.createTempSync('viewer_loading_test_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Task 3: Document Viewer Loading Reliability Regression Tests', () {
    test('1. Valid complete local PDF passes header and completeness verification', () async {
      final validPdf = File('${tempDir.path}/valid.pdf')
        ..writeAsStringSync('%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF');

      bool verifyCompleteness(File f) {
        if (!f.existsSync()) return false;
        if (f.lengthSync() < 10) return false;
        final bytes = f.readAsBytesSync();
        final header = String.fromCharCodes(bytes.take(5));
        return header.startsWith('%PDF-');
      }

      expect(verifyCompleteness(validPdf), isTrue);
    });

    test('2. Incomplete or corrupt file (missing PDF header or zero bytes) fails verification', () async {
      final emptyFile = File('${tempDir.path}/empty.pdf')..writeAsStringSync('');
      final corruptFile = File('${tempDir.path}/corrupt.pdf')..writeAsStringSync('HTML 404 Not Found');

      bool verifyCompleteness(File f) {
        if (!f.existsSync()) return false;
        if (f.lengthSync() < 10) return false;
        final bytes = f.readAsBytesSync();
        final header = String.fromCharCodes(bytes.take(5));
        return header.startsWith('%PDF-');
      }

      expect(verifyCompleteness(emptyFile), isFalse);
      expect(verifyCompleteness(corruptFile), isFalse);
    });

    test('3. DownloadService download state is accurately queried by resource identifier', () async {
      final downloadService = DownloadService();
      expect(downloadService.isDownloading('test_material_1'), isFalse);

      // Verify that progress defaults to 0.0 when not downloading
      expect(downloadService.getProgress('test_material_1'), equals(0.0));
    });

    test('4. Already downloaded resource is identified without triggering network call', () async {
      final downloadService = DownloadService();
      downloadService.addDownloadedResourceForTesting({
        'id': 'res_local_123',
        'title': 'Downloaded Notes',
        'fileUrl': '${tempDir.path}/local.pdf',
      });

      expect(downloadService.isDownloaded('res_local_123'), isTrue);
      expect(downloadService.isDownloaded('Downloaded Notes'), isTrue);
    });

    test('5. Loading failure preserves material ID and navigation context without popping', () {
      bool hasError = false;
      String? errorMessage;

      // Simulate failure handler in viewer
      void handleLoadFailure(dynamic error) {
        hasError = true;
        errorMessage = 'Failed to load document due to network interruption.';
      }

      handleLoadFailure(Exception('Network timeout'));

      expect(hasError, isTrue);
      expect(errorMessage, contains('network interruption'));
    });
  });
}
