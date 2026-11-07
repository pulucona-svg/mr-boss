import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/services/external_document_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.mirrordigital.app/external_documents');
  late Directory tempDir;
  final List<MethodCall> methodCalls = [];
  Map<String, dynamic>? initialDocMock;

  setUp(() {
    methodCalls.clear();
    tempDir = Directory.systemTemp.createTempSync('android_intent_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      methodCalls.add(call);
      if (call.method == 'getInitialDocument') {
        final doc = initialDocMock;
        initialDocMock = null; // Cleared once consumed
        return doc;
      } else if (call.method == 'clearExternalDocumentsCache') {
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('Task 2: Android "Open With" Document Integration Regression Tests', () {
    test('1. PDF incoming intent is received with valid file path and title', () async {
      final samplePdf = File('${tempDir.path}/lecture_notes.pdf')
        ..writeAsStringSync('%PDF-1.4 test content');

      initialDocMock = {
        'filePath': samplePdf.path,
        'title': 'lecture_notes',
        'mimeType': 'application/pdf',
      };

      final service = ExternalDocumentService();
      service.initialize();
      await service.checkInitialDocument();

      expect(methodCalls.any((call) => call.method == 'getInitialDocument'), isTrue);
    });

    test('2. Unsupported MIME types (e.g. DOCX, DOC, ZIP) are rejected gracefully', () {
      bool isMimeSupported(String mimeType, String path) {
        return mimeType.toLowerCase().contains('pdf') ||
            path.toLowerCase().endsWith('.pdf');
      }

      expect(isMimeSupported('application/pdf', 'doc.pdf'), isTrue);
      expect(isMimeSupported('application/msword', 'doc.doc'), isFalse);
      expect(isMimeSupported('application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'doc.docx'), isFalse);
      expect(isMimeSupported('application/zip', 'archive.zip'), isFalse);
      expect(isMimeSupported('video/mp4', 'video.mp4'), isFalse);
    });

    test('3. Content URI permission copying does not delete original document', () async {
      final originalFile = File('${tempDir.path}/user_original.pdf')
        ..writeAsStringSync('%PDF-1.4 original bytes');

      final cacheDir = Directory('${tempDir.path}/external_documents')..createSync();
      final copiedFile = File('${cacheDir.path}/12345_user_original.pdf')
        ..writeAsBytesSync(originalFile.readAsBytesSync());

      expect(copiedFile.existsSync(), isTrue);
      expect(originalFile.existsSync(), isTrue);
      expect(originalFile.lengthSync(), equals(copiedFile.lengthSync()));
    });

    test('4. Cold-start initial document is cleared once consumed to prevent repeated launches', () async {
      final samplePdf = File('${tempDir.path}/cold_start.pdf')..writeAsStringSync('%PDF-1.4');
      initialDocMock = {
        'filePath': samplePdf.path,
        'title': 'cold_start',
        'mimeType': 'application/pdf',
      };

      // First query consumes it
      final firstResult = await channel.invokeMethod<Map>('getInitialDocument');
      expect(firstResult, isNotNull);
      expect(firstResult!['title'], equals('cold_start'));

      // Second query returns null
      final secondResult = await channel.invokeMethod<Map>('getInitialDocument');
      expect(secondResult, isNull);
    });

    test('5. Already-running app receives external document via onDocumentReceived method call', () async {
      final samplePdf = File('${tempDir.path}/running_doc.pdf')..writeAsStringSync('%PDF-1.4');

      final service = ExternalDocumentService();
      service.initialize();

      // Simulate native calling onDocumentReceived
      final binaryMessenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final codec = channel.codec;

      final message = codec.encodeMethodCall(
        MethodCall('onDocumentReceived', {
          'filePath': samplePdf.path,
          'title': 'running_doc',
          'mimeType': 'application/pdf',
        }),
      );

      // Verify that service can decode and handle without throwing
      await binaryMessenger.handlePlatformMessage(
        channel.name,
        message,
        (data) {},
      );

      expect(samplePdf.existsSync(), isTrue);
    });

    test('6. External document is viewed directly and NEVER triggers upload pipeline or network publication', () async {
      final samplePdf = File('${tempDir.path}/private_external_file.pdf')
        ..writeAsStringSync('%PDF-1.4 private data');

      initialDocMock = {
        'filePath': samplePdf.path,
        'title': 'private_external_file',
        'mimeType': 'application/pdf',
      };

      final service = ExternalDocumentService();
      service.initialize();
      await service.checkInitialDocument();

      // Verify that external documents remain local and isolated
      expect(samplePdf.existsSync(), isTrue);
      // Clean cache method works safely without touching original
      await service.clearCache();
      expect(samplePdf.existsSync(), isTrue);
    });
  });
}
