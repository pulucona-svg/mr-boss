import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/models/ai_provider.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/widgets/ai_floating_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
  });

  testWidgets('1. The launcher actually renders in the widget hierarchy with dismiss button', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: AiFloatingLauncher(
                  onSelectProvider: (_) {},
                  onDismiss: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AiFloatingLauncher), findsOneWidget);
    expect(find.byType(SvgPicture), findsWidgets);
    expect(find.byKey(const ValueKey('ai_launcher_dismiss_button')), findsOneWidget);
  });

  testWidgets('2. The launcher is visible at its safe default position (within container bounds)', (WidgetTester tester) async {
    const containerWidth = 400.0;
    const containerHeight = 600.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: containerWidth,
              height: containerHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AiFloatingLauncher(
                      onSelectProvider: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final buttonFinder = find.byKey(const ValueKey('ai_floating_button'));
    final buttonTopLeft = tester.getTopLeft(buttonFinder);
    final buttonBottomRight = tester.getBottomRight(buttonFinder);

    expect(buttonTopLeft.dx, greaterThanOrEqualTo(0.0));
    expect(buttonTopLeft.dy, greaterThanOrEqualTo(0.0));
    expect(buttonBottomRight.dx, lessThanOrEqualTo(400.0));
    expect(buttonBottomRight.dy, lessThanOrEqualTo(600.0));
  });

  testWidgets('3. The launcher remains visible after screen rebuilds', (WidgetTester tester) async {
    final notifier = ValueNotifier<int>(0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: notifier,
            builder: (context, value, child) {
              return Stack(
                children: [
                  Center(child: Text('Rebuild count: $value')),
                  Positioned.fill(
                    child: AiFloatingLauncher(
                      onSelectProvider: (_) {},
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AiFloatingLauncher), findsOneWidget);
    expect(find.text('Rebuild count: 0'), findsOneWidget);

    notifier.value = 1;
    await tester.pump();
    expect(find.byType(AiFloatingLauncher), findsOneWidget);
    expect(find.text('Rebuild count: 1'), findsOneWidget);
  });

  testWidgets('4. Dragging changes launcher position, persists it, and does NOT accidentally open selector', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 800,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AiFloatingLauncher(
                    onSelectProvider: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final buttonFinder = find.byKey(const ValueKey('ai_floating_button'));
    final initialPos = tester.getTopLeft(buttonFinder);

    // Drag up and left by 60dp
    await tester.drag(buttonFinder, const Offset(-60, -80));
    await tester.pump();

    // Verify selector was NOT accidentally opened by drag
    expect(find.text('Choose AI'), findsNothing);

    // Verify coordinates moved
    final newPos = tester.getTopLeft(buttonFinder);
    expect(newPos.dx, lessThan(initialPos.dx));
    expect(newPos.dy, lessThan(initialPos.dy));

    final savedX = PersistenceService().getDouble('ai_launcher_pos_x');
    final savedY = PersistenceService().getDouble('ai_launcher_pos_y');
    expect(savedX, isNotNull);
    expect(savedY, isNotNull);
  });

  testWidgets('5. Tap immediately after dragging works reliably to open selector', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 800,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AiFloatingLauncher(
                    onSelectProvider: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final buttonFinder = find.byKey(const ValueKey('ai_floating_button'));

    // First, perform a drag
    await tester.drag(buttonFinder, const Offset(-40, -50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Choose AI'), findsNothing);

    // Next, tap immediately on the button
    await tester.tap(buttonFinder);
    await tester.pump();

    // Selector opens!
    expect(find.text('Choose AI'), findsOneWidget);
  });

  testWidgets('6. Recover safely from invalid or corrupt saved coordinates', (WidgetTester tester) async {
    await PersistenceService().setDouble('ai_launcher_pos_x', 99999.0);
    await PersistenceService().setDouble('ai_launcher_pos_y', 99999.0);

    const containerWidth = 400.0;
    const containerHeight = 600.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: containerWidth,
            height: containerHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AiFloatingLauncher(
                    onSelectProvider: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final recoveredX = PersistenceService().getDouble('ai_launcher_pos_x');
    final recoveredY = PersistenceService().getDouble('ai_launcher_pos_y');
    expect(recoveredX, lessThan(containerWidth));
    expect(recoveredY, lessThan(containerHeight));
  });

  testWidgets('7. Dismiss X button calls onDismiss callback', (WidgetTester tester) async {
    bool dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 800,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AiFloatingLauncher(
                    onSelectProvider: (_) {},
                    onDismiss: () => dismissed = true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final dismissBtn = find.byKey(const ValueKey('ai_launcher_dismiss_button'));
    expect(dismissBtn, findsOneWidget);

    await tester.tap(dismissBtn);
    await tester.pump();

    expect(dismissed, isTrue);
  });

  testWidgets('8. Expandable selector lists all 8 providers in exact order with strikethrough rules', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 800,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AiFloatingLauncher(
                    initialExpanded: true,
                    onSelectProvider: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Choose AI'), findsOneWidget);

    // Verify all 8 providers exist
    final providers = AiProviderConfig.allProviders;
    expect(providers.length, equals(8));
    expect(providers[0].displayName, equals('ChatGPT'));
    expect(providers[1].displayName, equals('Claude'));
    expect(providers[2].displayName, equals('Gemini'));
    expect(providers[3].displayName, equals('Grok'));
    expect(providers[4].displayName, equals('DeepSeek'));
    expect(providers[5].displayName, equals('DuckDuckGo AI'));
    expect(providers[6].displayName, equals('Perplexity'));
    expect(providers[7].displayName, equals('Copilot'));

    // Verify strikethrough rules:
    // ChatGPT, Gemini, Perplexity AI: NO strikethrough
    // Claude, Grok, DeepSeek, DuckDuckGo AI, Copilot: WITH strikethrough
    for (final p in providers) {
      final textFinder = find.text(p.displayName);
      expect(textFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(textFinder);
      if (p.showStrikethrough) {
        expect(textWidget.style?.decoration, equals(TextDecoration.lineThrough),
            reason: '${p.displayName} must have horizontal strikethrough');
      } else {
        expect(textWidget.style?.decoration, isNull,
            reason: '${p.displayName} must NOT have strikethrough');
      }
    }
  });

  testWidgets('9. Selecting a provider invokes onSelectProvider callback', (WidgetTester tester) async {
    AiProviderConfig? chosen;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 800,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AiFloatingLauncher(
                    initialExpanded: true,
                    onSelectProvider: (p) => chosen = p,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Tap ChatGPT (first provider at the top of the menu)
    await tester.tap(find.text('ChatGPT'));
    await tester.pump();

    expect(chosen, isNotNull);
    expect(chosen!.provider, equals(AiProvider.chatGpt));
    expect(chosen!.displayName, equals('ChatGPT'));

    // Selector collapsed
    expect(find.text('Choose AI'), findsNothing);
  });

  testWidgets('10. AiCompactToolbarLauncher directly invokes onRestoreLargeLauncher on tap without opening sheet', (WidgetTester tester) async {
    bool restored = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              AiCompactToolbarLauncher(
                onRestoreLargeLauncher: () => restored = true,
              ),
            ],
          ),
          body: const Center(child: Text('Document body')),
        ),
      ),
    );
    await tester.pump();

    final compactBtn = find.byKey(const ValueKey('compact_ai_toolbar_launcher'));
    expect(compactBtn, findsOneWidget);

    // Tap compact launcher
    await tester.tap(compactBtn);
    await tester.pump(const Duration(milliseconds: 300));

    expect(restored, isTrue);
    expect(find.text('Choose AI'), findsNothing);
  });

  testWidgets('11. Reduced motion preference renders static label without animation', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            size: Size(500, 800),
          ),
          child: Scaffold(
            body: SizedBox(
              width: 500,
              height: 800,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AiFloatingLauncher(
                      onSelectProvider: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Ask ChatGPT'), findsOneWidget);
  });

  testWidgets('12. AiCompactToolbarLauncher performs smooth light-bulb fading loop', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              AiCompactToolbarLauncher(
                onRestoreLargeLauncher: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final opacityFinder = find.descendant(
      of: find.byKey(const ValueKey('compact_ai_toolbar_launcher')),
      matching: find.byType(Opacity),
    );
    expect(opacityFinder, findsOneWidget);
    final initialOpacity = tester.widget<Opacity>(opacityFinder).opacity;
    expect(initialOpacity, equals(1.0));

    // Advance 1.5s into the fade-out phase
    await tester.pump(const Duration(milliseconds: 1500));
    final fadingOpacity = tester.widget<Opacity>(opacityFinder).opacity;
    expect(fadingOpacity, lessThan(1.0));
  });

  testWidgets('13. Exactly one state-aware X button handles menu closing and launcher dismissal', (WidgetTester tester) async {
    bool dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 800,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AiFloatingLauncher(
                    onSelectProvider: (_) {},
                    onDismiss: () => dismissed = true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Exactly one dismiss button present
    expect(find.byKey(const ValueKey('ai_launcher_dismiss_button')), findsOneWidget);

    // Tap floating button to open menu
    await tester.tap(find.byKey(const ValueKey('ai_floating_button')));
    await tester.pump();
    expect(find.text('Choose AI'), findsOneWidget);

    // Exactly one X button still present (no duplicates)
    expect(find.byKey(const ValueKey('ai_launcher_dismiss_button')), findsOneWidget);

    // Tapping X in State B closes the menu only (does NOT dismiss launcher)
    await tester.tap(find.byKey(const ValueKey('ai_launcher_dismiss_button')));
    await tester.pump();

    expect(find.text('Choose AI'), findsNothing);
    expect(dismissed, isFalse);
    expect(find.byType(AiFloatingLauncher), findsOneWidget);

    // Tapping X in State A dismisses the launcher
    await tester.tap(find.byKey(const ValueKey('ai_launcher_dismiss_button')));
    await tester.pump();

    expect(dismissed, isTrue);
  });
}
