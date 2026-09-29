import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mirror_laikipia/screens/login_screen.dart';

void main() {
  Widget createLoginScreen() {
  return const ProviderScope(
    child: MaterialApp(
      home: LoginScreen(),
    ),
  );
}

  group('Login Screen Glassmorphism UI Polish Tests', () {
    testWidgets('1. Background image & subtle overlay are rendered', (tester) async {
      await tester.pumpWidget(createLoginScreen());

      // Verify campus photograph
      final bgFinder = find.byWidgetPredicate((widget) {
        if (widget is Image && widget.image is AssetImage) {
          final asset = widget.image as AssetImage;
          return asset.assetName == 'assets/login_bg.jpeg';
        }
        return false;
      });
      expect(bgFinder, findsOneWidget);

      // Verify subtle dark overlay
      final overlayFinder = find.byWidgetPredicate((widget) {
        if (widget is Container && widget.color != null) {
          return widget.color!.toARGB32() == Colors.black.withValues(alpha: 0.28).toARGB32();
        }
        return false;
      });
      expect(overlayFinder, findsOneWidget);
    });

    testWidgets('2. Mirror branding is positioned above the glass panel', (tester) async {
      await tester.pumpWidget(createLoginScreen());

      expect(find.text('MIRROR'), findsOneWidget);
      expect(find.text('LAIKIPIA'), findsOneWidget);
      expect(find.byIcon(Icons.school), findsOneWidget);
      expect(find.text('Learn  ·  Access  ·  Grow'), findsOneWidget);

      // Verify logo asset
      final logoFinder = find.byWidgetPredicate((widget) {
        if (widget is Image && widget.image is AssetImage) {
          final asset = widget.image as AssetImage;
          return asset.assetName == 'assets/splash_logo.png';
        }
        return false;
      });
      expect(logoFinder, findsOneWidget);
    });

    testWidgets('3. Glassmorphism card has BackdropFilter and rounded 28px corners', (tester) async {
      await tester.pumpWidget(createLoginScreen());

      // BackdropFilter must be present
      expect(find.byType(BackdropFilter), findsOneWidget);

      // ClipRRect with radius 28
      final clipFinder = find.byWidgetPredicate((widget) {
        if (widget is ClipRRect) {
          return widget.borderRadius == BorderRadius.circular(28);
        }
        return false;
      });
      expect(clipFinder, findsOneWidget);
    });

    testWidgets('4. Form fields and labels render properly', (tester) async {
      await tester.pumpWidget(createLoginScreen());

      expect(find.text('Username / Email'), findsWidgets);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Remember me'), findsOneWidget);
      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.text('Login'), findsOneWidget);
      expect(find.text('OR'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue with Apple'), findsOneWidget);
      expect(find.byType(FaIcon), findsOneWidget);
    });

    testWidgets('5. Existing RED accent is preserved on Create Account', (tester) async {
      await tester.pumpWidget(createLoginScreen());

      final createAccountFinder = find.text('Create Account');
      expect(createAccountFinder, findsOneWidget);

      final textWidget = tester.widget<Text>(createAccountFinder);
      expect(textWidget.style?.color, const Color(0xFFE31E24));
    });

    testWidgets('6. Copyright text is explicitly preserved as BLUE', (tester) async {
      await tester.pumpWidget(createLoginScreen());

      final copyrightFinder = find.text('Copyright © 2026- MIRROR Softwares');
      expect(copyrightFinder, findsOneWidget);

      final copyrightWidget = tester.widget<Text>(copyrightFinder);
      expect(copyrightWidget.style?.color, const Color(0xFF20C8FF));

      final intlFinder = find.text('International');
      expect(intlFinder, findsOneWidget);

      final intlWidget = tester.widget<Text>(intlFinder);
      expect(intlWidget.style?.color, const Color(0xFF20C8FF));
    });

    testWidgets('7. Responsive test: Small screen (360x640) has ZERO overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createLoginScreen());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('8. Responsive test: Standard screen (390x844) has ZERO overflow', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createLoginScreen());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('9. Password obscure toggle works', (tester) async {
      await tester.pumpWidget(createLoginScreen());

      final toggleFinder = find.byIcon(Icons.visibility_off_outlined);
      expect(toggleFinder, findsOneWidget);

      await tester.tap(toggleFinder);
      await tester.pump();

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });
  });
}
