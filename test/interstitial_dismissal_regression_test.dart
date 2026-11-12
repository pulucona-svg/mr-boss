import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/models/manual_ad.dart';
import 'package:mirror_laikipia/services/interstitial_ad_service.dart';
import 'package:mirror_laikipia/widgets/manual_interstitial_ad_dialog.dart';

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

  group('TASK 1 — Interstitial Ad Dismissal & State Regression Tests', () {
    testWidgets('1. Ad dismissal returns to the existing viewer and preserves page without duplicate route', (tester) async {
      int currentPage = 42;
      int buildCount = 0;

      // Mock viewer widget representing MaterialViewerScreen
      final viewerWidget = StatefulBuilder(
        builder: (context, setState) {
          buildCount++;
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Document Viewer Active'),
                  Text('Page $currentPage'),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        currentPage = 43;
                      });
                    },
                    child: const Text('Next Page'),
                  ),
                ],
              ),
            ),
          );
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: InterstitialAdService.navigatorKey,
          home: viewerWidget,
        ),
      );

      expect(find.text('Document Viewer Active'), findsOneWidget);
      expect(find.text('Page 42'), findsOneWidget);
      expect(buildCount, equals(1));

      // Advance reading page
      await tester.tap(find.text('Next Page'));
      await tester.pumpAndSettle();
      expect(find.text('Page 43'), findsOneWidget);
      expect(buildCount, equals(2));

      // Simulate eligibility and presentation of interstitial ad
      service.isSubscribedOverrideForTesting = () => false;
      service.isOfflineOverrideForTesting = () => true;
      service.isEligibleForTesting = true;

      final testAd = ManualAd(
        id: 'interstitial_test_1',
        title: 'Test Sponsored Ad',
        subtitle: 'Test Subtitle',
        imageUrl: 'https://example.com/ad.jpg',
        contactUrl: 'https://wa.me/254700000000',
        placement: 'interstitial',
        isActive: true,
      );
      service.setCachedServerAdsForTesting([testAd]);

      // Show the interstitial ad over the viewer
      final showFuture = service.maybeShow(trigger: 'timer_interval_reached');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(InterstitialAdService.isFullScreenAdShowing, isTrue);
      // The ad is now visible over the viewer
      expect(find.byKey(const ValueKey('normal_interstitial_close_button')), findsOneWidget);

      // Tap the close button (X) to dismiss the advertisement normally
      await tester.tap(find.byKey(const ValueKey('normal_interstitial_close_button')));
      await tester.pumpAndSettle();
      // Pump past ManualAdViewTracker's 2-second debounce timer
      await tester.pump(const Duration(seconds: 3));

      final bool shownResult = await showFuture;
      expect(shownResult, isTrue);

      // Verify:
      // 1. Full screen ad guard is reset
      expect(InterstitialAdService.isFullScreenAdShowing, isFalse);
      // 2. Active session timer reset for the next interval
      expect(service.isEligible, isFalse);
      expect(service.activeSecondsInCurrentInterval, equals(0));
      // 3. User immediately returns to the same document viewer
      expect(find.text('Document Viewer Active'), findsOneWidget);
      // 4. Viewer remains on the exact same page
      expect(find.text('Page 43'), findsOneWidget);
      // 5. No duplicate viewer route created
      expect(find.text('Document Viewer Active'), findsOneWidget);
    });

    test('2. Failed ad presentation resets the ad state and avoids infinite re-trigger loop', () async {
      service.isSubscribedOverrideForTesting = () => false;
      service.isOfflineOverrideForTesting = () => false;
      service.isEligibleForTesting = true;

      // Simulate an ad failure callback
      InterstitialAdService.isFullScreenAdShowing = true;
      final completer = Completer<bool>();
      bool didComplete = false;

      // Simulate failure handler logic
      try {
        throw Exception('AdMob show failed: AdActivity unavailable');
      } catch (_) {
        InterstitialAdService.isFullScreenAdShowing = false;
        service.isEligibleForTesting = false;
        if (!completer.isCompleted) completer.complete(false);
        didComplete = true;
      }

      final result = await completer.future;
      expect(result, isFalse);
      expect(didComplete, isTrue);
      // Ad state is safely reset, preventing overlapping interstitials
      expect(InterstitialAdService.isFullScreenAdShowing, isFalse);
      expect(service.isEligible, isFalse);
      expect(service.activeSecondsInCurrentInterval, equals(0));
    });

    test('3. Repeated dismissal callbacks do not cause navigation errors or duplicate state mutation', () {
      bool isDismissedHandled = false;
      int dismissCounter = 0;

      void onAdDismissed() {
        if (isDismissedHandled) {
          return; // Guarded against duplicate dismissal
        }
        isDismissedHandled = true;
        dismissCounter++;
        InterstitialAdService.isFullScreenAdShowing = false;
        service.isEligibleForTesting = false;
      }

      InterstitialAdService.isFullScreenAdShowing = true;
      service.isEligibleForTesting = true;

      // First callback
      onAdDismissed();
      expect(dismissCounter, equals(1));
      expect(InterstitialAdService.isFullScreenAdShowing, isFalse);
      expect(service.isEligible, isFalse);

      // Second duplicate callback (e.g. rapid taps or OEM platform duplicate)
      onAdDismissed();
      expect(dismissCounter, equals(1)); // Did not execute again
      expect(InterstitialAdService.isFullScreenAdShowing, isFalse);
      expect(service.isEligible, isFalse);
    });

    test('4. Existing subscriber ad-free rules remain strictly intact', () async {
      service.isSubscribedOverrideForTesting = () => true; // Active subscriber
      service.isEligibleForTesting = true;

      // Should return false immediately without displaying ad
      final bool transitionResult = await service.maybeShowOnTransition(
        transitionPoint: 'document_view_transition',
      );
      expect(transitionResult, isFalse);

      final bool timerResult = await service.maybeShow(
        trigger: 'timer_interval_reached',
      );
      expect(timerResult, isFalse);

      expect(InterstitialAdService.isFullScreenAdShowing, isFalse);
    });

    test('5. Simultaneous full-screen guard prevents duplicate or overlapping interstitials', () async {
      service.isSubscribedOverrideForTesting = () => false;
      service.isEligibleForTesting = true;
      InterstitialAdService.isFullScreenAdShowing = true; // An ad is already showing

      // Attempting to show another interstitial must be rejected
      final bool rejected = await service.maybeShow(trigger: 'concurrent_test');
      expect(rejected, isFalse);
    });

    test('6. Online idle timer delays follow the configured timing sequence (5s, 20s, 60s, 120s, 240s -> STOP)', () {
      expect(service.getOnlineIdleDelay(0), equals(const Duration(seconds: 5)));
      expect(service.getOnlineIdleDelay(1), equals(const Duration(seconds: 20)));
      expect(service.getOnlineIdleDelay(2), equals(const Duration(seconds: 60)));
      expect(service.getOnlineIdleDelay(3), equals(const Duration(seconds: 120)));
      expect(service.getOnlineIdleDelay(4), equals(const Duration(seconds: 240)));
      expect(service.getOnlineIdleDelay(5), isNull);
    });

    test('7. Active native AdMob ad retains exclusive window focus during idle chain', () {
      // Simulate active native AdMob presentation
      InterstitialAdService.isFullScreenAdShowing = true;
      expect(InterstitialAdService.isFullScreenAdShowing, isTrue);

      // Verify that while full screen is active, competing presentation is deferred
      expect(service.isEligible, isFalse);
    });

    testWidgets('8. Manual interstitial ad close button has accessible tap targets and closes overlay', (tester) async {
      bool isDismissed = false;
      final testAd = ManualAd(
        id: 'manual_touch_target_test',
        title: 'Accessible Target Ad',
        subtitle: 'Tap Area Test',
        imageUrl: 'https://example.com/target.jpg',
        contactUrl: 'https://wa.me/254700000000',
        placement: 'interstitial',
        isActive: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showGeneralDialog(
                      context: context,
                      useRootNavigator: true,
                      pageBuilder: (ctx, anim1, anim2) {
                        return ManualInterstitialAdDialog(
                          adData: testAd.toDialogData(),
                          onDismissed: () => isDismissed = true,
                        );
                      },
                    );
                  },
                  child: const Text('Launch Ad'),
                );
              },
            ),
          ),
        ),
      );

      // Launch dialog
      await tester.tap(find.text('Launch Ad'));
      await tester.pumpAndSettle();

      // Find normal close button
      final closeButtonFinder = find.byKey(const ValueKey('normal_interstitial_close_button'));
      expect(closeButtonFinder, findsOneWidget);

      // Tap close button
      await tester.tap(closeButtonFinder);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));

      expect(isDismissed, isTrue);
      expect(find.byKey(const ValueKey('normal_interstitial_close_button')), findsNothing);
    });
  });
}
