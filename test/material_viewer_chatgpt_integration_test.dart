import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/screens/material_viewer_screen.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/widgets/ai_floating_launcher.dart';
import 'package:mirror_laikipia/services/security_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> securityChannelLog = <MethodCall>[];

  setUp(() async {
    securityChannelLog.clear();
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.mirrordigital.app/security'),
      (MethodCall methodCall) async {
        securityChannelLog.add(methodCall);
        return true;
      },
    );

    const ttsChannel = MethodChannel('flutter_tts');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, (MethodCall methodCall) async {
      return 1;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.mirrordigital.app/security'),
      null,
    );
  });

  testWidgets('AiFloatingLauncher is visible in MaterialViewerScreen and toggles off during Pen mode', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: MaterialViewerScreen(
          title: 'Quantum Physics Notes',
          fileUrl: 'test_doc.pdf',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify AiFloatingLauncher is mounted and visible
    expect(find.byType(AiFloatingLauncher), findsOneWidget);

    // Verify security service enabled secure screen
    expect(securityChannelLog.any((c) => c.method == 'enableSecureScreen'), isTrue);

    // Enter Pen mode via the study toolbar
    await tester.tap(find.text('Pen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // In Pen settings sheet, tap 'Start Drawing'
    await tester.tap(find.text('Start Drawing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // When drawing mode is active, AiFloatingLauncher must be hidden to prevent drawing collisions
    expect(find.byType(AiFloatingLauncher), findsNothing);

    // Tap Done on the drawing toolbar to exit drawing mode
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // AiFloatingLauncher is restored
    expect(find.byType(AiFloatingLauncher), findsOneWidget);
  });

  testWidgets('MaterialViewerScreen displays Document Shield when backgrounded/inactive', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: MaterialViewerScreen(
          title: 'Cell Biology',
          fileUrl: 'test_doc.pdf',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Document Shield Active'), findsNothing);

    // App goes inactive / paused (App switcher or lock screen)
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Document Shield Active'), findsOneWidget);

    // App resumes
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Document Shield Active'), findsNothing);
  });

  testWidgets('Disposing MaterialViewerScreen preserves global application protection', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('Previous Screen')),
      ),
    );

    navKey.currentState!.push(
      MaterialPageRoute(
        builder: (context) => const MaterialViewerScreen(
          title: 'Macroeconomics',
          fileUrl: 'test_doc.pdf',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(securityChannelLog.any((c) => c.method == 'enableSecureScreen'), isTrue);

    // Pop the viewer
    navKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify global security remains enabled and active
    expect(SecurityService().isSecureScreenEnabled, isTrue);
  });

  testWidgets('Dismissing large launcher with X switches to compact toolbar launcher and persists mode', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: MaterialViewerScreen(
          title: 'Chemistry 101',
          fileUrl: 'test_doc.pdf',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Initially, large floating launcher is mounted and visible
    expect(find.byType(AiFloatingLauncher), findsOneWidget);
    expect(find.byType(AiCompactToolbarLauncher), findsNothing);

    // Tap dismiss X button on large launcher
    final dismissBtn = find.byKey(const ValueKey('ai_launcher_dismiss_button'));
    expect(dismissBtn, findsOneWidget);
    await tester.tap(dismissBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Large launcher disappears
    expect(find.byType(AiFloatingLauncher), findsNothing);
    // Compact circular launcher appears in top toolbar
    expect(find.byType(AiCompactToolbarLauncher), findsOneWidget);

    // Mode is persisted in PersistenceService
    expect(PersistenceService().getString(kAiLauncherModeKey), equals('compact'));

    // Tap compact launcher in toolbar to directly restore large launcher
    await tester.tap(find.byKey(const ValueKey('compact_ai_toolbar_launcher')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Large floating launcher is restored directly without any bottom sheet!
    expect(find.byType(AiFloatingLauncher), findsOneWidget);
    expect(find.byType(AiCompactToolbarLauncher), findsNothing);
    expect(PersistenceService().getString(kAiLauncherModeKey), equals('large'));
  });

  testWidgets('MaterialViewerScreen boots in compact launcher mode if previously persisted', (WidgetTester tester) async {
    await PersistenceService().setString(kAiLauncherModeKey, 'compact');

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: MaterialViewerScreen(
          title: 'World History',
          fileUrl: 'test_doc.pdf',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Large launcher is NOT rendered
    expect(find.byType(AiFloatingLauncher), findsNothing);
    // Compact launcher is rendered in toolbar immediately
    expect(find.byType(AiCompactToolbarLauncher), findsOneWidget);
  });

  testWidgets('Bottom study toolbar toggles on intentional tap, stays put on scrolls and inactivity', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: MaterialViewerScreen(
          title: 'Physics Mechanics',
          fileUrl: 'test_doc.pdf',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 1. Initially, toolbar is visible
    final toolbarFinder = find.byKey(const ValueKey('study_toolbar_slide_transition'));
    expect(toolbarFinder, findsOneWidget);
    final slideTransition = tester.widget<SlideTransition>(toolbarFinder);
    expect(slideTransition.position.value, equals(Offset.zero));

    // 2. Inactivity (3 seconds) does NOT auto-hide the toolbar
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<SlideTransition>(toolbarFinder).position.value, equals(Offset.zero));

    // 3. Scrolling / drag gesture does NOT toggle the toolbar
    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<SlideTransition>(toolbarFinder).position.value, equals(Offset.zero));

    // 4. Intentional document tap slides the toolbar down to hidden
    await tester.tapAt(const Offset(200, 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final slidDownTransition = tester.widget<SlideTransition>(toolbarFinder);
    expect(slidDownTransition.position.value.dy, greaterThan(1.0));

    // 5. Drag while hidden does NOT reveal the toolbar
    final gesture2 = await tester.startGesture(const Offset(200, 400));
    await gesture2.moveBy(const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture2.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<SlideTransition>(toolbarFinder).position.value.dy, greaterThan(1.0));

    // 6. Another intentional document tap smoothly restores the toolbar to visible
    await tester.tapAt(const Offset(200, 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final restoredTransition = tester.widget<SlideTransition>(toolbarFinder);
    expect(restoredTransition.position.value, equals(Offset.zero));
  });
}
