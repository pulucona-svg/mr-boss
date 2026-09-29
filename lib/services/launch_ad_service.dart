// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'persistence_service.dart';
import 'subscription_service.dart';
import 'connectivity_service.dart';
import 'interstitial_ad_service.dart';
import 'app_open_ad_manager.dart';
import '../models/manual_ad.dart';
import '../widgets/manual_interstitial_ad_dialog.dart';

/// Single authoritative coordinator for the App Launch Ads system.
/// 
/// Enforces all eligibility criteria, parallel preloaded ad pool coordination,
/// offline manual launch ads with 5-second countdowns and X state,
/// warm-start (3-minute threshold), and clean non-blocking startup continuation.
class LaunchAdService with WidgetsBindingObserver {
  static final LaunchAdService _instance = LaunchAdService._internal();
  factory LaunchAdService() => _instance;
  LaunchAdService._internal();

  /// Key used in PersistenceService to mark if the app has ever completed startup.
  static const String kHasLaunchedAppKey = 'has_launched_app';

  /// Tracks whether a launch ad has already executed during this cold start session.
  bool _hasExecutedLaunchFlow = false;
  bool get hasExecutedLaunchFlow => _hasExecutedLaunchFlow;

  /// Guard to prevent reentrant launch-ad evaluations.
  bool _isEvaluatingLaunchAd = false;

  /// Timestamp when the app was last backgrounded or became inactive.
  DateTime? _lastBackgroundedTime;
  DateTime? get lastBackgroundedTimeForTesting => _lastBackgroundedTime;
  @visibleForTesting
  set lastBackgroundedTimeForTesting(DateTime? time) => _lastBackgroundedTime = time;

  /// Guard flag to prevent duplicate concurrent warm starts.
  bool _isExecutingWarmStart = false;
  bool get isExecutingWarmStart => _isExecutingWarmStart;

  /// Warm start away-time threshold: 3 minutes.
  static const Duration defaultWarmStartThreshold = Duration(minutes: 3);
  @visibleForTesting
  Duration? warmStartThresholdOverrideForTesting;

  bool _isObserverRegistered = false;

  // ==========================================
  // TESTING HOOKS & OVERRIDES
  // ==========================================
  @visibleForTesting
  bool? isLoggedInOverrideForTesting;

  @visibleForTesting
  bool? hasLaunchedOverrideForTesting;

  @visibleForTesting
  bool? isSubscribedOverrideForTesting;

  @visibleForTesting
  bool? isOfflineOverrideForTesting;

  @visibleForTesting
  bool skipDelayForTesting = false;

  @visibleForTesting
  Future<bool> Function({BuildContext? context, required VoidCallback onDismissed})?
      offlineLaunchPresenterForTesting;

  /// Registers lifecycle observation for warm-start handling.
  void initialize() {
    if (!_isObserverRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _isObserverRegistered = true;
      if (kDebugMode) {
        debugPrint('LaunchAdService: [INITIALIZE] Registered lifecycle observer for warm-start tracking.');
      }
    }
  }

  void dispose() {
    if (_isObserverRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _isObserverRegistered = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _lastBackgroundedTime ??= DateTime.now();
      if (kDebugMode) {
        debugPrint('LaunchAdService: [LIFECYCLE] App backgrounded at $_lastBackgroundedTime.');
      }
    } else if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _lastBackgroundedTime;
      _lastBackgroundedTime = null; // One-shot consumption
      if (backgroundedAt == null) return;

      final elapsed = DateTime.now().difference(backgroundedAt);
      final threshold = warmStartThresholdOverrideForTesting ?? defaultWarmStartThreshold;
      if (elapsed < threshold) {
        if (kDebugMode) {
          debugPrint('LaunchAdService: [WARM_START_SKIP] Away for ${elapsed.inSeconds}s (< ${threshold.inSeconds}s). Normal resume without ad.');
        }
        return;
      }

      if (kDebugMode) {
        debugPrint('LaunchAdService: [WARM_START_TRIGGER] Away for ${elapsed.inSeconds}s (>= ${threshold.inSeconds}s). Evaluating warm start launch ad...');
      }
      handleWarmStart();
    }
  }

  /// Evaluates whether the current user is strictly eligible for an App Launch Ad.
  /// 
  /// Requires ALL of the following:
  /// 1. User is logged in.
  /// 2. User has previously launched the app (NOT first-ever launch).
  /// 3. User does NOT currently have an active subscription.
  /// 4. No other full-screen ad/modal is currently displaying.
  bool isEligibleForLaunchAd() {
    // 1. Logged in check
    final bool isLoggedIn = isLoggedInOverrideForTesting ??
        (PersistenceService().getSessionUserId() != null &&
            PersistenceService().getSessionUserId()!.isNotEmpty);
    if (!isLoggedIn) {
      if (kDebugMode) debugPrint('LaunchAdService: [INELIGIBLE] User is not logged in.');
      return false;
    }

    // 2. First-ever launch check
    final bool hasLaunched = hasLaunchedOverrideForTesting ??
        (PersistenceService().getBool(kHasLaunchedAppKey) ?? false);
    if (!hasLaunched) {
      if (kDebugMode) debugPrint('LaunchAdService: [INELIGIBLE] First-ever app launch.');
      return false;
    }

    // 3. Subscription check
    final bool isSubscribed = isSubscribedOverrideForTesting ??
        SubscriptionService().isSubscribed;
    if (isSubscribed) {
      if (kDebugMode) debugPrint('LaunchAdService: [INELIGIBLE] User has an active subscription.');
      return false;
    }

    // 4. Fullscreen presentation guard
    if (InterstitialAdService.isFullScreenAdShowing) {
      if (kDebugMode) debugPrint('LaunchAdService: [INELIGIBLE] Another fullscreen presentation is active.');
      return false;
    }

    if (kDebugMode) debugPrint('LaunchAdService: [ELIGIBLE] User is eligible for App Launch Ad.');
    return true;
  }

  /// Initiates parallel preloading of the online App Open Ad pool.
  void startParallelPreload() {
    final bool isOffline = isOfflineOverrideForTesting ?? ConnectivityService().isOffline;
    if (!isOffline) {
      if (kDebugMode) {
        debugPrint('LaunchAdService: [PRELOAD] Initiating parallel App Open Ad load at startup...');
      }
      AppOpenAdManager().replenishPool();
    }
  }

  /// Authoritative coordinator for the cold start app launch advertising flow.
  /// 
  /// Priority:
  /// 1. Valid cached AdMob App Open Ads (usable ONLINE and OFFLINE).
  /// 2. If online: bounded AdMob load attempt (1200ms). If not ready, continue without ad.
  /// 3. If offline: manual offline App Launch Ad with 5s countdown + X close control.
  /// 
  /// Guaranteed single execution: completion of the ad transitions directly to the app
  /// without restarting splash or re-evaluating startup.
  Future<void> handleAppLaunch({
    required BuildContext context,
    required DateTime splashStartTime,
    required VoidCallback onContinue,
  }) async {
    // 1. One-shot reentrancy guard
    if (_hasExecutedLaunchFlow || _isEvaluatingLaunchAd) {
      if (kDebugMode) debugPrint('LaunchAdService: [SKIP] Launch flow already executed during this session.');
      _safeRemoveNativeSplash();
      onContinue();
      return;
    }
    _isEvaluatingLaunchAd = true;
    _hasExecutedLaunchFlow = true;

    bool continueInvoked = false;
    void safeContinue() {
      if (continueInvoked) return;
      continueInvoked = true;
      _isEvaluatingLaunchAd = false;
      onContinue();
    }

    if (kDebugMode) debugPrint('[AppOpenDebug] launchEvaluationStarted=true');

    // 2. Eligibility evaluation
    final eligible = isEligibleForLaunchAd();
    if (kDebugMode) {
      debugPrint('[AppLaunch] eligible=$eligible');
      debugPrint('[AppOpenDebug] eligible=$eligible');
      debugPrint('[AppOpenDebug] cachedPool=${AppOpenAdManager().cachedPoolSize}');
    }
    if (!eligible) {
      if (kDebugMode) {
        debugPrint('LaunchAdService: [STARTUP] User ineligible for launch ad. Proceeding with standard flow.');
        debugPrint('[AppOpenDebug] continuingWithoutAppOpen=true');
        debugPrint('[AppOpenDebug] reason=ineligible_user');
      }
      _safeRemoveNativeSplash();
      _markLaunchCompleted();
      safeContinue();
      return;
    }

    // 3. Splash timing: ~1.5s for eligible returning non-subscribers
    if (!skipDelayForTesting) {
      final elapsed = DateTime.now().difference(splashStartTime);
      const targetDuration = Duration(milliseconds: 1500);
      if (elapsed < targetDuration) {
        final remaining = targetDuration - elapsed;
        if (kDebugMode) {
          debugPrint('LaunchAdService: [SPLASH_TIMING] Waiting ${remaining.inMilliseconds}ms for eligible 1.5s splash timing...');
        }
        await Future.delayed(remaining);
      }
    }

    // Re-verify eligibility after delay
    if (!isEligibleForLaunchAd()) {
      if (kDebugMode) {
        debugPrint('[AppOpenDebug] continuingWithoutAppOpen=true');
        debugPrint('[AppOpenDebug] reason=ineligible_user');
      }
      _safeRemoveNativeSplash();
      _markLaunchCompleted();
      safeContinue();
      return;
    }

    // 4. Remove expired cached App Open Ads & log status
    final removedExpired = AppOpenAdManager().cleanExpiredAds();
    if (kDebugMode) debugPrint('[AppLaunch] removedExpired=$removedExpired');
    final cachedPool = AppOpenAdManager().cachedPoolSize;
    if (kDebugMode) debugPrint('[AppLaunch] cachedAdmobPool=$cachedPool');

    // 5. PRIORITY 1: If valid cached App Open Ad exists (usable ONLINE and OFFLINE)
    if (AppOpenAdManager().hasValidCachedAd) {
      if (kDebugMode) {
        debugPrint('[AppLaunch] usingCachedAdmob=true');
        final age = AppOpenAdManager().peekNextAdAge();
        debugPrint('[AppLaunch] cachedAdAge=${age?.inSeconds}s');
      }

      _safeRemoveNativeSplash();

      final Completer<void> adDismissedCompleter = Completer<void>();

      final showed = await AppOpenAdManager().showNextCachedAd(
        onDismissed: () {
          if (kDebugMode) debugPrint('[AppLaunch] cachedAdmobConsumed=true');
          InterstitialAdService().resetSessionTimer();
          _markLaunchCompleted();
          safeContinue();
          if (!adDismissedCompleter.isCompleted) adDismissedCompleter.complete();
        },
      );

      if (showed) {
        if (kDebugMode) debugPrint('[AppLaunch] replenishingPool=true');
        AppOpenAdManager().replenishPool();
        await adDismissedCompleter.future;
        return;
      } else {
        if (kDebugMode) {
          debugPrint('[AppLaunch] cached AdMob ad failed to show.');
          debugPrint('[AppOpenDebug] continuingWithoutAppOpen=true');
          debugPrint('[AppOpenDebug] reason=cached_ad_show_failed');
        }
      }
    }

    // If we reach here, either no cached AdMob ad was available OR it failed to show
    final bool isOffline = isOfflineOverrideForTesting ?? ConnectivityService().isOffline;

    // 6. ONLINE PATH: Bounded online wait (2500ms for network creative fetch)
    if (!isOffline) {
      if (kDebugMode) {
        debugPrint('[AppLaunch] usingCachedAdmob=false');
        debugPrint('[AppLaunch] online=true');
        debugPrint('[AppLaunch] boundedLoadStarted=true');
        debugPrint('[AppOpenDebug] waitingForAd=true');
      }

      bool ready = await AppOpenAdManager().waitForAd(timeout: const Duration(milliseconds: 2500));

      if (ready && AppOpenAdManager().hasValidCachedAd) {
        if (kDebugMode) debugPrint('[AppLaunch] boundedLoadResult=ready');
        _safeRemoveNativeSplash();

        final Completer<void> adDismissedCompleter = Completer<void>();

        final showed = await AppOpenAdManager().showNextCachedAd(
          onDismissed: () {
            if (kDebugMode) debugPrint('[AppLaunch] cachedAdmobConsumed=true');
            InterstitialAdService().resetSessionTimer();
            _markLaunchCompleted();
            safeContinue();
            if (!adDismissedCompleter.isCompleted) adDismissedCompleter.complete();
          },
        );

        if (showed) {
          if (kDebugMode) debugPrint('[AppLaunch] replenishingPool=true');
          AppOpenAdManager().replenishPool();
          await adDismissedCompleter.future;
          return;
        }
      }

      if (kDebugMode) {
        debugPrint('[AppLaunch] boundedLoadResult=timeout');
        debugPrint('[AppLaunch] continuingWithoutAd=true');
        debugPrint('[AppOpenDebug] continuingWithoutAppOpen=true');
        debugPrint('[AppOpenDebug] reason=startup_timeout');
      }
      _safeRemoveNativeSplash();
      _markLaunchCompleted();
      safeContinue();
      AppOpenAdManager().replenishPool();
      return;
    }

    // 7. OFFLINE PATH: Manual offline App Launch Ad
    if (kDebugMode) {
      debugPrint('[AppLaunch] online=false');
      debugPrint('[AppLaunch] cachedAdmobAvailable=false');
      debugPrint('[AppLaunch] usingManualOfflineAppLaunch=true');
      debugPrint('[AppOpenDebug] continuingWithoutAppOpen=true');
      debugPrint('[AppOpenDebug] reason=device_offline_fallback');
    }

    final launchAd = InterstitialAdService().getNextAppLaunchAd();

    if (launchAd != null) {
      if (kDebugMode) debugPrint('[AppLaunch] manualAdId=${launchAd.id}');
      _safeRemoveNativeSplash();

      if (!context.mounted) {
        _markLaunchCompleted();
        safeContinue();
        return;
      }

      if (offlineLaunchPresenterForTesting != null) {
        await offlineLaunchPresenterForTesting!(
          context: context,
          onDismissed: () {
            if (kDebugMode) {
              debugPrint('[AppLaunch] manualAdCompleted=true');
              debugPrint('[AppLaunch] continuingToApp=true');
            }
            InterstitialAdService().resetSessionTimer();
            _markLaunchCompleted();
            safeContinue();
          },
        );
        return;
      }

      await _showOfflineLaunchDialog(
        context: context,
        ad: launchAd,
        onDismissed: () {
          if (kDebugMode) {
            debugPrint('[AppLaunch] manualAdCompleted=true');
            debugPrint('[AppLaunch] continuingToApp=true');
          }
          InterstitialAdService().resetSessionTimer();
          _markLaunchCompleted();
          safeContinue();
        },
      );
      return;
    } else {
      if (kDebugMode) {
        debugPrint('[AppLaunch] manualAdId=none');
        debugPrint('[AppLaunch] continuingToApp=true');
      }
      _safeRemoveNativeSplash();
      _markLaunchCompleted();
      safeContinue();
      return;
    }
  }

  /// Handles warm start / resume after the app was backgrounded for >= 3 minutes.
  Future<void> handleWarmStart() async {
    if (_isExecutingWarmStart) {
      if (kDebugMode) debugPrint('LaunchAdService: [WARM_START_SKIP] Warm start already in progress.');
      return;
    }
    if (InterstitialAdService.isFullScreenAdShowing) {
      if (kDebugMode) {
        debugPrint('LaunchAdService: [WARM_START_SKIP] Another fullscreen ad is active.');
        debugPrint('[AppOpenDebug] continuingWithoutAppOpen=true');
        debugPrint('[AppOpenDebug] reason=another_fullscreen_ad_active');
      }
      return;
    }
    if (!isEligibleForLaunchAd()) {
      if (kDebugMode) {
        debugPrint('LaunchAdService: [WARM_START_INELIGIBLE] User ineligible for warm start launch ad (subscriber, logged out, or first launch).');
        debugPrint('[AppOpenDebug] continuingWithoutAppOpen=true');
        debugPrint('[AppOpenDebug] reason=ineligible_user');
      }
      return;
    }

    _isExecutingWarmStart = true;

    try {
      final removedExpired = AppOpenAdManager().cleanExpiredAds();
      if (kDebugMode) debugPrint('[AppLaunch] removedExpired=$removedExpired');

      // PRIORITY 1: Cached AdMob App Open Ad (online OR offline)
      if (AppOpenAdManager().hasValidCachedAd) {
        if (kDebugMode) {
          debugPrint('LaunchAdService: [WARM_START_CACHED] Valid cached App Open Ad found. Presenting on warm resume...');
        }
        final showed = await AppOpenAdManager().showNextCachedAd(
          onDismissed: () {
            if (kDebugMode) debugPrint('LaunchAdService: [WARM_START_DISMISSED] Warm start ad dismissed.');
            InterstitialAdService().resetSessionTimer();
            _isExecutingWarmStart = false;
          },
        );

        if (showed) {
          AppOpenAdManager().replenishPool();
          return;
        } else {
          if (kDebugMode) {
            debugPrint('[AppOpenDebug] continuingWithoutAppOpen=true');
            debugPrint('[AppOpenDebug] reason=cached_ad_show_failed');
          }
        }
      }

      final bool isOffline = isOfflineOverrideForTesting ?? ConnectivityService().isOffline;

      // PRIORITY 2 (Online without cache): bounded load
      if (!isOffline) {
        if (kDebugMode) {
          debugPrint('LaunchAdService: [WARM_START_ONLINE] Checking online App Open Ad...');
          debugPrint('[AppOpenDebug] waitingForAd=true');
        }
        bool ready = await AppOpenAdManager().waitForAd(timeout: const Duration(milliseconds: 1500));

        if (ready && AppOpenAdManager().hasValidCachedAd) {
          if (kDebugMode) debugPrint('LaunchAdService: [WARM_START_SHOW_ONLINE] Presenting App Open Ad on warm resume...');
          final showed = await AppOpenAdManager().showNextCachedAd(
            onDismissed: () {
              InterstitialAdService().resetSessionTimer();
              _isExecutingWarmStart = false;
            },
          );
          if (showed) {
            AppOpenAdManager().replenishPool();
            return;
          }
        }

        if (kDebugMode) {
          debugPrint('LaunchAdService: [WARM_START_ONLINE_UNAVAILABLE] App Open Ad not ready on warm resume. Continuing app.');
          debugPrint('[AppOpenDebug] continuingWithoutAppOpen=true');
          debugPrint('[AppOpenDebug] reason=startup_timeout');
        }
        _isExecutingWarmStart = false;
        AppOpenAdManager().replenishPool();
        return;
      }

      // PRIORITY 2 (Offline without cache): manual offline App Launch Ad
      if (kDebugMode) {
        debugPrint('LaunchAdService: [WARM_START_OFFLINE] Device offline on warm resume without cached AdMob ad. Checking manual offline ads...');
        debugPrint('[AppOpenDebug] continuingWithoutAppOpen=true');
        debugPrint('[AppOpenDebug] reason=device_offline_fallback');
      }
      final launchAd = InterstitialAdService().getNextAppLaunchAd();
      if (launchAd != null) {
        final navContext = InterstitialAdService.navigatorKey.currentContext;
        if (offlineLaunchPresenterForTesting != null) {
          await offlineLaunchPresenterForTesting!(
            context: navContext,
            onDismissed: () {
              if (kDebugMode) debugPrint('LaunchAdService: [WARM_START_OFFLINE_DISMISSED] Offline warm start ad dismissed.');
              InterstitialAdService().resetSessionTimer();
              _isExecutingWarmStart = false;
            },
          );
          return;
        }

        if (navContext != null && navContext.mounted) {
          await _showOfflineLaunchDialog(
            context: navContext,
            ad: launchAd,
            onDismissed: () {
              if (kDebugMode) debugPrint('LaunchAdService: [WARM_START_OFFLINE_DISMISSED] Offline warm start ad dismissed.');
              InterstitialAdService().resetSessionTimer();
              _isExecutingWarmStart = false;
            },
          );
          return;
        } else {
          _isExecutingWarmStart = false;
          return;
        }
      } else {
        if (kDebugMode) debugPrint('LaunchAdService: [WARM_START_OFFLINE_NO_AD] No cached offline launch ad.');
        _isExecutingWarmStart = false;
        return;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LaunchAdService: [WARM_START_ERROR] Error in warm start flow: $e');
      _isExecutingWarmStart = false;
    }
  }

  /// Displays the offline App Launch Ad dialog with a 5-second auto-closing countdown and X state.
  Future<void> _showOfflineLaunchDialog({
    required BuildContext context,
    required ManualAd ad,
    required VoidCallback onDismissed,
  }) async {
    InterstitialAdService.isFullScreenAdShowing = true;
    final Completer<void> completer = Completer<void>();

    try {
      await showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.90),
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (dialogContext, anim1, anim2) {
          return ManualInterstitialAdDialog(
            adData: ad.toDialogData(),
            isAppLaunch: true,
            onDismissed: () {
              if (!completer.isCompleted) completer.complete();
            },
          );
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('LaunchAdService: [OFFLINE_DIALOG_ERROR] Error showing offline launch dialog: $e');
      }
    } finally {
      InterstitialAdService.isFullScreenAdShowing = false;
      if (!completer.isCompleted) completer.complete();
    }

    await completer.future;
    onDismissed();
  }

  void _safeRemoveNativeSplash() {
    try {
      FlutterNativeSplash.remove();
    } catch (_) {}
  }

  void _markLaunchCompleted() {
    PersistenceService().setBool(kHasLaunchedAppKey, true);
  }

  @visibleForTesting
  void resetForTesting() {
    _hasExecutedLaunchFlow = false;
    _isEvaluatingLaunchAd = false;
    _lastBackgroundedTime = null;
    _isExecutingWarmStart = false;
    warmStartThresholdOverrideForTesting = null;
    isLoggedInOverrideForTesting = null;
    hasLaunchedOverrideForTesting = null;
    isSubscribedOverrideForTesting = null;
    isOfflineOverrideForTesting = null;
    skipDelayForTesting = false;
    offlineLaunchPresenterForTesting = null;
  }
}
