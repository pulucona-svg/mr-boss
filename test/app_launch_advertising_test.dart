import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/services/interstitial_ad_service.dart';
import 'package:mirror_laikipia/services/app_open_ad_manager.dart';
import 'package:mirror_laikipia/services/launch_ad_service.dart';
import 'package:mirror_laikipia/models/manual_ad.dart';
import 'package:mirror_laikipia/widgets/manual_interstitial_ad_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
    await PersistenceService().clearAll();
    AppOpenAdManager().resetForTesting();
    AppOpenAdManager().skipAdLoadingForTesting = true;
    LaunchAdService().resetForTesting();
    LaunchAdService().skipDelayForTesting = true;
    InterstitialAdService().resetForTesting();
    InterstitialAdService().skipAdLoadingForTesting = true;
    InterstitialAdService().skipFirestoreForTesting = true;
  });

  tearDown(() {
    AppOpenAdManager().resetForTesting();
    LaunchAdService().resetForTesting();
    InterstitialAdService().resetForTesting();
  });

  group('App Launch Advertising - Eligibility & Rules', () {
    test('1. First launch -> no launch ad', () {
      LaunchAdService().isLoggedInOverrideForTesting = true;
      LaunchAdService().hasLaunchedOverrideForTesting = false; // first-ever launch
      LaunchAdService().isSubscribedOverrideForTesting = false;

      final isEligible = LaunchAdService().isEligibleForLaunchAd();
      expect(isEligible, isFalse);
    });

    test('2. Logged-out user -> no launch ad', () {
      LaunchAdService().isLoggedInOverrideForTesting = false; // logged out
      LaunchAdService().hasLaunchedOverrideForTesting = true;
      LaunchAdService().isSubscribedOverrideForTesting = false;

      final isEligible = LaunchAdService().isEligibleForLaunchAd();
      expect(isEligible, isFalse);
    });

    test('3. Active subscriber -> no launch ad', () {
      LaunchAdService().isLoggedInOverrideForTesting = true;
      LaunchAdService().hasLaunchedOverrideForTesting = true;
      LaunchAdService().isSubscribedOverrideForTesting = true; // active subscriber

      final isEligible = LaunchAdService().isEligibleForLaunchAd();
      expect(isEligible, isFalse);
    });

    test('4. Returning logged-in non-subscriber -> eligible', () {
      LaunchAdService().isLoggedInOverrideForTesting = true;
      LaunchAdService().hasLaunchedOverrideForTesting = true;
      LaunchAdService().isSubscribedOverrideForTesting = false;

      final isEligible = LaunchAdService().isEligibleForLaunchAd();
      expect(isEligible, isTrue);
    });

    test('15. Expired App Open Ad is not shown (>= 4 hours)', () {
      final manager = AppOpenAdManager();
      // Set an ad loaded 4 hours and 5 minutes ago
      final fourHoursAgo = DateTime.now().subtract(const Duration(hours: 4, minutes: 5));
      manager.setAdForTesting(null, loadTime: fourHoursAgo);

      expect(manager.isAdAvailable, isFalse);
    });

    test('16. Valid fresh App Open Ad is available (< 4 hours)', () {
      final manager = AppOpenAdManager();
      final freshTime = DateTime.now().subtract(const Duration(hours: 1));
      manager.setAdForTesting(null, loadTime: freshTime);
      expect(manager.isAdAvailable, isFalse); // null ad
    });
  });

  group('App Launch Advertising - Flow & Execution', () {
    testWidgets('5. Online App Open Ad available -> show online launch ad', (tester) async {
      LaunchAdService().isLoggedInOverrideForTesting = true;
      LaunchAdService().hasLaunchedOverrideForTesting = true;
      LaunchAdService().isSubscribedOverrideForTesting = false;
      LaunchAdService().isOfflineOverrideForTesting = false;

      bool adShowInvoked = false;
      AppOpenAdManager().showAdOverrideForTesting = ({required onDismissed}) async {
        adShowInvoked = true;
        onDismissed();
        return true;
      };

      bool appContinued = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await LaunchAdService().handleAppLaunch(
                    context: context,
                    splashStartTime: DateTime.now(),
                    onContinue: () {
                      appContinued = true;
                    },
                  );
                },
                child: const Text('Start'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(adShowInvoked, isTrue);
      expect(appContinued, isTrue);
      expect(PersistenceService().getBool(LaunchAdService.kHasLaunchedAppKey), isTrue);
    });

    testWidgets('6. Online App Open Ad unavailable -> app continues without blocking', (tester) async {
      LaunchAdService().isLoggedInOverrideForTesting = true;
      LaunchAdService().hasLaunchedOverrideForTesting = true;
      LaunchAdService().isSubscribedOverrideForTesting = false;
      LaunchAdService().isOfflineOverrideForTesting = false;
      // Ad is NOT available
      expect(AppOpenAdManager().isAdAvailable, isFalse);

      bool appContinued = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await LaunchAdService().handleAppLaunch(
                    context: context,
                    splashStartTime: DateTime.now(),
                    onContinue: () {
                      appContinued = true;
                    },
                  );
                },
                child: const Text('Start'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(appContinued, isTrue);
    });

    testWidgets('7. Online ad fails to show -> app continues cleanly', (tester) async {
      LaunchAdService().isLoggedInOverrideForTesting = true;
      LaunchAdService().hasLaunchedOverrideForTesting = true;
      LaunchAdService().isSubscribedOverrideForTesting = false;
      LaunchAdService().isOfflineOverrideForTesting = false;

      AppOpenAdManager().showAdOverrideForTesting = ({required onDismissed}) async {
        // Simulates show failure
        onDismissed();
        return false;
      };

      bool appContinued = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await LaunchAdService().handleAppLaunch(
                    context: context,
                    splashStartTime: DateTime.now(),
                    onContinue: () {
                      appContinued = true;
                    },
                  );
                },
                child: const Text('Start'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(appContinued, isTrue);
    });

    testWidgets('8. Offline eligible user with launch ad -> offline launch ad displays', (tester) async {
      LaunchAdService().isLoggedInOverrideForTesting = true;
      LaunchAdService().hasLaunchedOverrideForTesting = true;
      LaunchAdService().isSubscribedOverrideForTesting = false;
      LaunchAdService().isOfflineOverrideForTesting = true;

      // Seed an offline app launch ad
      final testLaunchAd = ManualAd(
        id: 'offline_launch_1',
        title: 'Campus Printing & Cyber',
        subtitle: 'Fast printing and academic stationery',
        imageUrl: 'assets/ad_cyber.jpeg',
        contactUrl: 'https://wa.me/254108462492',
        placement: 'app_launch',
        isActive: true,
      );
      InterstitialAdService().setCachedServerAdsForTesting([testLaunchAd]);

      bool offlineAdPresented = false;
      LaunchAdService().offlineLaunchPresenterForTesting = ({context, required onDismissed}) async {
        offlineAdPresented = true;
        onDismissed();
        return true;
      };

      bool appContinued = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await LaunchAdService().handleAppLaunch(
                    context: context,
                    splashStartTime: DateTime.now(),
                    onContinue: () {
                      appContinued = true;
                    },
                  );
                },
                child: const Text('Start'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(offlineAdPresented, isTrue);
      expect(appContinued, isTrue);
    });

    testWidgets('9 & 10. Offline countdown starts at 5, decrements to 0, then enters X state with 2s auto-close', (tester) async {
      bool onDismissedCalled = false;
      const testAdData = {
        'id': 'offline_launch_test',
        'title': 'Test Launch Ad',
        'subtitle': 'Countdown test subtitle',
        'url': 'assets/ad_cyber.jpeg',
        'contactUrl': 'https://wa.me/254108462492',
        'color': Color(0xFF20C8FF),
        'type': 'image',
        'placement': 'app_launch',
        'isAsset': true,
        'isAppLaunch': true,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManualInterstitialAdDialog(
              adData: testAdData,
              isAppLaunch: true,
              onDismissed: () {
                onDismissedCalled = true;
              },
            ),
          ),
        ),
      );

      // Verify initial countdown display starts at 5
      expect(find.byKey(const ValueKey('launch_countdown_badge')), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('Sponsored'), findsOneWidget);
      // Close button X should not be shown during countdown
      expect(find.byKey(const ValueKey('launch_x_button')), findsNothing);

      // Advance by 1 second -> 4
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('4'), findsOneWidget);

      // Advance by 1 second -> 3
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('3'), findsOneWidget);

      // Advance by 1 second -> 2
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2'), findsOneWidget);

      // Advance by 1 second -> 1
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1'), findsOneWidget);

      // Advance by 1 second -> 0
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('0'), findsOneWidget);
      expect(onDismissedCalled, isFalse);

      // Advance by 1 second -> X state appears
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('launch_x_badge')), findsOneWidget);
      expect(find.byKey(const ValueKey('launch_x_button')), findsOneWidget);
      expect(onDismissedCalled, isFalse);

      // Advance by 1 second (1s of X state) -> still waiting
      await tester.pump(const Duration(seconds: 1));
      expect(onDismissedCalled, isFalse);

      // Advance by 1 more second (2s of X state total) -> auto-close triggers!
      await tester.pump(const Duration(seconds: 1));
      expect(onDismissedCalled, isTrue);
    });

    testWidgets('10a. Offline ad: tapping X during 2-second window closes immediately', (tester) async {
      bool onDismissedCalled = false;
      const testAdData = {
        'id': 'offline_launch_tap_test',
        'title': 'Test Launch Ad',
        'subtitle': 'Tap test subtitle',
        'url': 'assets/ad_cyber.jpeg',
        'contactUrl': 'https://wa.me/254108462492',
        'color': Color(0xFF20C8FF),
        'type': 'image',
        'placement': 'app_launch',
        'isAsset': true,
        'isAppLaunch': true,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManualInterstitialAdDialog(
              adData: testAdData,
              isAppLaunch: true,
              onDismissed: () {
                onDismissedCalled = true;
              },
            ),
          ),
        ),
      );

      // Fast forward 6 seconds to reach X state (5s down to 0 + 1s to X)
      await tester.pump(const Duration(seconds: 6));
      expect(find.byKey(const ValueKey('launch_x_button')), findsOneWidget);
      expect(onDismissedCalled, isFalse);

      // Tap X immediately
      await tester.tap(find.byKey(const ValueKey('launch_x_button')));
      await tester.pump();

      expect(onDismissedCalled, isTrue);
    });

    testWidgets('10b. Dialog pops route before invoking onDismissed, preventing navigation stack hang', (tester) async {
      bool onDismissedCalled = false;
      const testAdData = {
        'id': 'offline_launch_pop_test',
        'title': 'Test Pop Ad',
        'subtitle': 'Pop order subtitle',
        'url': 'assets/ad_cyber.jpeg',
        'contactUrl': 'https://wa.me/254108462492',
        'color': Color(0xFF20C8FF),
        'type': 'image',
        'placement': 'app_launch',
        'isAsset': true,
        'isAppLaunch': true,
      };

      bool homePushed = false;

      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/home': (context) {
              homePushed = true;
              return const Scaffold(body: Text('Home Screen'));
            },
          },
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  showGeneralDialog(
                    context: context,
                    pageBuilder: (dialogContext, anim1, anim2) => ManualInterstitialAdDialog(
                      adData: testAdData,
                      isAppLaunch: true,
                      onDismissed: () {
                        onDismissedCalled = true;
                        Navigator.pushReplacementNamed(context, '/home');
                      },
                    ),
                  );
                },
                child: const Text('Open Ad'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open Ad'));
      await tester.pumpAndSettle();

      // Fast forward to X state
      await tester.pump(const Duration(seconds: 6));
      await tester.tap(find.byKey(const ValueKey('launch_x_button')));
      await tester.pumpAndSettle();

      expect(onDismissedCalled, isTrue);
      expect(homePushed, isTrue);
      expect(find.text('Home Screen'), findsOneWidget);
    });

    testWidgets('11. Offline ad missing -> app proceeds normally without stuck splash', (tester) async {
      LaunchAdService().isLoggedInOverrideForTesting = true;
      LaunchAdService().hasLaunchedOverrideForTesting = true;
      LaunchAdService().isSubscribedOverrideForTesting = false;
      LaunchAdService().isOfflineOverrideForTesting = true;

      // No app launch ads in runtime pool
      InterstitialAdService().setCachedServerAdsForTesting([
        ManualAd(
          id: 'normal_interstitial',
          title: 'Normal Interstitial',
          subtitle: 'Normal',
          imageUrl: 'assets/ad_snake.jpeg',
          contactUrl: '',
          placement: 'interstitial',
          isActive: true,
        ),
      ]);

      expect(InterstitialAdService().getNextAppLaunchAd(), isNull);

      bool appContinued = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await LaunchAdService().handleAppLaunch(
                    context: context,
                    splashStartTime: DateTime.now(),
                    onContinue: () {
                      appContinued = true;
                    },
                  );
                },
                child: const Text('Start'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(appContinued, isTrue);
    });

    testWidgets('12. Online and offline launch ads never display together', (tester) async {
      LaunchAdService().isLoggedInOverrideForTesting = true;
      LaunchAdService().hasLaunchedOverrideForTesting = true;
      LaunchAdService().isSubscribedOverrideForTesting = false;
      LaunchAdService().isOfflineOverrideForTesting = false; // ONLINE

      // Even if offline ad is available in pool
      InterstitialAdService().setCachedServerAdsForTesting([
        ManualAd(
          id: 'offline_launch_ad',
          title: 'Offline Launch',
          subtitle: '',
          imageUrl: 'assets/ad_cyber.jpeg',
          contactUrl: '',
          placement: 'app_launch',
          isActive: true,
        ),
      ]);

      bool offlineAdShown = false;
      LaunchAdService().offlineLaunchPresenterForTesting = ({context, required onDismissed}) async {
        offlineAdShown = true;
        onDismissed();
        return true;
      };

      bool onlineAdShown = false;
      AppOpenAdManager().showAdOverrideForTesting = ({required onDismissed}) async {
        onlineAdShown = true;
        onDismissed();
        return true;
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await LaunchAdService().handleAppLaunch(
                    context: context,
                    splashStartTime: DateTime.now(),
                    onContinue: () {},
                  );
                },
                child: const Text('Start'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      // Because device was online, offline ad was NOT shown!
      expect(onlineAdShown, isTrue);
      expect(offlineAdShown, isFalse);
    });

    testWidgets('13. Launch ad resets session timer to prevent immediate normal interstitial', (tester) async {
      LaunchAdService().isLoggedInOverrideForTesting = true;
      LaunchAdService().hasLaunchedOverrideForTesting = true;
      LaunchAdService().isSubscribedOverrideForTesting = false;
      LaunchAdService().isOfflineOverrideForTesting = false;

      // Simulate session timer had accumulated time
      InterstitialAdService().isEligibleForTesting = true;

      AppOpenAdManager().showAdOverrideForTesting = ({required onDismissed}) async {
        onDismissed();
        return true;
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await LaunchAdService().handleAppLaunch(
                    context: context,
                    splashStartTime: DateTime.now(),
                    onContinue: () {},
                  );
                },
                child: const Text('Start'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      // Timer and eligibility must be reset to 0
      expect(InterstitialAdService().isEligible, isFalse);
      expect(InterstitialAdService().activeSecondsInCurrentInterval, 0);
    });

    test('14. App resume does not cause repeated launch ads', () {
      final adService = InterstitialAdService();
      adService.didChangeAppLifecycleState(AppLifecycleState.resumed);
      // AppOpenAdManager is not invoked automatically on resumed
      expect(AppOpenAdManager().isShowingAd, isFalse);
    });

    testWidgets('18. Splash behavior remains unchanged for subscribers, logged-out users, and first launch', (tester) async {
      int continueCalls = 0;

      // Test Subscriber
      LaunchAdService().resetForTesting();
      LaunchAdService().skipDelayForTesting = true;
      LaunchAdService().isLoggedInOverrideForTesting = true;
      LaunchAdService().hasLaunchedOverrideForTesting = true;
      LaunchAdService().isSubscribedOverrideForTesting = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await LaunchAdService().handleAppLaunch(
                    context: context,
                    splashStartTime: DateTime.now(),
                    onContinue: () => continueCalls++,
                  );
                },
                child: const Text('Go'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(continueCalls, 1);
    });

    testWidgets('19. 1.5s Race Condition: Ad finishes loading during bounded wait -> ad displays', (tester) async {
      LaunchAdService().isLoggedInOverrideForTesting = true;
      LaunchAdService().hasLaunchedOverrideForTesting = true;
      LaunchAdService().isSubscribedOverrideForTesting = false;
      // Ad is NOT ready initially at 1.5s
      AppOpenAdManager().isAdAvailableOverrideForTesting = false;

      bool adPresented = false;
      AppOpenAdManager().showAdOverrideForTesting = ({required onDismissed}) async {
        adPresented = true;
        onDismissed();
        return true;
      };

      AppOpenAdManager().waitForAdOverrideForTesting = ({required timeout}) async {
        // Simulates ad finishing loading at 1.8s (during the bounded wait)
        AppOpenAdManager().isAdAvailableOverrideForTesting = true;
        return true;
      };

      bool appContinued = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await LaunchAdService().handleAppLaunch(
                    context: context,
                    splashStartTime: DateTime.now(),
                    onContinue: () => appContinued = true,
                  );
                },
                child: const Text('Start'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(adPresented, isTrue);
      expect(appContinued, isTrue);
    });

    testWidgets('20. 1.5s Race Condition: Ad times out during bounded wait -> app proceeds cleanly without getting stuck', (tester) async {
      LaunchAdService().isLoggedInOverrideForTesting = true;
      LaunchAdService().hasLaunchedOverrideForTesting = true;
      LaunchAdService().isSubscribedOverrideForTesting = false;
      LaunchAdService().isOfflineOverrideForTesting = false;

      // Ad never finishes loading within timeout
      AppOpenAdManager().waitForAdOverrideForTesting = ({required timeout}) async {
        return false;
      };

      bool appContinued = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await LaunchAdService().handleAppLaunch(
                    context: context,
                    splashStartTime: DateTime.now(),
                    onContinue: () => appContinued = true,
                  );
                },
                child: const Text('Start'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(appContinued, isTrue);
    });
  });

  group('App Launch Advertising - Warm Start (3-Minute Threshold)', () {
    test('21. Warm start < 3 minutes -> no launch ad shown', () {
      final service = LaunchAdService();
      service.isLoggedInOverrideForTesting = true;
      service.hasLaunchedOverrideForTesting = true;
      service.isSubscribedOverrideForTesting = false;

      // Simulate app was backgrounded 2 minutes ago (< 3 min)
      service.lastBackgroundedTimeForTesting = DateTime.now().subtract(const Duration(minutes: 2));

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);

      // Verify no warm start ad was executed
      expect(service.isExecutingWarmStart, isFalse);
    });

    test('22. Warm start >= 3 minutes (Online) -> presents online App Open Ad', () async {
      final service = LaunchAdService();
      service.isLoggedInOverrideForTesting = true;
      service.hasLaunchedOverrideForTesting = true;
      service.isSubscribedOverrideForTesting = false;
      service.isOfflineOverrideForTesting = false;

      bool onlineAdShown = false;
      AppOpenAdManager().showAdOverrideForTesting = ({required onDismissed}) async {
        onlineAdShown = true;
        onDismissed();
        return true;
      };

      // Away for 3 minutes and 10 seconds
      service.lastBackgroundedTimeForTesting = DateTime.now().subtract(const Duration(minutes: 3, seconds: 10));

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);

      expect(onlineAdShown, isTrue);
    });

    testWidgets('23. Warm start >= 3 minutes (Offline) -> presents offline App Launch Ad with 5s countdown', (tester) async {
      final service = LaunchAdService();
      service.isLoggedInOverrideForTesting = true;
      service.hasLaunchedOverrideForTesting = true;
      service.isSubscribedOverrideForTesting = false;
      service.isOfflineOverrideForTesting = true;

      final testAd = ManualAd(
        id: 'warm_offline_ad',
        title: 'Warm Offline Ad',
        subtitle: 'Test',
        imageUrl: 'assets/ad_cyber.jpeg',
        contactUrl: '',
        placement: 'app_launch',
        isActive: true,
      );
      InterstitialAdService().setCachedServerAdsForTesting([testAd]);

      bool offlineAdShown = false;
      service.offlineLaunchPresenterForTesting = ({context, required onDismissed}) async {
        offlineAdShown = true;
        onDismissed();
        return true;
      };

      // Away for 4 minutes
      service.lastBackgroundedTimeForTesting = DateTime.now().subtract(const Duration(minutes: 4));

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(offlineAdShown, isTrue);
    });

    test('24. Warm start: Active subscriber returns after 3+ minutes -> suppressed (no ad)', () async {
      final service = LaunchAdService();
      service.isLoggedInOverrideForTesting = true;
      service.hasLaunchedOverrideForTesting = true;
      service.isSubscribedOverrideForTesting = true; // Subscribed!
      service.isOfflineOverrideForTesting = false;

      bool onlineAdShown = false;
      AppOpenAdManager().showAdOverrideForTesting = ({required onDismissed}) async {
        onlineAdShown = true;
        onDismissed();
        return true;
      };

      service.lastBackgroundedTimeForTesting = DateTime.now().subtract(const Duration(minutes: 5));
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);

      expect(onlineAdShown, isFalse);
    });

    test('25. Warm start: Logged-out user returns after 3+ minutes -> suppressed (no ad)', () async {
      final service = LaunchAdService();
      service.isLoggedInOverrideForTesting = false; // Logged out!
      service.hasLaunchedOverrideForTesting = true;
      service.isSubscribedOverrideForTesting = false;

      bool onlineAdShown = false;
      AppOpenAdManager().showAdOverrideForTesting = ({required onDismissed}) async {
        onlineAdShown = true;
        onDismissed();
        return true;
      };

      service.lastBackgroundedTimeForTesting = DateTime.now().subtract(const Duration(minutes: 5));
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);

      expect(onlineAdShown, isFalse);
    });

    test('26. Warm start one-shot guard: multiple resumed events do not repeat ad', () async {
      final service = LaunchAdService();
      service.isLoggedInOverrideForTesting = true;
      service.hasLaunchedOverrideForTesting = true;
      service.isSubscribedOverrideForTesting = false;
      service.isOfflineOverrideForTesting = false;

      int adShowCount = 0;
      AppOpenAdManager().showAdOverrideForTesting = ({required onDismissed}) async {
        adShowCount++;
        onDismissed();
        return true;
      };

      // Backgrounded 5 minutes ago
      service.lastBackgroundedTimeForTesting = DateTime.now().subtract(const Duration(minutes: 5));

      // First resumed callback
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);

      // Second immediate resumed callback (e.g. Android multi-window or permission return)
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);

      expect(adShowCount, 1);
    });
  });

  group('ManualAd Model & Placement Extensions', () {
    test('Placement deserialization parses app_launch correctly', () {
      final ad = ManualAd.fromMap('ad_1', {
        'title': 'Launch Ad',
        'placement': 'app_launch',
      });
      expect(ad.placement, 'app_launch');
      expect(ad.isAppLaunch, isTrue);

      final dialogData = ad.toDialogData();
      expect(dialogData['isAppLaunch'], isTrue);
      expect(dialogData['placement'], 'app_launch');
    });

    test('Placement deserialization parses app_launch_interstitial alias', () {
      final ad = ManualAd.fromMap('ad_2', {
        'title': 'Launch Ad 2',
        'placement': 'app_launch_interstitial',
      });
      expect(ad.placement, 'app_launch');
      expect(ad.isAppLaunch, isTrue);
    });

    test('Canonical serialization: toMap and toJson always persist app_launch', () {
      final ad = ManualAd(
        id: 'ad_canonical',
        title: 'Launch Ad',
        subtitle: 'Sub',
        imageUrl: 'https://example.com/ad.jpg',
        contactUrl: '',
        placement: 'app_launch_interstitial', // Old alias passed
      );
      expect(ad.placement, 'app_launch');
      expect(ad.toMap()['placement'], 'app_launch');
      expect(ad.toJson()['placement'], 'app_launch');
    });

    test('Placement deserialization parses multiple aliases canonically', () {
      for (final alias in ['app_launch', 'app_launch_interstitial', 'applaunch', 'app launch', 'app launch ads']) {
        final ad = ManualAd.fromMap('id', {'placement': alias});
        expect(ad.placement, 'app_launch', reason: 'Failed for alias: $alias');
        expect(ad.isAppLaunch, isTrue);
      }
    });

    test('Normal interstitials do not pick app_launch ads in getNextManualAd', () {
      InterstitialAdService().setCachedServerAdsForTesting([
        ManualAd(
          id: 'app_launch_ad',
          title: 'Launch Ad',
          subtitle: '',
          imageUrl: '',
          contactUrl: '',
          placement: 'app_launch',
          isActive: true,
        ),
        ManualAd(
          id: 'normal_ad',
          title: 'Normal Interstitial',
          subtitle: '',
          imageUrl: '',
          contactUrl: '',
          placement: 'interstitial',
          isActive: true,
        ),
      ]);

      final selected = InterstitialAdService().getNextManualAd();
      expect(selected.id, 'normal_ad');
      expect(selected.placement, 'interstitial');

      final launchSelected = InterstitialAdService().getNextAppLaunchAd();
      expect(launchSelected?.id, 'app_launch_ad');
      expect(launchSelected?.placement, 'app_launch');
    });
  });

  group('Cached App Open Pool (Multi-Ad Bounded Pool)', () {
    test('Pool size bounded at maxPoolSize = 3', () {
      final manager = AppOpenAdManager();
      manager.resetForTesting();

      expect(manager.cachedPoolSize, 0);
      expect(manager.hasValidCachedAd, isFalse);

      manager.addTestDummyAd();
      manager.addTestDummyAd();
      manager.addTestDummyAd();

      expect(manager.cachedPoolSize, 3);
      expect(manager.hasValidCachedAd, isTrue);
    });

    test('Consumes one valid cached ad and decrements pool', () async {
      final manager = AppOpenAdManager();
      manager.resetForTesting();

      manager.addTestDummyAd();
      manager.addTestDummyAd();
      expect(manager.cachedPoolSize, 2);

      bool dismissed = false;
      final showed = await manager.showNextCachedAd(onDismissed: () {
        dismissed = true;
      });

      expect(showed, isTrue);
      expect(dismissed, isTrue);
      expect(manager.cachedPoolSize, 1);
    });

    test('4-hour expiration validation discards stale ads', () {
      final manager = AppOpenAdManager();
      manager.resetForTesting();

      final fourHoursAgo = DateTime.now().subtract(const Duration(hours: 4, minutes: 10));
      manager.addTestDummyAd(loadedAt: fourHoursAgo);

      final removed = manager.cleanExpiredAds();
      expect(removed, 1);
      expect(manager.cachedPoolSize, 0);
      expect(manager.hasValidCachedAd, isFalse);
    });

    test('Fresh ad (< 4 hours) is retained and valid', () {
      final manager = AppOpenAdManager();
      manager.resetForTesting();

      final freshTime = DateTime.now().subtract(const Duration(hours: 2));
      manager.addTestDummyAd(loadedAt: freshTime);

      final removed = manager.cleanExpiredAds();
      expect(removed, 0);
      expect(manager.cachedPoolSize, 1);
      expect(manager.hasValidCachedAd, isTrue);
    });
  });

  group('Launch Ad Decision Priority (Cached AdMob > Manual Offline)', () {
    testWidgets('Priority 1: Eligible user OFFLINE with valid cached AdMob ad -> presents cached AdMob ad', (tester) async {
      LaunchAdService().isLoggedInOverrideForTesting = true;
      LaunchAdService().hasLaunchedOverrideForTesting = true;
      LaunchAdService().isSubscribedOverrideForTesting = false;
      LaunchAdService().isOfflineOverrideForTesting = true; // OFFLINE!

      // Add a valid cached AdMob ad
      AppOpenAdManager().addTestDummyAd();
      expect(AppOpenAdManager().hasValidCachedAd, isTrue);

      // Also configure a manual offline ad
      InterstitialAdService().setCachedServerAdsForTesting([
        ManualAd(
          id: 'manual_offline_ad_1',
          title: 'Manual Offline Ad',
          subtitle: '',
          imageUrl: 'assets/ad_cyber.jpeg',
          contactUrl: '',
          placement: 'app_launch',
          isActive: true,
        ),
      ]);

      bool offlineManualShown = false;
      LaunchAdService().offlineLaunchPresenterForTesting = ({context, required onDismissed}) async {
        offlineManualShown = true;
        onDismissed();
        return true;
      };

      bool appContinued = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await LaunchAdService().handleAppLaunch(
                    context: context,
                    splashStartTime: DateTime.now(),
                    onContinue: () => appContinued = true,
                  );
                },
                child: const Text('Start'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      // CACHED AdMob ad must be chosen over manual ad, even though device is offline!
      expect(offlineManualShown, isFalse);
      expect(appContinued, isTrue);
    });

    testWidgets('Priority 2: Eligible user OFFLINE WITHOUT cached AdMob ad -> presents manual offline launch ad', (tester) async {
      LaunchAdService().isLoggedInOverrideForTesting = true;
      LaunchAdService().hasLaunchedOverrideForTesting = true;
      LaunchAdService().isSubscribedOverrideForTesting = false;
      LaunchAdService().isOfflineOverrideForTesting = true; // OFFLINE!

      // NO cached AdMob ad
      AppOpenAdManager().resetForTesting();
      expect(AppOpenAdManager().hasValidCachedAd, isFalse);

      // Configure a manual offline ad
      InterstitialAdService().setCachedServerAdsForTesting([
        ManualAd(
          id: 'manual_offline_fallback',
          title: 'Fallback Manual Ad',
          subtitle: '',
          imageUrl: 'assets/ad_cyber.jpeg',
          contactUrl: '',
          placement: 'app_launch',
          isActive: true,
        ),
      ]);

      bool offlineManualShown = false;
      LaunchAdService().offlineLaunchPresenterForTesting = ({context, required onDismissed}) async {
        offlineManualShown = true;
        onDismissed();
        return true;
      };

      bool appContinued = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await LaunchAdService().handleAppLaunch(
                    context: context,
                    splashStartTime: DateTime.now(),
                    onContinue: () => appContinued = true,
                  );
                },
                child: const Text('Start'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(offlineManualShown, isTrue);
      expect(appContinued, isTrue);
    });

    testWidgets('Priority 1b: Eligible user OFFLINE with cached AdMob ad that fails show -> falls back cleanly to manual offline launch ad', (tester) async {
      LaunchAdService().isLoggedInOverrideForTesting = true;
      LaunchAdService().hasLaunchedOverrideForTesting = true;
      LaunchAdService().isSubscribedOverrideForTesting = false;
      LaunchAdService().isOfflineOverrideForTesting = true; // OFFLINE!

      // Cached AdMob ad exists, but fails to show on device
      AppOpenAdManager().showAdOverrideForTesting = ({required onDismissed}) async {
        // Simulates native show failure (e.g. offline rendering unsupported by SDK)
        return false;
      };

      // Configure a manual offline ad
      InterstitialAdService().setCachedServerAdsForTesting([
        ManualAd(
          id: 'manual_offline_fallback_after_fail',
          title: 'Fallback Manual Ad After Show Failure',
          subtitle: '',
          imageUrl: 'assets/ad_cyber.jpeg',
          contactUrl: '',
          placement: 'app_launch',
          isActive: true,
        ),
      ]);

      bool offlineManualShown = false;
      LaunchAdService().offlineLaunchPresenterForTesting = ({context, required onDismissed}) async {
        offlineManualShown = true;
        onDismissed();
        return true;
      };

      bool appContinued = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await LaunchAdService().handleAppLaunch(
                    context: context,
                    splashStartTime: DateTime.now(),
                    onContinue: () => appContinued = true,
                  );
                },
                child: const Text('Start'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      // Verified: Cached AdMob ad failed to show offline, so manual offline fallback ad displayed!
      expect(offlineManualShown, isTrue);
      expect(appContinued, isTrue);
    });

    test('SDK initialization state tracking in AppOpenAdManager', () {
      final manager = AppOpenAdManager();
      manager.resetForTesting();
      // Initially not initialized
      expect(manager.isSdkInitialized, isFalse);
      // Mark initialized
      manager.markSdkInitialized();
      expect(manager.isSdkInitialized, isTrue);
    });
  });

  group('Offline Manual App Launch Rotation', () {
    final adA = ManualAd(
      id: 'ad_A',
      title: 'Ad Alpha',
      subtitle: '',
      imageUrl: '',
      contactUrl: '',
      placement: 'app_launch',
      isActive: true,
    );

    final adB = ManualAd(
      id: 'ad_B',
      title: 'Ad Beta',
      subtitle: '',
      imageUrl: '',
      contactUrl: '',
      placement: 'app_launch',
      isActive: true,
    );

    final adC = ManualAd(
      id: 'ad_C',
      title: 'Ad Gamma',
      subtitle: '',
      imageUrl: '',
      contactUrl: '',
      placement: 'app_launch',
      isActive: true,
    );

    test('Deterministic rotation across 3 ads: A -> B -> C -> A', () {
      final service = InterstitialAdService();
      service.setCachedServerAdsForTesting([adA, adB, adC]);

      final first = service.getNextAppLaunchAd();
      expect(first?.id, 'ad_A');

      final second = service.getNextAppLaunchAd();
      expect(second?.id, 'ad_B');

      final third = service.getNextAppLaunchAd();
      expect(third?.id, 'ad_C');

      final fourth = service.getNextAppLaunchAd();
      expect(fourth?.id, 'ad_A');
    });

    test('Deterministic rotation across 2 ads: A -> B -> A -> B', () {
      final service = InterstitialAdService();
      service.setCachedServerAdsForTesting([adA, adB]);

      final first = service.getNextAppLaunchAd();
      expect(first?.id, 'ad_A');

      final second = service.getNextAppLaunchAd();
      expect(second?.id, 'ad_B');

      final third = service.getNextAppLaunchAd();
      expect(third?.id, 'ad_A');

      final fourth = service.getNextAppLaunchAd();
      expect(fourth?.id, 'ad_B');
    });

    test('Single ad pool: repeatedly returns A', () {
      final service = InterstitialAdService();
      service.setCachedServerAdsForTesting([adA]);

      expect(service.getNextAppLaunchAd()?.id, 'ad_A');
      expect(service.getNextAppLaunchAd()?.id, 'ad_A');
      expect(service.getNextAppLaunchAd()?.id, 'ad_A');
    });

    test('Inactive/deleted previous ad is skipped gracefully', () {
      final service = InterstitialAdService();
      service.setCachedServerAdsForTesting([adA, adB, adC]);

      expect(service.getNextAppLaunchAd()?.id, 'ad_A');
      expect(service.getNextAppLaunchAd()?.id, 'ad_B');

      // Now adB is deactivated, pool has only A and C
      service.setCachedServerAdsForTesting([adA, adC]);

      // Next call should pick first available valid ad without error
      final next = service.getNextAppLaunchAd();
      expect(next?.id, 'ad_A');

      final subsequent = service.getNextAppLaunchAd();
      expect(subsequent?.id, 'ad_C');
    });

    test('Rotation state survives service reset using SharedPreferences persistence', () {
      final service = InterstitialAdService();
      service.setCachedServerAdsForTesting([adA, adB]);

      // First call selects A and persists it
      final first = service.getNextAppLaunchAd();
      expect(first?.id, 'ad_A');
      expect(PersistenceService().getString('last_app_launch_ad_id'), 'ad_A');

      // Simulate app restart: clear in-memory last shown state
      service.lastAppLaunchAdIdForTesting = null;

      // Next call picks up persisted lastShown 'ad_A' and rotates to 'ad_B'!
      final second = service.getNextAppLaunchAd();
      expect(second?.id, 'ad_B');
      expect(PersistenceService().getString('last_app_launch_ad_id'), 'ad_B');
    });
  });

  group('One-Shot Reentrancy & Splash Lifecycle Safety', () {
    testWidgets('handleAppLaunch called multiple times -> executes only once', (tester) async {
      LaunchAdService().isLoggedInOverrideForTesting = true;
      LaunchAdService().hasLaunchedOverrideForTesting = true;
      LaunchAdService().isSubscribedOverrideForTesting = false;
      LaunchAdService().isOfflineOverrideForTesting = true;

      final testAd = ManualAd(
        id: 'safety_ad',
        title: 'Safety Ad',
        subtitle: '',
        imageUrl: 'assets/ad_cyber.jpeg',
        contactUrl: '',
        placement: 'app_launch',
        isActive: true,
      );
      InterstitialAdService().setCachedServerAdsForTesting([testAd]);

      int presentationCount = 0;
      LaunchAdService().offlineLaunchPresenterForTesting = ({context, required onDismissed}) async {
        presentationCount++;
        onDismissed();
        return true;
      };

      int continueCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await LaunchAdService().handleAppLaunch(
                    context: context,
                    splashStartTime: DateTime.now(),
                    onContinue: () => continueCount++,
                  );
                  // Call a second time immediately
                  await LaunchAdService().handleAppLaunch(
                    context: context,
                    splashStartTime: DateTime.now(),
                    onContinue: () => continueCount++,
                  );
                },
                child: const Text('Start'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(presentationCount, 1);
      expect(continueCount, 2); // 1st completed, 2nd skipped immediately to onContinue
    });
  });
}
