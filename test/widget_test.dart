import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirror_laikipia/main.dart';
import 'package:mirror_laikipia/screens/material_viewer_screen.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/services/progress_service.dart';

void main() {
  setUp(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
  });

  testWidgets('App shows dashboard content', (WidgetTester tester) async {
    // Set a realistic screen size to prevent layout overflow on smaller default test windows
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await PersistenceService().saveSession('mock_user');
    await PersistenceService().setJson('user_profile', {
      'uid': 'mock_user',
      'username': 'mock_username',
      'onboardingComplete': true,
    });
    await tester.pumpWidget(const ProviderScope(child: MirrorApp(isLoggedIn: true)));
    await tester.pump();
    // Advance virtual clock past the 1.5s simulated loading duration to trigger setState
    await tester.pump(const Duration(seconds: 2));
    // Pump another frame to apply the rebuild and render the dashboard content
    await tester.pump();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Find your academic edge.'), findsOneWidget);
  });

  testWidgets('MaterialViewerScreen displays AppBar metadata correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MaterialViewerScreen(
          title: 'Chemistry Lesson 1',
          fileUrl: '',
          unitName: 'Organic Chemistry I',
          unitCode: 'CHEM 122',
          category: 'Exam',
          publicationYear: '2025',
        ),
      ),
    );

    // Pump to process microtasks
    await tester.pump();

    // Verify Title Line is: "Organic Chemistry I (CHEM 122)"
    expect(find.text('Organic Chemistry I (CHEM 122)'), findsOneWidget);

    // Verify Subtitle Line is: "Exam • 2025"
    expect(find.text('Exam • 2025'), findsOneWidget);
  });

  testWidgets('MaterialViewerScreen hides year when publicationYear is missing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MaterialViewerScreen(
          title: 'Chemistry Lesson 1',
          fileUrl: '',
          unitName: 'Organic Chemistry I',
          unitCode: 'CHEM 122',
          category: 'Exam',
          publicationYear: '',
        ),
      ),
    );

    await tester.pump();

    // Verify Title Line is: "Organic Chemistry I (CHEM 122)"
    expect(find.text('Organic Chemistry I (CHEM 122)'), findsOneWidget);

    // Verify Subtitle Line is only: "Exam"
    expect(find.text('Exam'), findsOneWidget);
  });

  test('ProgressService updates progress backwards', () {
    final service = ProgressService();
    service.updateProgress('test_material', 0.8);
    expect(service.getProgress('test_material'), 0.8);

    // Save progress backwards (earlier position/page)
    service.updateProgress('test_material', 0.3);
    expect(service.getProgress('test_material'), 0.3);
  });

  testWidgets('MaterialViewerScreen title has correct blue color', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MaterialViewerScreen(
          title: 'Chemistry Lesson 1',
          fileUrl: '',
          unitName: 'Organic Chemistry I',
          unitCode: 'CHEM 122',
          category: 'Exam',
          publicationYear: '2025',
        ),
      ),
    );

    await tester.pump();

    final Text titleText = tester.widget(find.text('Organic Chemistry I (CHEM 122)'));
    expect(titleText.style?.color, const Color(0xFF20C8FF));
  });

  testWidgets('MaterialViewerScreen search mode enters and exits correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MaterialViewerScreen(
          title: 'Chemistry Lesson 1',
          fileUrl: 'test_doc.pdf',
          unitName: 'Organic Chemistry I',
          unitCode: 'CHEM 122',
          category: 'Exam',
          publicationYear: '2025',
        ),
      ),
    );

    await tester.pump();

    // Verify search icon is present
    expect(find.byIcon(Icons.search), findsOneWidget);

    // Tap search icon to enter search mode
    await tester.tap(find.byIcon(Icons.search));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify normal title is replaced with the search text field
    expect(find.text('Organic Chemistry I (CHEM 122)'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    // Tap close icon to exit search mode
    await tester.tap(find.byIcon(Icons.close));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify search mode is closed and title is restored
    expect(find.text('Organic Chemistry I (CHEM 122)'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('MaterialViewerScreen Pen and Highlighter settings sheets work correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MaterialViewerScreen(
          title: 'Chemistry Lesson 1',
          fileUrl: 'test_doc.pdf',
          unitName: 'Organic Chemistry I',
          unitCode: 'CHEM 122',
          category: 'Exam',
          publicationYear: '2025',
        ),
      ),
    );

    // Let _prepareFile run and catch exception, setting _isLoading to false
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify More Tools vert icon is present and opens bottom sheet
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('More Tools'), findsOneWidget);
    
    // Dismiss bottom sheet
    await tester.tap(find.text('Material Details'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify Pen Settings opens
    expect(find.text('Pen'), findsOneWidget);
    await tester.tap(find.text('Pen'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Pen Settings'), findsOneWidget);
    expect(find.text('Start Drawing'), findsOneWidget);
    
    // Tap Start Drawing to enter pen mode
    await tester.tap(find.text('Start Drawing'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Pen Mode'), findsOneWidget);
    
    // Tap Done to exit pen mode
    await tester.tap(find.text('Done'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Pen Mode'), findsNothing);

    // Verify Highlighter Settings opens
    expect(find.text('Highlighter'), findsOneWidget);
    await tester.tap(find.text('Highlighter'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Highlighter Settings'), findsOneWidget);
    expect(find.text('Start Highlighting'), findsOneWidget);
    
    // Tap Start Highlighting to enter highlighter mode
    await tester.tap(find.text('Start Highlighting'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Highlighter Mode'), findsOneWidget);
    
    // Tap Done to exit highlighter mode
    await tester.tap(find.text('Done'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Highlighter Mode'), findsNothing);
  });
}
