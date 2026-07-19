import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirror_laikipia/main.dart';
import 'package:mirror_laikipia/screens/material_viewer_screen.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/services/progress_service.dart';
import 'package:mirror_laikipia/widgets/resource_details_modal.dart';
import 'package:mirror_laikipia/providers/upload_provider.dart';
import 'package:mirror_laikipia/models/material_model.dart';
import 'dart:io';

void main() {
  setUp(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();

    const channel = MethodChannel('flutter_tts');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'getVoices':
          return [
            {'name': 'en-us-x-sfg-local', 'locale': 'en-US'},
            {'name': 'en-us-x-tpf-local', 'locale': 'en-US'},
            {'name': 'en-gb-x-rjs-local', 'locale': 'en-GB'},
            {'name': 'fr-fr-x-xyz-network', 'locale': 'fr-FR'},
          ];
        case 'setSpeechRate':
        case 'setPitch':
        case 'setVoice':
        case 'speak':
        case 'pause':
        case 'stop':
          return 1;
        default:
          return null;
      }
    });
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

  testWidgets('MaterialViewerScreen Notes system works correctly', (WidgetTester tester) async {
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

    // Let any async setup run
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify Notes button is present in bottom bar and tap it
    expect(find.text('Notes'), findsOneWidget);
    await tester.tap(find.text('Notes'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify bottom sheet title is Notes and "+ New Note" button is present
    expect(find.text('+ New Note'), findsOneWidget);

    // Tap "+ New Note" to open editor
    await tester.tap(find.text('+ New Note'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify editor has Title and Body textfields
    final titleFinder = find.byWidgetPredicate((widget) =>
        widget is TextField && widget.decoration?.hintText == 'Title (Optional)');
    final bodyFinder = find.byWidgetPredicate((widget) =>
        widget is TextField && widget.decoration?.hintText == 'Write your note here...');
    expect(titleFinder, findsOneWidget);
    expect(bodyFinder, findsOneWidget);

    // Input title and body
    await tester.enterText(titleFinder, 'Test Title');
    await tester.enterText(bodyFinder, 'Test Note Body Content');
    await tester.pump();

    // Tap Save
    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.text('Save'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify note card is shown in the bottom sheet
    expect(find.text('Test Title'), findsOneWidget);
    expect(find.text('Test Note Body Content'), findsOneWidget);

    // Test Search: search for non-matching text
    final searchFinder = find.byWidgetPredicate((widget) =>
        widget is TextField && widget.decoration?.hintText == 'Search notes...');
    await tester.enterText(searchFinder, 'NoMatchText');
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Test Title'), findsNothing);
    expect(find.text('No matching notes found'), findsOneWidget);

    // Clear search
    await tester.enterText(searchFinder, '');
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Test Title'), findsOneWidget);

    // Tap edit button to edit the note
    await tester.tap(find.byIcon(Icons.edit_outlined).last);
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    
    // Change title and save
    await tester.enterText(titleFinder, 'Edited Title');
    await tester.tap(find.text('Save'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Edited Title'), findsOneWidget);

    // Tap delete button
    await tester.tap(find.byIcon(Icons.delete_outline).last);
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Verify confirmation dialog shows
    expect(find.text('Delete Note'), findsOneWidget);
    // Tap Delete in confirmation dialog
    await tester.tap(find.text('Delete'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify note is deleted
    expect(find.text('Edited Title'), findsNothing);
    expect(find.text('No notes created yet'), findsOneWidget);
  });

  testWidgets('MaterialViewerScreen Read Aloud bottom sheet works correctly', (WidgetTester tester) async {
    // Set a realistic screen size to prevent layout overflow on smaller default test windows
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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

    // Let any async setup run
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify Read Aloud button is present in bottom bar and tap it
    expect(find.text('Read Aloud'), findsOneWidget);
    await tester.tap(find.text('Read Aloud'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify bottom sheet title is "Read Aloud"
    expect(find.text('Read Aloud').last, findsOneWidget);

    // Verify presence of playback controls (Play, Skip next, Skip previous, Stop)
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);

    // Verify presence of Speed and Pitch labels
    expect(find.text('Speed'), findsOneWidget);
    expect(find.text('Pitch'), findsOneWidget);

    // Verify speed/pitch sliders are present
    expect(find.byType(Slider), findsNWidgets(2));

    // Tap play button and verify toggle to pause
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    // Tap pause button
    await tester.tap(find.byIcon(Icons.pause_rounded));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    // Verify voice selector is present and shows Default Voice (which gets resolved to English (US) Voice 1)
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('English (US) Voice 1'), findsOneWidget);

    // Tap Voice selector to open voice sheet
    await tester.tap(find.text('Voice'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Verify "Select Voice" title is visible
    expect(find.text('Select Voice'), findsOneWidget);

    // Verify grouped headers and mock voice display names are present
    expect(find.text('English Voices (Recommended)'), findsOneWidget);
    expect(find.text('French'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'English (US) Voice 1'), findsOneWidget);
    expect(find.text('English (US) Voice 2'), findsOneWidget);
    expect(find.text('English (UK)'), findsOneWidget);
    final frenchVoiceFinder = find.ancestor(
      of: find.byWidgetPredicate((w) => w is Text && w.data == 'French (France)' && w.style?.fontSize == 15),
      matching: find.byType(ListTile),
    );
    expect(frenchVoiceFinder, findsOneWidget);

    // Test search functionality in voice selection sheet
    // Search for 'French'
    await tester.enterText(find.byType(TextField).last, 'French');
    await tester.pumpAndSettle();
    
    // Only French should be visible, English should be filtered out
    expect(frenchVoiceFinder, findsOneWidget);
    expect(find.widgetWithText(ListTile, 'English (US) Voice 1'), findsNothing);

    // Search for non-existent voice
    await tester.enterText(find.byType(TextField).last, 'NonExistentVoice');
    await tester.pumpAndSettle();
    expect(find.text('No matching voices found.'), findsOneWidget);

    // Clear search
    await tester.tap(find.byIcon(Icons.clear_rounded));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'English (US) Voice 1'), findsOneWidget);

    // Select "French (France)"
    await tester.tap(frenchVoiceFinder);
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify selector sheet closes and voice row updates
    expect(find.text('Select Voice'), findsNothing);
    expect(find.text('French (France)'), findsOneWidget);
  });

  testWidgets('ResourceDetailsModal hides uploader details when isAnonymous is true', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ResourceDetailsModal(
              title: 'Chemistry Lesson 1',
              type: 'Notes',
              thumbnailUrl: 'https://images.unsplash.com/photo-1532094349884-543bc11b234d?w=400&q=80',
              unitName: 'Organic Chemistry I',
              unitCode: 'CHEM 122',
              materialFormat: 'PDF',
              uploadYear: '2026',
              publicationYear: '2025',
              yearOfStudy: '1st Year',
              semester: 'Semester 1',
              lecturers: ['Dr. John Doe'],
              uploadedBy: 'Jane Doe',
              uploaderRole: 'Student',
              uploaderId: 'other_user',
              uploaderProfilePic: 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=100&q=80',
              fileUrl: 'test_doc.pdf',
              isAnonymous: true,
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));

    // The name "Jane Doe" and role "Student" should NOT be visible.
    // Instead, "Anonymous" should be displayed.
    expect(find.textContaining('Jane Doe'), findsNothing);
    expect(find.textContaining('Student'), findsNothing);
    expect(find.text('Anonymous'), findsOneWidget);

    // The uploader profile picture should use the local anonymous_mask.png asset
    bool foundAsset = false;
    for (final element in tester.allElements) {
      if (element.widget is Image) {
        final img = element.widget as Image;
        if (img.image is AssetImage) {
          final assetImage = img.image as AssetImage;
          if (assetImage.assetName == 'assets/images/anonymous_mask.png') {
            foundAsset = true;
            break;
          }
        }
      }
    }
    expect(foundAsset, isTrue);
  });

  test('UploadState validation works for PDFs and multiple images', () {
    final statePdf = UploadState(
      material: UploadMaterialModel(
        unitName: 'Intro to Programming',
        unitCode: 'COMP 101',
        programs: ['Computer Science'],
        yearOfStudy: '1st Year',
        semester: 'Semester 1',
        yearOfPublication: 2026,
        uploadedBy: 'uploader',
        uploaderId: 'id',
        yearOfUpload: 2026,
        materialType: 'Notes',
        file: File('dummy.pdf'),
        fileFormat: 'PDF',
      ),
    );
    expect(statePdf.isValid, isTrue);

    final stateImages = UploadState(
      material: UploadMaterialModel(
        unitName: 'Intro to Programming',
        unitCode: 'COMP 101',
        programs: ['Computer Science'],
        yearOfStudy: '1st Year',
        semester: 'Semester 1',
        yearOfPublication: 2026,
        uploadedBy: 'uploader',
        uploaderId: 'id',
        yearOfUpload: 2026,
        materialType: 'Notes',
        files: [File('dummy1.png'), File('dummy2.png')],
        fileFormat: 'Images',
      ),
    );
    expect(stateImages.isValid, isTrue);

    final stateMix = statePdf.copyWith(error: 'Some error');
    expect(stateMix.isValid, isFalse);
  });
}
