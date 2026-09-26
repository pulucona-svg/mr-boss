import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/services/interstitial_ad_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InterstitialAdService service;

  setUp(() {
    service = InterstitialAdService();
    service.resetForTesting();
    service.skipAdLoadingForTesting = true;
    service.isSubscribedOverrideForTesting = () => false;
    service.isOfflineOverrideForTesting = () => false;
  });

  tearDown(() {
    service.resetForTesting();
  });

  group('InterstitialAdService Acceptance Tests', () {
    test('1. Fresh app launch does NOT immediately show an interstitial or mark as eligible', () {
      expect(service.isEligible, isFalse);
      expect(service.activeSecondsInCurrentInterval, equals(0));
    });

    test('2. Official Google test interstitial ad unit ID is used', () {
      expect(
        InterstitialAdService.testAdUnitId,
        equals('ca-app-pub-3940256099942544/1033173712'),
      );
      expect(
        InterstitialAdService.defaultSessionInterval,
        equals(const Duration(minutes: 5)),
      );
    });

    test('3. Interval is configurable for testing without altering production default', () {
      expect(service.sessionInterval, equals(const Duration(minutes: 5)));
      service.sessionIntervalForTesting = const Duration(seconds: 30);
      expect(service.sessionInterval, equals(const Duration(seconds: 30)));
    });

    test('4. Active paid subscriber NEVER receives interstitial ads', () async {
      service.isSubscribedOverrideForTesting = () => true;
      service.isEligibleForTesting = true;

      final bool shown = await service.maybeShowOnTransition(
        transitionPoint: 'main_nav_tab_switch',
      );

      expect(shown, isFalse);
    });

    test('5. Inactive/non-subscriber is evaluated when eligible', () async {
      service.isSubscribedOverrideForTesting = () => false;
      service.isEligibleForTesting = false;

      // When not yet eligible (under 15 minutes)
      final bool notEligibleShown = await service.maybeShowOnTransition(
        transitionPoint: 'main_nav_tab_switch',
      );
      expect(notEligibleShown, isFalse);
    });

    test('6. Guard prevents simultaneous full-screen ad presentation', () async {
      service.isSubscribedOverrideForTesting = () => false;
      service.isEligibleForTesting = true;
      InterstitialAdService.isFullScreenAdShowing = true;

      final bool shown = await service.maybeShowOnTransition(
        transitionPoint: 'main_nav_tab_switch',
      );

      expect(shown, isFalse);
    });

    test('7. App lifecycle pauses timer on background and resumes on foreground', () {
      service.initialize();
      expect(service.isEligible, isFalse);

      // App goes to background
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      final int pausedSeconds = service.activeSecondsInCurrentInterval;

      // App returns to foreground
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(service.activeSecondsInCurrentInterval, equals(pausedSeconds));
    });

    test('8. Resetting for testing restores initial state cleanly', () {
      service.isEligibleForTesting = true;
      InterstitialAdService.isFullScreenAdShowing = true;
      service.sessionIntervalForTesting = const Duration(seconds: 10);
      service.isSubscribedOverrideForTesting = () => true;
      service.isOfflineOverrideForTesting = () => true;

      service.resetForTesting();

      expect(service.isEligible, isFalse);
      expect(service.activeSecondsInCurrentInterval, equals(0));
      expect(InterstitialAdService.isFullScreenAdShowing, isFalse);
      expect(service.sessionInterval, equals(const Duration(minutes: 5)));
      expect(service.isSubscribedOverrideForTesting, isNull);
      expect(service.isOfflineOverrideForTesting, isNull);
      expect(service.skipAdLoadingForTesting, isFalse);
    });

    test('9. When device is offline, offline manual interstitial ad is displayed upon eligibility', () async {
      service.isSubscribedOverrideForTesting = () => false;
      service.isOfflineOverrideForTesting = () => true;
      service.isEligibleForTesting = true;

      bool offlineAdInvoked = false;
      service.offlineManualAdPresenterForTesting = () async {
        offlineAdInvoked = true;
        return true;
      };

      final bool shown = await service.maybeShow(trigger: 'article_reading_interval');

      expect(shown, isTrue);
      expect(offlineAdInvoked, isTrue);
      expect(service.isEligible, isFalse);
      expect(service.activeSecondsInCurrentInterval, equals(0));
    });

    test('10. Interstitial ad can run while reading an article without waiting for exit', () async {
      service.isSubscribedOverrideForTesting = () => false;
      service.isEligibleForTesting = true;

      bool adInvoked = false;
      service.offlineManualAdPresenterForTesting = () async {
        adInvoked = true;
        return true;
      };

      // Trigger while in article screen
      final bool shown = await service.maybeShow(trigger: 'full_article_screen_reading');

      expect(shown, isTrue);
      expect(adInvoked, isTrue);
    });

    test('11. Active paid subscriber is exempt even when offline', () async {
      service.isSubscribedOverrideForTesting = () => true;
      service.isOfflineOverrideForTesting = () => true;
      service.isEligibleForTesting = true;

      bool offlineAdInvoked = false;
      service.offlineManualAdPresenterForTesting = () async {
        offlineAdInvoked = true;
        return true;
      };

      final bool shown = await service.maybeShow(trigger: 'offline_check');

      expect(shown, isFalse);
      expect(offlineAdInvoked, isFalse);
    });
  });
}
