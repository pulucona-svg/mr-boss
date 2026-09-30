import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

import 'package:mirror_laikipia/constants/legal_constants.dart';
import 'package:mirror_laikipia/screens/terms_and_conditions_screen.dart';
import 'package:mirror_laikipia/screens/privacy_policy_screen.dart';
import 'package:mirror_laikipia/screens/signup_screen.dart';
import 'package:mirror_laikipia/screens/profile_screen.dart';
import 'package:mirror_laikipia/screens/more_options_screen.dart';
import 'package:mirror_laikipia/providers/user_provider.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';

void main() {
  setUp(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
  });

  group('Legal Constants & Platform Name Integrity Tests', () {
    test('1. Platform name is strictly Mirror Digital and not Mirror Laikipia', () {
      expect(LegalConstants.platformName, 'Mirror Digital');
      expect(LegalConstants.contactEmail, 'mirrorlaikipia@gmail.com');
      expect(LegalConstants.termsVersion, '1.0');
      expect(LegalConstants.privacyPolicyVersion, '1.0');

      // Ensure "Mirror Laikipia" does not appear as the platform name in legal documents
      expect(LegalConstants.termsIntro.contains('Mirror Laikipia'), isFalse);
      expect(LegalConstants.privacyPolicyIntro.contains('Mirror Laikipia'), isFalse);
      expect(LegalConstants.termsAcknowledgement.contains('Mirror Laikipia'), isFalse);
      expect(LegalConstants.privacyPolicyAcknowledgement.contains('Mirror Laikipia'), isFalse);

      for (final section in LegalConstants.termsSections) {
        // Checking that the document does not refer to the platform as Mirror Laikipia
        expect(section.content.contains('Mirror Laikipia platform'), isFalse);
      }
      for (final section in LegalConstants.privacyPolicySections) {
        expect(section.content.contains('Mirror Laikipia platform'), isFalse);
      }
    });
  });

  group('UserProfile Legal Acceptance Tracking Tests', () {
    test('2. UserProfile correctly serializes and deserializes acceptance fields', () {
      final now = DateTime.now();
      final profile = UserProfile(
        uid: 'user_123',
        username: 'student',
        institution: 'Test University',
        universityLocation: 'Main Campus',
        program: 'Computer Science',
        programCode: 'CS101',
        year: 'Year 2',
        semester: 'Sem 1',
        phone: '+254700000000',
        email: 'student@example.com',
        termsVersionAccepted: '1.0',
        termsAcceptedAt: now,
        privacyPolicyVersionAccepted: '1.0',
        privacyPolicyAcceptedAt: now,
      );

      final json = profile.toJson();
      expect(json['termsVersionAccepted'], '1.0');
      expect(json['termsAcceptedAt'], now.toIso8601String());
      expect(json['privacyPolicyVersionAccepted'], '1.0');
      expect(json['privacyPolicyAcceptedAt'], now.toIso8601String());

      final restored = UserProfile.fromJson(json);
      expect(restored.termsVersionAccepted, '1.0');
      expect(restored.termsAcceptedAt?.toIso8601String(), now.toIso8601String());
      expect(restored.privacyPolicyVersionAccepted, '1.0');
      expect(restored.privacyPolicyAcceptedAt?.toIso8601String(), now.toIso8601String());
    });

    test('3. UserProfile copyWith preserves and updates acceptance fields', () {
      final profile = UserProfile(
        uid: 'user_456',
        username: 'student2',
        institution: 'Test University',
        universityLocation: 'Main Campus',
        program: 'Engineering',
        programCode: 'ENG01',
        year: 'Year 1',
        semester: 'Sem 1',
        phone: '',
        email: 'test@example.com',
      );

      expect(profile.termsVersionAccepted, isNull);

      final updated = profile.copyWith(
        termsVersionAccepted: '1.0',
        privacyPolicyVersionAccepted: '1.0',
      );

      expect(updated.termsVersionAccepted, '1.0');
      expect(updated.privacyPolicyVersionAccepted, '1.0');
      expect(updated.uid, 'user_456');
    });
  });

  group('Terms & Conditions Screen Tests', () {
    testWidgets('4. TermsAndConditionsScreen renders header, version, sections, and scrolls without overflow on small screen',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });



      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: TermsAndConditionsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify title in AppBar
      expect(find.text('Terms & Conditions'), findsWidgets);
      // Verify platform name badge
      expect(find.text('MIRROR DIGITAL'), findsOneWidget);
      // Verify version
      expect(find.textContaining('Version: 1.0'), findsWidgets);
      // Verify effective date
      expect(find.textContaining('Effective Date: October 1, 2026'), findsWidgets);
      // Verify first section
      expect(find.text('1. ABOUT MIRROR DIGITAL'), findsOneWidget);

      // Verify no exception / overflow
      expect(tester.takeException(), isNull);

      // Scroll to test large document vertical scrolling
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('Privacy Policy Screen Tests', () {
    testWidgets('5. PrivacyPolicyScreen renders header, version, sections, and scrolls without overflow on small screen',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: PrivacyPolicyScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify title in AppBar
      expect(find.text('Privacy Policy'), findsWidgets);
      // Verify platform name badge
      expect(find.text('MIRROR DIGITAL'), findsOneWidget);
      // Verify version
      expect(find.textContaining('Version: 1.0'), findsWidgets);
      // Verify effective date
      expect(find.textContaining('Effective Date: October 1, 2026'), findsWidgets);
      // Verify section
      expect(find.text('1. ABOUT THIS PRIVACY POLICY'), findsOneWidget);

      // Verify no exception / overflow
      expect(tester.takeException(), isNull);

      // Scroll to verify vertical scrolling works
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('Signup Screen Terms & Conditions Link Tests', () {
    testWidgets('6. SignupScreen displays "By continuing you agree to" and blue tappable "Terms and Conditions"',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SignupScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the rich text
      final richTextFinder = find.byWidgetPredicate((widget) {
        if (widget is RichText) {
          final span = widget.text;
          if (span is TextSpan) {
            return span.toPlainText().contains('By continuing you agree to Terms and Conditions');
          }
        }
        return false;
      });

      expect(richTextFinder, findsOneWidget);

      // Verify the blue style on "Terms and Conditions"
      final richTextWidget = tester.widget<RichText>(richTextFinder);
      final rootSpan = richTextWidget.text as TextSpan;
      TextSpan? termsSpan;
      rootSpan.visitChildren((span) {
        if (span is TextSpan && span.text == 'Terms and Conditions') {
          termsSpan = span;
          return false;
        }
        return true;
      });

      expect(termsSpan, isNotNull);
      expect(termsSpan!.text, 'Terms and Conditions');
      expect(termsSpan!.style?.color, const Color(0xFF20C8FF));
      expect(termsSpan!.recognizer, isNotNull);
      expect(termsSpan!.recognizer, isA<TapGestureRecognizer>());
    });

    testWidgets('7. Tapping Terms and Conditions link opens TermsAndConditionsScreen',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SignupScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the rich text span and trigger tap
      final richTextFinder = find.byWidgetPredicate((widget) {
        if (widget is RichText) {
          final span = widget.text;
          if (span is TextSpan) {
            return span.toPlainText().contains('By continuing you agree to Terms and Conditions');
          }
        }
        return false;
      });

      final richTextWidget = tester.widget<RichText>(richTextFinder);
      final rootSpan = richTextWidget.text as TextSpan;
      TextSpan? termsSpan;
      rootSpan.visitChildren((span) {
        if (span is TextSpan && span.text == 'Terms and Conditions') {
          termsSpan = span;
          return false;
        }
        return true;
      });

      expect(termsSpan, isNotNull);
      final recognizer = termsSpan!.recognizer as TapGestureRecognizer;

      recognizer.onTap?.call();
      await tester.pumpAndSettle();

      // Terms screen should now be opened
      expect(find.byType(TermsAndConditionsScreen), findsOneWidget);
      expect(find.text('Terms & Conditions'), findsWidgets);
      expect(find.text('MIRROR DIGITAL'), findsOneWidget);

      // Back button works
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(TermsAndConditionsScreen), findsNothing);
      expect(find.byType(SignupScreen), findsOneWidget);
    });
  });

  group('Profile Screen & More Options Legal Navigation Tests', () {
    testWidgets('8. Profile Screen Privacy Policy footer link navigates to PrivacyPolicyScreen',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final privacyLinkFinder = find.text('Privacy Policy');
      expect(privacyLinkFinder, findsOneWidget);

      await tester.tap(privacyLinkFinder);
      await tester.pumpAndSettle();

      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
      expect(find.text('1. ABOUT THIS PRIVACY POLICY'), findsOneWidget);

      // Back navigation
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(PrivacyPolicyScreen), findsNothing);
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('9. MoreOptionsScreen Privacy Policy and Terms navigate to correct screens',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: MoreOptionsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Privacy Policy
      await tester.tap(find.text('Privacy Policy'));
      await tester.pumpAndSettle();

      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      // Tap Terms and Conditions
      await tester.tap(find.text('Terms and Conditions'));
      await tester.pumpAndSettle();

      expect(find.byType(TermsAndConditionsScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    });
  });
}
