import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/main.dart';
import 'package:mirror_laikipia/providers/providers.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';

class MockUserProfileNotifier extends UserProfileNotifier {
  MockUserProfileNotifier() {
    state = UserProfile(
      uid: 'nav_user',
      username: 'Nav User',
      institution: 'Laikipia University',
      universityLocation: 'Main Campus',
      program: 'Computer Science',
      programCode: 'COMP',
      year: 'Year 3',
      semester: 'Semester 1',
      phone: '+254712345678',
      email: 'nav@laikipia.ac.ke',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
  });

  testWidgets('Back press from secondary tab returns to Home first without exiting', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [
        userProfileProvider.overrideWith((ref) => MockUserProfileNotifier()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: MainNavigation(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Initially on Home (index 0)
    expect(container.read(uiStateProvider).mainNavigationIndex, equals(0));

    // Switch to Explore (index 2) via BottomNavigationBar
    await tester.tap(find.text('Explore'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(uiStateProvider).mainNavigationIndex, equals(2));

    // Press system back button
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Must return to Home (index 0) first
    expect(container.read(uiStateProvider).mainNavigationIndex, equals(0));

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('Double back to exit on Home requires two presses within 3 seconds', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    bool systemNavigatorPopCalled = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'SystemNavigator.pop') {
          systemNavigatorPopCalled = true;
        }
        return null;
      },
    );

    final container = ProviderContainer(
      overrides: [
        userProfileProvider.overrideWith((ref) => MockUserProfileNotifier()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: MainNavigation(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Initially on Home (index 0)
    expect(container.read(uiStateProvider).mainNavigationIndex, equals(0));

    // 1st back press on Home: Shows exit notification, does not exit
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(systemNavigatorPopCalled, isFalse);
    expect(find.text('Tap back again to exit'), findsOneWidget);

    // 2nd back press within 3 seconds: Exits application
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(systemNavigatorPopCalled, isTrue);

    // Let notification/timer drain cleanly
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('Exit confirmation window expires after 3 seconds without second press', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    bool systemNavigatorPopCalled = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'SystemNavigator.pop') {
          systemNavigatorPopCalled = true;
        }
        return null;
      },
    );

    final container = ProviderContainer(
      overrides: [
        userProfileProvider.overrideWith((ref) => MockUserProfileNotifier()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: MainNavigation(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 1st back press
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(systemNavigatorPopCalled, isFalse);

    // Wait 4 seconds (confirmation window expires and notification completes)
    await tester.pump(const Duration(seconds: 4));

    // Next press should NOT exit; it starts a new confirmation window
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(systemNavigatorPopCalled, isFalse);
    expect(find.text('Tap back again to exit'), findsOneWidget);

    // Let notification/timer drain cleanly
    await tester.pump(const Duration(seconds: 4));
  });
}
