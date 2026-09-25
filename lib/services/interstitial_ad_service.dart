import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'connectivity_service.dart';
import 'subscription_service.dart';
import '../widgets/manual_interstitial_ad_dialog.dart';

class InterstitialAdService with WidgetsBindingObserver {
  static final InterstitialAdService _instance = InterstitialAdService._internal();
  factory InterstitialAdService() => _instance;
  InterstitialAdService._internal();

  /// Global navigator key allowing the service to present full-screen dialogs
  /// (e.g. offline manual ads) from any active screen in the app.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Official Google Mobile Ads test interstitial ad unit ID for Android.
  static const String testAdUnitId = 'ca-app-pub-3940256099942544/1033173712';

  /// Default active session interval: exactly 15 minutes.
  static const Duration defaultSessionInterval = Duration(minutes: 15);

  /// Configurable active session interval (default: 15 minutes).
  Duration _sessionInterval = defaultSessionInterval;
  Duration get sessionInterval => _sessionInterval;

  @visibleForTesting
  set sessionIntervalForTesting(Duration duration) {
    _sessionInterval = duration;
    debugPrint('InterstitialAdService: [TESTING_CONFIG] Session interval set to ${duration.inSeconds} seconds.');
  }

  /// Global guard to prevent simultaneous full-screen ad presentations
  /// (e.g. rewarded ad vs interstitial ad vs purchase modal).
  static bool isFullScreenAdShowing = false;

  InterstitialAd? _interstitialAd;
  bool _isLoading = false;
  bool _isEligible = false;
  int _activeSecondsInCurrentInterval = 0;
  Timer? _activeTimer;
  bool _isInitialized = false;

  bool get isEligible => _isEligible;
  int get activeSecondsInCurrentInterval => _activeSecondsInCurrentInterval;
  bool get isAdLoaded => _interstitialAd != null;

  @visibleForTesting
  set isEligibleForTesting(bool value) {
    _isEligible = value;
  }

  @visibleForTesting
  set interstitialAdForTesting(InterstitialAd? ad) {
    _interstitialAd = ad;
  }

  /// Hook for overriding the subscription check during tests without requiring Firebase.
  @visibleForTesting
  bool Function()? isSubscribedOverrideForTesting;

  /// Hook for overriding the offline check during tests.
  @visibleForTesting
  bool Function()? isOfflineOverrideForTesting;

  /// Hook to skip native ad platform loading during unit tests.
  @visibleForTesting
  bool skipAdLoadingForTesting = false;

  /// Hook to intercept offline manual ad presentation in unit tests.
  @visibleForTesting
  Future<bool> Function()? offlineManualAdPresenterForTesting;

  /// Initializes the service, binds app lifecycle observation, starts the session timer,
  /// and preloads the initial Google test interstitial ad.
  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    _loadInterstitialAd();

    debugPrint('InterstitialAdService: [INTERSTITIAL_SESSION_STARTED] Active session timer started. Interval: ${_sessionInterval.inMinutes} minutes (${_sessionInterval.inSeconds}s). Ad Unit: $testAdUnitId');
  }

  /// Starts or resumes the active foreground session timer.
  void _startTimer() {
    _activeTimer?.cancel();
    _activeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _activeSecondsInCurrentInterval++;

      // Log progress periodically every minute (or on test intervals <= 60s every 10s)
      if (_activeSecondsInCurrentInterval % 60 == 0 ||
          (_sessionInterval.inSeconds <= 60 && _activeSecondsInCurrentInterval % 10 == 0)) {
        debugPrint('InterstitialAdService: [INTERSTITIAL_TIMER_TICK] Elapsed active session time: ${_activeSecondsInCurrentInterval}s / ${_sessionInterval.inSeconds}s (eligible: $_isEligible)');
      }

      if (_activeSecondsInCurrentInterval >= _sessionInterval.inSeconds && !_isEligible) {
        _isEligible = true;
        debugPrint('InterstitialAdService: [INTERSTITIAL_ELIGIBLE] Active session elapsed ${_sessionInterval.inMinutes} minutes. Interstitial is now eligible.');

        // Automatically attempt to show ad even if the user is reading an article or browsing!
        maybeShow(trigger: 'timer_interval_reached');
      }
    });
  }

  /// Pauses the active session timer when app is in background.
  void _stopTimer() {
    _activeTimer?.cancel();
    _activeTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('InterstitialAdService: [LIFECYCLE] App resumed - resuming active session timer from ${_activeSecondsInCurrentInterval}s.');
      _startTimer();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      debugPrint('InterstitialAdService: [LIFECYCLE] App paused/backgrounded - pausing active session timer at ${_activeSecondsInCurrentInterval}s (zero background accumulation).');
      _stopTimer();
    }
  }

  /// Preloads an AdMob interstitial ad.
  void _loadInterstitialAd() {
    if (skipAdLoadingForTesting) return;
    if (_isLoading || _interstitialAd != null) return;
    _isLoading = true;

    debugPrint('InterstitialAdService: [INTERSTITIAL_LOADING] Preloading Google test interstitial ad ($testAdUnitId)...');

    InterstitialAd.load(
      adUnitId: testAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isLoading = false;
          debugPrint('InterstitialAdService: [INTERSTITIAL_LOADED] AdMob test interstitial ad loaded successfully. Unit ID: $testAdUnitId');

          // If session became eligible while waiting for ad to load, show it now
          if (_isEligible && !isFullScreenAdShowing) {
            maybeShow(trigger: 'ad_loaded_while_eligible');
          }
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
          _isLoading = false;
          debugPrint('InterstitialAdService: [INTERSTITIAL_LOAD_FAILED] AdMob test interstitial failed to load: ${error.message} (code: ${error.code})');
          // Retry after a safe non-aggressive delay
          Future.delayed(const Duration(seconds: 30), () {
            if (_interstitialAd == null && !_isLoading) {
              _loadInterstitialAd();
            }
          });
        },
      ),
    );
  }

  /// Attempts to display an interstitial ad on a transition point (e.g. tab switch, article exit).
  Future<bool> maybeShowOnTransition({required String transitionPoint}) async {
    return maybeShow(trigger: transitionPoint);
  }

  /// Attempts to display an interstitial ad.
  /// - Can run anywhere including when user is reading an article or on transition.
  /// - When online, displays Google AdMob Interstitial.
  /// - When offline (or if AdMob is unavailable), displays bundled offline/manual ad.
  /// - Paid subscribers NEVER receive any ads.
  /// Returns true if an ad was displayed, false otherwise.
  Future<bool> maybeShow({required String trigger}) async {
    debugPrint('InterstitialAdService: [INTERSTITIAL_CHECK] Evaluating ad display (trigger: "$trigger")');

    // 1. Subscription check: active paid subscribers NEVER receive interstitial ads
    final bool isSubscribed = isSubscribedOverrideForTesting != null
        ? isSubscribedOverrideForTesting!()
        : SubscriptionService().isSubscribed;
    debugPrint('InterstitialAdService: [INTERSTITIAL_CHECK] Subscription check: isSubscribed=$isSubscribed');
    if (isSubscribed) {
      debugPrint('InterstitialAdService: [INTERSTITIAL_SKIPPED] Skipped: User has an active paid subscription/package.');
      return false;
    }

    // 2. Guard against simultaneous full-screen ad presentation
    if (isFullScreenAdShowing) {
      debugPrint('InterstitialAdService: [INTERSTITIAL_SKIPPED] Skipped: Another full-screen ad/modal is currently being displayed.');
      return false;
    }

    // 3. Session interval eligibility check
    if (!_isEligible && _activeSecondsInCurrentInterval < _sessionInterval.inSeconds) {
      debugPrint('InterstitialAdService: [INTERSTITIAL_SKIPPED] Skipped: Interval not yet reached (${_activeSecondsInCurrentInterval}s / ${_sessionInterval.inSeconds}s).');
      return false;
    }

    // 4. Connectivity check
    final bool isOffline = isOfflineOverrideForTesting != null
        ? isOfflineOverrideForTesting!()
        : ConnectivityService().isOffline;
    debugPrint('InterstitialAdService: [INTERSTITIAL_CHECK] Connectivity check: isOffline=$isOffline');

    // If offline: display the bundled offline/manual ad
    if (isOffline) {
      debugPrint('InterstitialAdService: [INTERSTITIAL_OFFLINE] Device is offline. Displaying offline manual ad.');
      if (offlineManualAdPresenterForTesting != null) {
        isFullScreenAdShowing = true;
        final res = await offlineManualAdPresenterForTesting!();
        isFullScreenAdShowing = false;
        _activeSecondsInCurrentInterval = 0;
        _isEligible = false;
        return res;
      }
      return await _showOfflineManualAd(trigger: trigger);
    }

    // If online: display AdMob interstitial if loaded
    if (_interstitialAd != null) {
      return await _showAdMobInterstitial(trigger: trigger);
    }

    // If online but AdMob ad is not ready, display the offline/manual ad as a reliable fallback
    debugPrint('InterstitialAdService: [INTERSTITIAL_FALLBACK] AdMob ad not loaded yet. Displaying offline manual ad.');
    if (offlineManualAdPresenterForTesting != null) {
      isFullScreenAdShowing = true;
      final res = await offlineManualAdPresenterForTesting!();
      isFullScreenAdShowing = false;
      _activeSecondsInCurrentInterval = 0;
      _isEligible = false;
      return res;
    }
    return await _showOfflineManualAd(trigger: trigger);
  }

  /// Displays the online Google AdMob full-screen interstitial ad.
  Future<bool> _showAdMobInterstitial({required String trigger}) async {
    final adToShow = _interstitialAd!;
    isFullScreenAdShowing = true;

    final Completer<bool> completer = Completer<bool>();

    adToShow.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        debugPrint('InterstitialAdService: [INTERSTITIAL_SHOWN] Displayed Google AdMob interstitial ad (trigger: "$trigger").');
      },
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('InterstitialAdService: [INTERSTITIAL_DISMISSED] Google AdMob interstitial ad dismissed by user.');
        ad.dispose();
        _interstitialAd = null;
        isFullScreenAdShowing = false;

        // Reset interval and timer for the next 15-minute interval
        _isEligible = false;
        _activeSecondsInCurrentInterval = 0;
        debugPrint('InterstitialAdService: [INTERSTITIAL_INTERVAL_RESET] Resetting timer. Next 15-minute active session interval started.');

        // Preload next interstitial ad
        _loadInterstitialAd();

        if (!completer.isCompleted) completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('InterstitialAdService: [INTERSTITIAL_SHOW_FAILED] Failed to show AdMob interstitial: ${error.message} (code: ${error.code})');
        ad.dispose();
        _interstitialAd = null;
        isFullScreenAdShowing = false;

        // Retain eligibility and reload so it can try again
        _loadInterstitialAd();

        if (!completer.isCompleted) completer.complete(false);
      },
    );

    try {
      await adToShow.show();
      return await completer.future;
    } catch (e) {
      debugPrint('InterstitialAdService: [INTERSTITIAL_EXCEPTION] Error showing AdMob interstitial: $e');
      isFullScreenAdShowing = false;
      _interstitialAd = null;
      _loadInterstitialAd();
      return false;
    }
  }

  /// Displays the bundled offline/manual full-screen ad.
  Future<bool> _showOfflineManualAd({required String trigger}) async {
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('InterstitialAdService: [OFFLINE_AD_SKIP] No BuildContext found on navigatorKey.');
      return false;
    }

    isFullScreenAdShowing = true;
    debugPrint('InterstitialAdService: [OFFLINE_AD_SHOWN] Displaying offline/manual full-screen ad (trigger: "$trigger").');

    final Completer<bool> completer = Completer<bool>();

    try {
      await showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.90),
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (dialogContext, anim1, anim2) {
          return ManualInterstitialAdDialog(
            onDismissed: () {
              debugPrint('InterstitialAdService: [OFFLINE_AD_DISMISSED] Offline manual interstitial dismissed by user.');
              isFullScreenAdShowing = false;
              _activeSecondsInCurrentInterval = 0;
              _isEligible = false;
              debugPrint('InterstitialAdService: [INTERSTITIAL_INTERVAL_RESET] Resetting timer. Next 15-minute active session interval started.');

              // Preload next AdMob ad in case connectivity returns
              _loadInterstitialAd();

              if (!completer.isCompleted) completer.complete(true);
            },
          );
        },
      );
      return await completer.future;
    } catch (e) {
      debugPrint('InterstitialAdService: [OFFLINE_AD_EXCEPTION] Error showing manual interstitial dialog: $e');
      isFullScreenAdShowing = false;
      return false;
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _stopTimer();
    _activeSecondsInCurrentInterval = 0;
    _isEligible = false;
    _isLoading = false;
    _interstitialAd?.dispose();
    _interstitialAd = null;
    isFullScreenAdShowing = false;
    _sessionInterval = defaultSessionInterval;
    isSubscribedOverrideForTesting = null;
    isOfflineOverrideForTesting = null;
    skipAdLoadingForTesting = false;
    offlineManualAdPresenterForTesting = null;
  }
}
