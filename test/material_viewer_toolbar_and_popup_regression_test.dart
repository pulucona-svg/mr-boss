import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/screens/material_viewer_screen.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/services/progress_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
    await PersistenceService().clearAll();
    ProgressService().clear();
  });

  group('Material Viewer: Toolbar Layout & Overflow Regression Tests', () {
    testWidgets('1. Toolbar layout does not overflow with very long document title', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const longTitle = 'Supercalifragilisticexpialidocious Anatomy & Advanced Histopathology Comprehensive Clinical Coursework Handbook (Fall Semester 2026 Edition)';

      await tester.pumpWidget(
        const MaterialApp(
          home: MaterialViewerScreen(
            title: longTitle,
            fileUrl: 'test_doc.pdf',
            unitName: 'Anatomy and Histopathology Department of Medicine',
            unitCode: 'MED 8094',
            category: 'Coursework Note',
            publicationYear: '2026',
          ),
        ),
      );

      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // No RenderFlex overflow should occur.
      expect(tester.takeException(), isNull);

      // Verify action buttons remain accessible
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf_search_button')), findsOneWidget);
    });

    testWidgets('2. Toolbar layout does not overflow on narrow 320px screen width', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const longTitle = 'Organic Chemistry I Midterm Exam with Solutions and Detailed Mechanisms';

      await tester.pumpWidget(
        const MaterialApp(
          home: MaterialViewerScreen(
            title: longTitle,
            fileUrl: 'test_doc.pdf',
            unitName: 'Organic Chemistry',
            unitCode: 'CHEM 122',
            category: 'Past Paper',
            publicationYear: '2025',
          ),
        ),
      );

      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Assert no layout overflow occurred on 320px screen width
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf_search_button')), findsOneWidget);
    });
  });

  group('Material Viewer: Reading-Resume Popup Regression Tests', () {
    testWidgets('3. Resume popup appears directly below top toolbar when saved page > 1', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const docTitle = 'Biochemistry Fundamentals';
      const docIdentifier = 'doc_bio_30';
      const savedPage = 30;

      // Seed progress at page 30
      ProgressService().updateProgress(
        docIdentifier,
        0.30,
        pageNumber: savedPage,
        totalPages: 100,
        title: docTitle,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: MaterialViewerScreen(
            id: docIdentifier,
            title: docTitle,
            fileUrl: 'test_doc.pdf',
            unitName: 'Biochemistry',
            unitCode: 'BCH 201',
          ),
        ),
      );

      // Pump frames to initialize and trigger popup animation
      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Verify resume popup is displayed with correct text and action button
      expect(find.text('Continue reading from page 30?'), findsOneWidget);
      expect(find.byKey(const ValueKey('resume_reading_button')), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);

      // Verify popup is positioned directly BELOW the top toolbar
      final popupFinder = find.byKey(const ValueKey('resume_reading_button'));
      final popupPosition = tester.getTopLeft(popupFinder);

      // Top toolbar in Scaffold with default AppBar is 56.0 pixels high.
      // The popup is in the body Stack with top: 8, so popup top must be >= 56.0 and < 150.0.
      expect(popupPosition.dy, greaterThanOrEqualTo(56.0));
      expect(popupPosition.dy, lessThan(150.0));
    });

    testWidgets('4. Resume popup does NOT appear when saved page is 1', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const docTitle = 'Cell Biology';
      const docIdentifier = 'doc_cell_1';

      // Seed progress at page 1
      ProgressService().updateProgress(
        docIdentifier,
        0.01,
        pageNumber: 1,
        totalPages: 100,
        title: docTitle,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: MaterialViewerScreen(
            id: docIdentifier,
            title: docTitle,
            fileUrl: 'test_doc.pdf',
            unitName: 'Biology',
            unitCode: 'BIO 101',
          ),
        ),
      );

      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Verify resume popup does not appear
      expect(find.textContaining('Continue reading'), findsNothing);
      expect(find.byKey(const ValueKey('resume_reading_button')), findsNothing);
    });

    testWidgets('5. Resume popup does NOT appear when no previous progress exists', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const docTitle = 'Introductory Physics';
      const docIdentifier = 'doc_phys_new';

      await tester.pumpWidget(
        const MaterialApp(
          home: MaterialViewerScreen(
            id: docIdentifier,
            title: docTitle,
            fileUrl: 'test_doc.pdf',
            unitName: 'Physics',
            unitCode: 'PHY 101',
          ),
        ),
      );

      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.textContaining('Continue reading'), findsNothing);
      expect(find.byKey(const ValueKey('resume_reading_button')), findsNothing);
    });

    testWidgets('6. Tapping Resume dismisses popup and preserves saved progress', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const docTitle = 'Microbiology Notes';
      const docIdentifier = 'doc_micro_45';
      const savedPage = 45;

      ProgressService().updateProgress(
        docIdentifier,
        0.45,
        pageNumber: savedPage,
        totalPages: 100,
        title: docTitle,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: MaterialViewerScreen(
            id: docIdentifier,
            title: docTitle,
            fileUrl: 'test_doc.pdf',
            unitName: 'Microbiology',
            unitCode: 'MIC 301',
          ),
        ),
      );

      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byKey(const ValueKey('resume_reading_button')), findsOneWidget);

      // Tap Resume
      await tester.tap(find.byKey(const ValueKey('resume_reading_button')));

      // Advance frames to complete dismissal
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Resume popup should be dismissed
      expect(find.byKey(const ValueKey('resume_reading_button')), findsNothing);

      // Saved progress must still be page 45
      expect(ProgressService().getSavedPage(docIdentifier), equals(45));
    });

    testWidgets('7. Ignoring popup for 3 seconds auto-dismisses it and preserves saved position', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const docTitle = 'Pathology Essentials';
      const docIdentifier = 'doc_path_25';
      const savedPage = 25;

      ProgressService().updateProgress(
        docIdentifier,
        0.25,
        pageNumber: savedPage,
        totalPages: 100,
        title: docTitle,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: MaterialViewerScreen(
            id: docIdentifier,
            title: docTitle,
            fileUrl: 'test_doc.pdf',
            unitName: 'Pathology',
            unitCode: 'PAT 401',
          ),
        ),
      );

      // Verify popup appears initially
      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Continue reading from page 25?'), findsOneWidget);

      // Wait 3.5 seconds without tapping Resume
      await tester.pump(const Duration(milliseconds: 3500));
      // Pump extra frames for reverse animation
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Popup must have dismissed automatically
      expect(find.byKey(const ValueKey('resume_reading_button')), findsNothing);

      // CRITICAL PRESERVATION RULE: Saved progress must NOT be overwritten by page 1
      expect(ProgressService().getSavedPage(docIdentifier), equals(25));
    });

    testWidgets('8. Closing and reopening after ignoring popup still offers original saved position', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const docTitle = 'Pharmacology Guide';
      const docIdentifier = 'doc_pharm_50';
      const savedPage = 50;

      ProgressService().updateProgress(
        docIdentifier,
        0.50,
        pageNumber: savedPage,
        totalPages: 100,
        title: docTitle,
      );

      // 1. First open: popup appears and user ignores it (auto-dismisses after 3s)
      await tester.pumpWidget(
        const MaterialApp(
          home: MaterialViewerScreen(
            id: docIdentifier,
            title: docTitle,
            fileUrl: 'test_doc.pdf',
            unitName: 'Pharmacology',
            unitCode: 'PHA 301',
          ),
        ),
      );

      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Continue reading from page 50?'), findsOneWidget);

      // Let timer expire
      await tester.pump(const Duration(milliseconds: 3500));
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const ValueKey('resume_reading_button')), findsNothing);

      // 2. Close document viewer by popping or replacing with a placeholder
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Home Screen')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Saved progress must still be page 50
      expect(ProgressService().getSavedPage(docIdentifier), equals(50));

      // 3. Reopen the document: resume popup must appear again offering page 50!
      await tester.pumpWidget(
        const MaterialApp(
          home: MaterialViewerScreen(
            id: docIdentifier,
            title: docTitle,
            fileUrl: 'test_doc.pdf',
            unitName: 'Pharmacology',
            unitCode: 'PHA 301',
          ),
        ),
      );

      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('Continue reading from page 50?'), findsOneWidget);
      expect(find.byKey(const ValueKey('resume_reading_button')), findsOneWidget);
    });

    testWidgets('9. Manual close button on resume popup dismisses it immediately and preserves progress', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const docTitle = 'Genetics Handbook';
      const docIdentifier = 'doc_gen_18';
      const savedPage = 18;

      ProgressService().updateProgress(
        docIdentifier,
        0.18,
        pageNumber: savedPage,
        totalPages: 100,
        title: docTitle,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: MaterialViewerScreen(
            id: docIdentifier,
            title: docTitle,
            fileUrl: 'test_doc.pdf',
            unitName: 'Genetics',
            unitCode: 'GEN 202',
          ),
        ),
      );

      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byKey(const ValueKey('dismiss_resume_popup_button')), findsOneWidget);

      // Tap the dismiss button
      await tester.tap(find.byKey(const ValueKey('dismiss_resume_popup_button')));

      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Popup dismissed
      expect(find.byKey(const ValueKey('resume_reading_button')), findsNothing);

      // Progress remains 18
      expect(ProgressService().getSavedPage(docIdentifier), equals(18));
    });
  });
}
