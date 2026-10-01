import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'connectivity_service.dart';
import 'interstitial_ad_service.dart';

/// Represents a single preloaded AdMob App Open Ad in the cache pool.
class CachedAppOpenAd {
  final AppOpenAd? ad;
  final DateTime loadedAt;
  final bool isTestDummy;

  CachedAppOpenAd({this.ad, required this.loadedAt, this.isTestDummy = false});

  /// Google AdMob guidelines specify that App Open ads expire after 4 hours.
  bool get isExpired => DateTime.now().difference(loadedAt).inHours >= 4;

  Duration get age => DateTime.now().difference(loadedAt);

  bool get isValid => !isExpired && (ad != null || isTestDummy);
}

/// Centralized manager for AdMob App Open Ads displayed at cold app launch and warm start.
/// 
/// Manages a bounded cached pool (max 3 preloaded ads), 4-hour expiration validation,
/// asynchronous background replenishment, and safe failure recovery without blocking the startup experience.
class AppOpenAdManager {
  static final AppOpenAdManager _instance = AppOpenAdManager._internal();
  factory AppOpenAdManager() => _instance;
  AppOpenAdManager._internal();

  /// Maximum number of preloaded App Open Ads held in the cache pool.
  static const int maxPoolSize = 3;

  /// Official Google Mobile Ads test App Open ad unit ID for Android (retained for test isolation).
  static const String testAdUnitId = 'ca-app-pub-3940256099942544/9257395921';

  /// Official Google Mobile Ads production App Open ad unit ID for Android.
  static const String productionAdUnitId = 'ca-app-pub-6360381092649351/3180928539';

  /// Configurable ad unit ID for runtime operation (defaults strictly to production).
  String _adUnitId = productionAdUnitId;
  String get adUnitId => _adUnitId;
  set adUnitId(String value) {
    if (value.isNotEmpty) _adUnitId = value;
  }

  /// Small bounded cache pool of preloaded App Open Ads.
  final List<CachedAppOpenAd> _adPool = [];

  int _pendingLoads = 0;
  bool _isShowingAd = false;
  bool _isConnectivityListening = false;
  bool _isSdkInitialized = false;
  Completer<bool>? _loadCompleter;

  bool get isLoading => _pendingLoads > 0 || waitForAdOverrideForTesting != null;
  bool get isShowingAd => _isShowingAd;
  bool get isSdkInitialized => _isSdkInitialized;

  void markSdkInitialized() {
    _isSdkInitialized = true;
  }

  // ==========================================
  // TESTING HOOKS & OVERRIDES
  // ==========================================
  @visibleForTesting
  bool skipAdLoadingForTesting = false;

  @visibleForTesting
  Future<bool> Function({required VoidCallback onDismissed})? showAdOverrideForTesting;

  @visibleForTesting
  Future<bool> Function({required Duration timeout})? waitForAdOverrideForTesting;

  @visibleForTesting
  bool? isAdAvailableOverrideForTesting;

  @visibleForTesting
  List<CachedAppOpenAd> get poolForTesting => List.unmodifiable(_adPool);

  @visibleForTesting
  int get pendingLoadsForTesting => _pendingLoads;

  /// Initializes connectivity observation for automatic pool replenishment.
  void initialize() {
    if (!_isConnectivityListening) {
      ConnectivityService().addListener(_onConnectivityChanged);
      _isConnectivityListening = true;
    }
  }

  void _onConnectivityChanged() {
    if (!ConnectivityService().isOffline) {
      if (kDebugMode) {
        debugPrint('AppOpenAdManager: [CONNECTIVITY] Device returned online. Replenishing App Open pool...');
      }
      replenishPool();
    }
  }

  /// Removes and disposes any expired ads (>= 4 hours old) from the cache pool.
  /// Returns the count of removed expired ads.
  int cleanExpiredAds() {
    int removedCount = 0;
    _adPool.removeWhere((cached) {
      if (cached.isExpired) {
        cached.ad?.dispose();
        removedCount++;
        if (kDebugMode) {
          debugPrint('AppOpenAdManager: [EXPIRED] Cached App Open Ad expired after ${cached.age.inMinutes}m (>= 4h). Disposed.');
        }
        return true;
      }
      return false;
    });
    return removedCount;
  }

  /// Whether a valid non-expired cached App Open Ad is available in the pool.
  bool get hasValidCachedAd {
    if (isAdAvailableOverrideForTesting != null) {
      return isAdAvailableOverrideForTesting!;
    }
    if (showAdOverrideForTesting != null) {
      return true;
    }
    cleanExpiredAds();
    return _adPool.any((e) => e.isValid);
  }

  /// Backwards-compatible getter for existing consumers.
  bool get isAdAvailable => hasValidCachedAd;

  /// Returns the number of valid non-expired ads currently cached in the pool.
  int get cachedPoolSize {
    cleanExpiredAds();
    return _adPool.where((e) => e.isValid).length;
  }

  /// Returns the age of the next available cached ad, or null if pool is empty.
  Duration? peekNextAdAge() {
    cleanExpiredAds();
    final valid = _adPool.where((e) => e.isValid);
    if (valid.isEmpty) return null;
    return valid.first.age;
  }

  /// Replenishes the pool up to [maxPoolSize] whenever network conditions allow.
  void replenishPool() {
    if (skipAdLoadingForTesting) return;
    final isOffline = ConnectivityService().isOffline;
    if (isOffline) {
      if (kDebugMode) debugPrint('AppOpenAdManager: [REPLENISH_SKIP] Device is offline.');
      return;
    }
    cleanExpiredAds();
    final int currentCount = _adPool.length + _pendingLoads;
    final int needed = maxPoolSize - currentCount;
    if (needed <= 0) {
      if (kDebugMode) {
        debugPrint('AppOpenAdManager: [POOL_FULL] Pool has ${_adPool.length} valid ads, $_pendingLoads pending (max: $maxPoolSize).');
      }
      return;
    }
    if (kDebugMode) {
      debugPrint('AppOpenAdManager: [REPLENISH] Requesting $needed ads to reach target pool size $maxPoolSize.');
    }
    for (int i = 0; i < needed; i++) {
      _loadSingleAd();
    }
  }

  /// Initiates loading a single App Open Ad into the cache pool.
  Future<void> _loadSingleAd() async {
    if (skipAdLoadingForTesting) return;
    cleanExpiredAds();
    if (_adPool.length + _pendingLoads >= maxPoolSize) {
      return;
    }
    _pendingLoads++;
    final int poolBefore = _adPool.length;
    final bool isOnline = !ConnectivityService().isOffline;

    if (kDebugMode) {
      debugPrint('[AppOpenDebug] loadRequested=true');
      debugPrint('[AppOpenDebug] sdkInitialized=$_isSdkInitialized');
      debugPrint('[AppOpenDebug] online=$isOnline');
      debugPrint('[AppOpenDebug] poolBefore=$poolBefore');
    }

    try {
      await AppOpenAd.load(
        adUnitId: _adUnitId,
        request: const AdRequest(),
        adLoadCallback: AppOpenAdLoadCallback(
          onAdLoaded: (ad) {
            _pendingLoads = (_pendingLoads - 1).clamp(0, maxPoolSize);
            cleanExpiredAds();
            if (_adPool.length < maxPoolSize) {
              final entry = CachedAppOpenAd(ad: ad, loadedAt: DateTime.now());
              _adPool.add(entry);
              if (kDebugMode) {
                debugPrint('[AppOpenDebug] loadSuccess=true');
                debugPrint('[AppOpenDebug] poolAfter=${_adPool.length}');
                debugPrint('[AppOpenDebug] adAge=${entry.age.inSeconds}s');
              }
            } else {
              ad.dispose();
              if (kDebugMode) {
                debugPrint('AppOpenAdManager: [LOADED_EXCESS] Pool full, disposed excess loaded ad.');
              }
            }
            if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
              _loadCompleter!.complete(true);
            }
          },
          onAdFailedToLoad: (error) {
            _pendingLoads = (_pendingLoads - 1).clamp(0, maxPoolSize);
            if (kDebugMode) {
              debugPrint('[AppOpenDebug] loadFailed=true');
              debugPrint('[AppOpenDebug] errorCode=${error.code}');
              debugPrint('[AppOpenDebug] errorDomain=${error.domain}');
              debugPrint('[AppOpenDebug] errorMessage=${error.message}');
            }
            if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
              _loadCompleter!.complete(false);
            }
            // Non-aggressive background retry after 15s to replenish cache
            Future.delayed(const Duration(seconds: 15), () {
              if (!ConnectivityService().isOffline && _adPool.length < maxPoolSize) {
                replenishPool();
              }
            });
          },
        ),
      );
    } catch (e) {
      _pendingLoads = (_pendingLoads - 1).clamp(0, maxPoolSize);
      if (kDebugMode) {
        debugPrint('[AppOpenDebug] loadFailed=true');
        debugPrint('[AppOpenDebug] errorCode=-1');
        debugPrint('[AppOpenDebug] errorDomain=exception');
        debugPrint('[AppOpenDebug] errorMessage=$e');
      }
      if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
        _loadCompleter!.complete(false);
      }
    }
  }

  /// Backward-compatible loadAd method.
  Future<void> loadAd() async {
    replenishPool();
  }

  /// Awaits ad loading with a bounded duration timeout.
  /// If an ad is already available, returns true immediately.
  /// If an in-flight ad finishes within [timeout], returns true.
  /// If the ad fails or times out, returns false without blocking the user.
  Future<bool> waitForAd({required Duration timeout}) async {
    if (waitForAdOverrideForTesting != null) {
      return await waitForAdOverrideForTesting!(timeout: timeout);
    }
    if (hasValidCachedAd) return true;
    if (skipAdLoadingForTesting && _pendingLoads == 0) {
      return false;
    }
    if (_pendingLoads == 0) {
      replenishPool();
    }
    _loadCompleter ??= Completer<bool>();
    try {
      final result = await _loadCompleter!.future.timeout(timeout, onTimeout: () => false);
      _loadCompleter = null;
      return result && hasValidCachedAd;
    } catch (_) {
      _loadCompleter = null;
      return false;
    }
  }

  /// Consumes and displays the oldest valid cached App Open Ad from the pool.
  /// Triggers [onDismissed] when completed or on failure so startup continues cleanly.
  Future<bool> showNextCachedAd({required VoidCallback onDismissed}) async {
    if (showAdOverrideForTesting != null) {
      return await showAdOverrideForTesting!(onDismissed: onDismissed);
    }

    cleanExpiredAds();
    final validIndex = _adPool.indexWhere((e) => e.isValid);
    if (validIndex == -1) {
      if (kDebugMode) {
        debugPrint('AppOpenAdManager: [UNAVAILABLE] No valid cached App Open Ad available.');
        debugPrint('[AppOpenDebug] continuingWithoutAppOpen=true');
        debugPrint('[AppOpenDebug] reason=no_cached_ad');
      }
      onDismissed();
      return false;
    }

    if (_isShowingAd || InterstitialAdService.isFullScreenAdShowing) {
      if (kDebugMode) {
        debugPrint('AppOpenAdManager: [GUARD] Another full-screen presentation is active. Skipping App Open Ad.');
        debugPrint('[AppOpenDebug] continuingWithoutAppOpen=true');
        debugPrint('[AppOpenDebug] reason=another_fullscreen_ad_active');
      }
      onDismissed();
      return false;
    }

    final entry = _adPool.removeAt(validIndex);
    if (entry.isTestDummy && entry.ad == null) {
      if (kDebugMode) {
        debugPrint('[AppOpenDebug] showRequested=true');
        debugPrint('[AppOpenDebug] adSelected=true');
        debugPrint('[AppOpenDebug] adAge=${entry.age.inSeconds}s');
        debugPrint('[AppOpenDebug] showSuccess=true');
        debugPrint('[AppOpenDebug] dismissed=true');
      }
      onDismissed();
      return true;
    }

    final ad = entry.ad!;
    _isShowingAd = true;
    InterstitialAdService.isFullScreenAdShowing = true;

    if (kDebugMode) {
      debugPrint('[AppOpenDebug] showRequested=true');
      debugPrint('[AppOpenDebug] adSelected=true');
      debugPrint('[AppOpenDebug] adAge=${entry.age.inSeconds}s');
    }

    final Completer<bool> completer = Completer<bool>();
    bool dismissedCalled = false;

    void safeDismiss() {
      if (dismissedCalled) return;
      dismissedCalled = true;
      _isShowingAd = false;
      InterstitialAdService.isFullScreenAdShowing = false;
      onDismissed();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        if (kDebugMode) {
          debugPrint('AppOpenAdManager: [SHOWN] App Open Ad displayed on screen.');
          debugPrint('[AppOpenDebug] showSuccess=true');
        }
      },
      onAdDismissedFullScreenContent: (ad) {
        if (kDebugMode) {
          debugPrint('AppOpenAdManager: [DISMISSED] App Open Ad dismissed by user.');
          debugPrint('[AppOpenDebug] dismissed=true');
        }
        ad.dispose();
        safeDismiss();
        if (!completer.isCompleted) completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        if (kDebugMode) {
          debugPrint('AppOpenAdManager: [SHOW_FAILED] App Open Ad failed to show: ${error.message} (code: ${error.code})');
          debugPrint('[AppOpenDebug] showFailed=true');
          debugPrint('[AppOpenDebug] errorCode=${error.code}');
          debugPrint('[AppOpenDebug] errorDomain=${error.domain}');
          debugPrint('[AppOpenDebug] errorMessage=${error.message}');
        }
        ad.dispose();
        safeDismiss();
        if (!completer.isCompleted) completer.complete(false);
      },
      onAdImpression: (ad) {
        if (kDebugMode) debugPrint('AppOpenAdManager: [IMPRESSION] App Open Ad recorded impression.');
      },
      onAdClicked: (ad) {
        if (kDebugMode) debugPrint('AppOpenAdManager: [CLICKED] App Open Ad clicked.');
      },
    );

    try {
      await ad.show();
      return await completer.future;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AppOpenAdManager: [EXCEPTION] Error showing App Open Ad: $e');
        debugPrint('[AppOpenDebug] showFailed=true');
        debugPrint('[AppOpenDebug] errorCode=-1');
        debugPrint('[AppOpenDebug] errorDomain=exception');
        debugPrint('[AppOpenDebug] errorMessage=$e');
      }
      ad.dispose();
      safeDismiss();
      return false;
    }
  }

  /// Backward-compatible showAdIfAvailable method.
  Future<bool> showAdIfAvailable({required VoidCallback onDismissed}) {
    return showNextCachedAd(onDismissed: onDismissed);
  }

  void _disposeAllAds() {
    for (final cached in _adPool) {
      cached.ad?.dispose();
    }
    _adPool.clear();
  }

  @visibleForTesting
  void setAdForTesting(AppOpenAd? ad, {DateTime? loadTime}) {
    _disposeAllAds();
    if (ad != null || loadTime != null) {
      _adPool.add(CachedAppOpenAd(ad: ad, loadedAt: loadTime ?? DateTime.now()));
    }
  }

  @visibleForTesting
  void addAdToPoolForTesting(AppOpenAd ad, {DateTime? loadTime}) {
    _adPool.add(CachedAppOpenAd(ad: ad, loadedAt: loadTime ?? DateTime.now()));
  }

  @visibleForTesting
  void addTestDummyAd({DateTime? loadedAt}) {
    _adPool.add(CachedAppOpenAd(ad: null, loadedAt: loadedAt ?? DateTime.now(), isTestDummy: true));
  }

  @visibleForTesting
  void resetForTesting() {
    _disposeAllAds();
    _pendingLoads = 0;
    if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
      _loadCompleter!.complete(false);
    }
    _loadCompleter = null;
    _isShowingAd = false;
    _adUnitId = productionAdUnitId;
    skipAdLoadingForTesting = false;
    showAdOverrideForTesting = null;
    waitForAdOverrideForTesting = null;
    isAdAvailableOverrideForTesting = null;
  }
}
