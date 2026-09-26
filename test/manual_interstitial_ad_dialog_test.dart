import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/models/manual_ad.dart';
import 'package:mirror_laikipia/services/interstitial_ad_service.dart';
import 'package:mirror_laikipia/widgets/manual_interstitial_ad_dialog.dart';
import 'package:mirror_laikipia/widgets/ad_carousel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InterstitialAdService service;

  setUp(() {
    service = InterstitialAdService();
    service.resetForTesting();
    service.skipAdLoadingForTesting = true;
    service.skipFirestoreForTesting = true;
  });

  tearDown(() {
    service.resetForTesting();
  });

  group('ManualInterstitialAdDialog In-Place Rotation and Live Sync Tests', () {
    testWidgets('1. Dialog advances in-place according to manual idle schedule', (tester) async {
      final adA = ManualAd(
        id: 'ad_A',
        title: 'Ad Alpha',
        subtitle: 'Alpha subtitle description',
        imageUrl: 'assets/ad_cyber.jpeg',
        contactUrl: 'https://wa.me/254111',
        colorValue: 0xFF111111,
        isActive: true,
        isAsset: true,
        type: 'image',
      );

      final adB = ManualAd(
        id: 'ad_B',
        title: 'Ad Beta',
        subtitle: 'Beta subtitle description',
        imageUrl: 'assets/ad_data.jpeg',
        contactUrl: 'https://wa.me/254222',
        colorValue: 0xFF222222,
        isActive: true,
        isAsset: true,
        type: 'image',
      );

      service.setCachedServerAdsForTesting([adA, adB]);

      // Override idle delays for fast deterministic test execution: 100ms, 200ms
      service.manualIdleDelayOverrideForTesting = (stage) {
        if (stage == 0) return const Duration(milliseconds: 100);
        return const Duration(milliseconds: 200);
      };

      bool dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManualInterstitialAdDialog(
              adData: adA.toDialogData(),
              onDismissed: () {
                dismissed = true;
              },
            ),
          ),
        ),
      );

      // Initially Ad Alpha is displayed
      expect(find.text('Ad Alpha'), findsOneWidget);
      expect(find.text('Alpha subtitle description'), findsOneWidget);
      expect(find.text('Ad Beta'), findsNothing);

      // Fast forward past stage 0 idle timeout (100ms)
      await tester.pump(const Duration(milliseconds: 150));

      // Now Ad Beta should be displayed in-place
      expect(find.text('Ad Beta'), findsOneWidget);
      expect(find.text('Beta subtitle description'), findsOneWidget);
      expect(find.text('Ad Alpha'), findsNothing);

      // Fast forward past stage 1 idle timeout (200ms)
      await tester.pump(const Duration(milliseconds: 250));

      // Rotates back to Ad Alpha
      expect(find.text('Ad Alpha'), findsOneWidget);
      expect(find.text('Alpha subtitle description'), findsOneWidget);

      // User taps Close button
      final closeButton = find.byTooltip('Close Ad');
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
    });

    testWidgets('2. Dialog immediately advances if current ad is deactivated/deleted by admin', (tester) async {
      final adA = ManualAd(
        id: 'ad_A',
        title: 'Ad Alpha',
        subtitle: 'Alpha subtitle description',
        imageUrl: 'assets/ad_cyber.jpeg',
        contactUrl: 'https://wa.me/254111',
        colorValue: 0xFF111111,
        isActive: true,
        isAsset: true,
        type: 'image',
      );

      final adB = ManualAd(
        id: 'ad_B',
        title: 'Ad Beta',
        subtitle: 'Beta subtitle description',
        imageUrl: 'assets/ad_data.jpeg',
        contactUrl: 'https://wa.me/254222',
        colorValue: 0xFF222222,
        isActive: true,
        isAsset: true,
        type: 'image',
      );

      service.setCachedServerAdsForTesting([adA, adB]);

      // Long delay so idle timer does not fire during this test
      service.manualIdleDelayOverrideForTesting = (_) => const Duration(seconds: 300);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManualInterstitialAdDialog(
              adData: adA.toDialogData(),
              onDismissed: () {},
            ),
          ),
        ),
      );

      expect(find.text('Ad Alpha'), findsOneWidget);

      // Admin deactivates adA in real-time
      final adADeactivated = adA.copyWith(isActive: false);
      service.setCachedServerAdsForTesting([adADeactivated, adB]);

      await tester.pump();

      // Dialog should have reacted to listener and switched immediately to Ad Beta
      expect(find.text('Ad Beta'), findsOneWidget);
      expect(find.text('Ad Alpha'), findsNothing);
    });

    testWidgets('3. Dialog dismisses cleanly if all ads are deactivated by admin', (tester) async {
      final adA = ManualAd(
        id: 'ad_A',
        title: 'Ad Alpha',
        subtitle: 'Alpha subtitle description',
        imageUrl: 'assets/ad_cyber.jpeg',
        contactUrl: 'https://wa.me/254111',
        colorValue: 0xFF111111,
        isActive: true,
        isAsset: true,
        type: 'image',
      );

      service.setCachedServerAdsForTesting([adA]);
      service.manualIdleDelayOverrideForTesting = (_) => const Duration(seconds: 300);

      bool dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManualInterstitialAdDialog(
              adData: adA.toDialogData(),
              onDismissed: () {
                dismissed = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Ad Alpha'), findsOneWidget);

      // Admin deletes / deactivates all ads
      service.setCachedServerAdsForTesting([]);

      await tester.pump();

      expect(dismissed, isTrue);
    });

    testWidgets('4. Image interstitial display duration is 10 seconds', (tester) async {
      final adA = ManualAd(
        id: 'ad_A',
        title: 'Ad Alpha',
        subtitle: 'Alpha subtitle description',
        imageUrl: 'assets/ad_cyber.jpeg',
        contactUrl: 'https://wa.me/254111',
        colorValue: 0xFF111111,
        isActive: true,
        isAsset: true,
        type: 'image',
      );

      final adB = ManualAd(
        id: 'ad_B',
        title: 'Ad Beta',
        subtitle: 'Beta subtitle description',
        imageUrl: 'assets/ad_data.jpeg',
        contactUrl: 'https://wa.me/254222',
        colorValue: 0xFF222222,
        isActive: true,
        isAsset: true,
        type: 'image',
      );

      service.setCachedServerAdsForTesting([adA, adB]);
      service.manualIdleDelayOverrideForTesting = null; // Production 10-second duration

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManualInterstitialAdDialog(
              adData: adA.toDialogData(),
              onDismissed: () {},
            ),
          ),
        ),
      );

      // Initially Ad Alpha is shown
      expect(find.text('Ad Alpha'), findsOneWidget);
      expect(find.text('Ad Beta'), findsNothing);

      // After 9 seconds, Ad Alpha is still showing
      await tester.pump(const Duration(seconds: 9));
      expect(find.text('Ad Alpha'), findsOneWidget);
      expect(find.text('Ad Beta'), findsNothing);

      // At 10 seconds, it advances in-place to Ad Beta
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Ad Beta'), findsOneWidget);
      expect(find.text('Ad Alpha'), findsNothing);
    });

    testWidgets('5. Full-screen presentation renders creative with BoxFit.contain and metadata overlay', (tester) async {
      final adA = ManualAd(
        id: 'ad_A',
        title: 'Full Screen Promo',
        subtitle: 'Special offer subtitle',
        imageUrl: 'assets/ad_cyber.jpeg',
        contactUrl: 'https://wa.me/254111',
        colorValue: 0xFF111111,
        isActive: true,
        isAsset: true,
        type: 'image',
      );

      service.setCachedServerAdsForTesting([adA]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManualInterstitialAdDialog(
              adData: adA.toDialogData(),
              onDismissed: () {},
            ),
          ),
        ),
      );

      // Verified full-screen image with BoxFit.contain
      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);
      final Image imageWidget = tester.widget(imageFinder);
      expect(imageWidget.fit, equals(BoxFit.contain));

      // Verified metadata overlay: Title, Subtitle, WhatsApp CTA, Return to App, Close X
      expect(find.text('Full Screen Promo'), findsOneWidget);
      expect(find.text('Special offer subtitle'), findsOneWidget);
      expect(find.text('Contact via WhatsApp'), findsOneWidget);
      expect(find.text('Return to App'), findsOneWidget);
      expect(find.byTooltip('Close Ad'), findsOneWidget);
    });

    testWidgets('6. AdCarousel renders creative adaptively with BoxFit.contain', (tester) async {
      final adA = {
        'id': 'ad_1',
        'title': 'Carousel Ad',
        'subtitle': 'Carousel Subtitle',
        'url': 'assets/ad_cyber.jpeg',
        'imageUrl': 'assets/ad_cyber.jpeg',
        'isAsset': true,
        'type': 'image',
        'color': Colors.blue,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdCarousel(
              ads: [adA],
              height: 180,
            ),
          ),
        ),
      );

      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);
      final Image imageWidget = tester.widget(imageFinder);
      expect(imageWidget.fit, equals(BoxFit.contain));
      expect(imageWidget.alignment, equals(Alignment.center));
    });
  });
}
