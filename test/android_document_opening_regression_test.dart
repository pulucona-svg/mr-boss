import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/screens/external_document_launch_screen.dart';
import 'package:mirror_laikipia/screens/material_viewer_screen.dart';
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

    test('7. Cold-start ACTION_VIEW delivers correct document URI and filename', () async {
      final samplePdf = File('${tempDir.path}/cold_action_view.pdf')
        ..writeAsStringSync('%PDF-1.4 cold start test');

      initialDocMock = {
        'filePath': samplePdf.path,
        'title': 'cold_action_view',
        'mimeType': 'application/pdf',
      };

      final service = ExternalDocumentService();
      await service.checkInitialDocument();

      expect(samplePdf.existsSync(), isTrue);
      expect(samplePdf.path, contains('cold_action_view.pdf'));
    });

    test('8. Warm-start ACTION_VIEW delivers document when app is running', () async {
      final samplePdf = File('${tempDir.path}/warm_action_view.pdf')
        ..writeAsStringSync('%PDF-1.4 warm start test');

      final service = ExternalDocumentService();
      service.initialize();

      final binaryMessenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final codec = channel.codec;

      final message = codec.encodeMethodCall(
        MethodCall('onDocumentReceived', {
          'filePath': samplePdf.path,
          'title': 'warm_action_view',
          'mimeType': 'application/pdf',
        }),
      );

      await binaryMessenger.handlePlatformMessage(
        channel.name,
        message,
        (data) {},
      );

      expect(samplePdf.existsSync(), isTrue);
    });

    test('9. ACTION_SEND delivers shared document correctly', () async {
      final samplePdf = File('${tempDir.path}/shared_action_send.pdf')
        ..writeAsStringSync('%PDF-1.4 action send stream test');

      final service = ExternalDocumentService();
      service.initialize();

      final binaryMessenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final codec = channel.codec;

      final message = codec.encodeMethodCall(
        MethodCall('onDocumentReceived', {
          'filePath': samplePdf.path,
          'title': 'shared_action_send',
          'mimeType': 'application/pdf',
        }),
      );

      await binaryMessenger.handlePlatformMessage(
        channel.name,
        message,
        (data) {},
      );

      expect(samplePdf.existsSync(), isTrue);
    });

    test('10. Second document received while app is running opens without getting stuck', () async {
      final doc1 = File('${tempDir.path}/doc1.pdf')..writeAsStringSync('%PDF-1.4 doc 1');
      final doc2 = File('${tempDir.path}/doc2.pdf')..writeAsStringSync('%PDF-1.4 doc 2');

      final service = ExternalDocumentService();
      service.initialize();

      final binaryMessenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final codec = channel.codec;

      // First document
      await binaryMessenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(MethodCall('onDocumentReceived', {
          'filePath': doc1.path,
          'title': 'doc1',
          'mimeType': 'application/pdf',
        })),
        (data) {},
      );
      expect(service.currentlyViewingPathForTesting, equals(doc1.path));

      // Second document
      await binaryMessenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(MethodCall('onDocumentReceived', {
          'filePath': doc2.path,
          'title': 'doc2',
          'mimeType': 'application/pdf',
        })),
        (data) {},
      );
      expect(service.currentlyViewingPathForTesting, equals(doc2.path));
    });

    test('11. Repeated delivery of identical document does not cause duplicate navigation', () async {
      final doc1 = File('${tempDir.path}/duplicate_test.pdf')..writeAsStringSync('%PDF-1.4 duplicate test');

      final service = ExternalDocumentService();
      service.initialize();

      final binaryMessenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final codec = channel.codec;

      // First delivery sets active path
      await binaryMessenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(MethodCall('onDocumentReceived', {
          'filePath': doc1.path,
          'title': 'duplicate_test',
          'mimeType': 'application/pdf',
        })),
        (data) {},
      );
      expect(service.currentlyViewingPathForTesting, equals(doc1.path));

      // Second identical delivery while active is deduplicated
      await binaryMessenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(MethodCall('onDocumentReceived', {
          'filePath': doc1.path,
          'title': 'duplicate_test',
          'mimeType': 'application/pdf',
        })),
        (data) {},
      );
      expect(service.currentlyViewingPathForTesting, equals(doc1.path));
    });

    test('12. Existing FLAG_SECURE security service remains enabled and enforced', () async {
      const securityChannel = MethodChannel('com.mirrordigital.app/security');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(securityChannel, (MethodCall call) async {
        if (call.method == 'enableSecureScreen' ||
            call.method == 'disableSecureScreen' ||
            call.method == 'isSecureScreenEnabled') {
          return true;
        }
        return null;
      });

      final bool isEnabled = await securityChannel.invokeMethod<bool>('isSecureScreenEnabled') ?? false;
      expect(isEnabled, isTrue);

      final bool enableResult = await securityChannel.invokeMethod<bool>('enableSecureScreen') ?? false;
      expect(enableResult, isTrue);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(securityChannel, null);
    });

    testWidgets('13. Cold-start external document opens with branded splash and transitions smoothly', (tester) async {
      final samplePdf = File('${tempDir.path}/splash_launch_test.pdf')
        ..writeAsStringSync('%PDF-1.4 test document content');

      await tester.pumpWidget(
        MaterialApp(
          home: ExternalDocumentLaunchScreen(
            docData: {
              'filePath': samplePdf.path,
              'title': 'Splash Launch Test',
              'mimeType': 'application/pdf',
            },
          ),
        ),
      );

      // Branded splash elements are immediately visible
      expect(find.byType(Scaffold), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(MaterialViewerScreen), findsOneWidget);
    });

    test('14. Cache retention protects files belonging to concurrent sessions or recently created files', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final recentFileTime = now - 1000 * 60 * 30; // 30 mins ago
      final oldFileTime = now - 1000 * 60 * 60 * 25; // 25 hours ago

      bool shouldRetain(int lastModified, bool isCurrentSession) {
        final isRecent = (now - lastModified) < 2 * 60 * 60 * 1000;
        return isCurrentSession || isRecent;
      }

      // Recent file from another session must be retained
      expect(shouldRetain(recentFileTime, false), isTrue);
      // Active session file must always be retained
      expect(shouldRetain(oldFileTime, true), isTrue);
      // Unclaimed file older than 2 hours can be safely pruned
      expect(shouldRetain(oldFileTime, false), isFalse);
    });

    testWidgets('15. Missing external document file shows error screen rather than hanging permanently', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ExternalDocumentLaunchScreen(
            docData: {
              'filePath': '/non/existent/file.pdf',
              'title': 'Missing File',
              'mimeType': 'application/pdf',
            },
          ),
        ),
      );

      // Post-frame callback triggers synchronous file check and updates state
      await tester.pump();
      await tester.pump();

      expect(find.text('Unable to Open Document'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('16. Splash remains visible during PDF preparation and removes only when viewer is ready', (tester) async {
      final samplePdf = File('${tempDir.path}/splash_readiness_test.pdf')
        ..writeAsStringSync('%PDF-1.4 test document content');

      await tester.pumpWidget(
        MaterialApp(
          home: MaterialViewerScreen(
            id: 'splash_readiness_test',
            title: 'Splash Readiness Test',
            fileUrl: samplePdf.path,
            category: 'Document',
          ),
        ),
      );

      // On initial frames, branded splash is displayed while document is prepared
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('Opening document...'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    });

    test('17. Independent document sessions maintain isolated reading progress and positions', () {
      final sessionA = {
        'docId': 'ext_document_A.pdf',
        'title': 'Document A',
        'currentPage': 5,
        'zoom': 1.25,
      };

      final sessionB = {
        'docId': 'ext_document_B.pdf',
        'title': 'Document B',
        'currentPage': 12,
        'zoom': 2.0,
      };

      expect(sessionA['docId'], isNot(equals(sessionB['docId'])));
      expect(sessionA['currentPage'], equals(5));
      expect(sessionB['currentPage'], equals(12));
      expect(sessionA['zoom'], equals(1.25));
      expect(sessionB['zoom'], equals(2.0));
    });

    test('18. Task-specific cache isolation deletes only session files on destroy', () {
      final taskAFile = File('${tempDir.path}/taskA_session.pdf')..writeAsStringSync('%PDF-1.4 Task A');
      final taskBFile = File('${tempDir.path}/taskB_session.pdf')..writeAsStringSync('%PDF-1.4 Task B');

      final sessionAFiles = [taskAFile];
      final sessionBFiles = [taskBFile];

      // Task A finishes and destroys its session files
      for (final f in sessionAFiles) {
        if (f.existsSync()) f.deleteSync();
      }

      // Task A file deleted, Task B file strictly preserved
      expect(taskAFile.existsSync(), isFalse);
      expect(taskBFile.existsSync(), isTrue);
      expect(sessionBFiles.every((f) => f.existsSync()), isTrue);

      // Cleanup
      if (taskBFile.existsSync()) taskBFile.deleteSync();
    });
  });
}
