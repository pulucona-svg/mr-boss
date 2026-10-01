import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../models/manual_ad.dart';
import 'connectivity_service.dart';
import 'persistence_service.dart';
import 'subscription_service.dart';
import '../widgets/manual_interstitial_ad_dialog.dart';

class InterstitialAdService extends ChangeNotifier with WidgetsBindingObserver {
  static final InterstitialAdService _instance = InterstitialAdService._internal();
  factory InterstitialAdService() => _instance;
  InterstitialAdService._internal();

  /// Key used to persist the synchronized server advertisement pool in local storage
  static const String _kCachedServerAdsKey = 'cached_server_manual_ads_v1';

  /// Global navigator key allowing the service to present full-screen dialogs
  /// (e.g. offline manual ads) from any active screen in the app.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Official Google Mobile Ads test interstitial ad unit ID for Android (retained for test fixture compatibility).
  static const String testAdUnitId = 'ca-app-pub-3940256099942544/1033173712';

  /// Official Google Mobile Ads production interstitial ad unit ID for Android.
  static const String productionAdUnitId = 'ca-app-pub-6360381092649351/6324209033';

  /// Active runtime ad unit ID (defaults strictly to production).
  String _adUnitId = productionAdUnitId;
  String get adUnitId => _adUnitId;
  @visibleForTesting
  set adUnitIdForTesting(String value) => _adUnitId = value;

  /// Default active session interval: exactly 5 minutes (reduced from 15 minutes).
  static const Duration defaultSessionInterval = Duration(minutes: 5);

  /// Configurable active session interval (default: 5 minutes).
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

  /// Hook to supply cached server ads directly in unit tests without disk IO.
  @visibleForTesting
  void setCachedServerAdsForTesting(List<ManualAd> ads) {
    _hasSyncedServerAds = true;
    _cachedServerAds = List.from(ads);
    _rebuildRuntimePool();
  }

  /// Hook to skip Firestore realtime listener in unit tests where Firebase is uninitialized.
  @visibleForTesting
  bool skipFirestoreForTesting = false;

  /// Hook to override manual idle delays for testing with short durations.
  Duration Function(int stageIndex)? manualIdleDelayOverrideForTesting;

  /// Hook to override online idle delays for testing with short durations.
  @visibleForTesting
  Duration? Function(int stageIndex)? onlineIdleDelayOverrideForTesting;

  /// Subscription to Firestore `manual_ads` collection for real-time live synchronization.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _firestoreSubscription;

  /// Tracked rotation state for manual advertisements
  ManualAd? _currentManualAd;
  ManualAd? _previousManualAd;
  int _manualRotationIndex = 0;
  ManualAd? get currentManualAd => _currentManualAd;
  ManualAd? get previousManualAd => _previousManualAd;
  int currentManualIdleStage = 0;

  /// Online AdMob idle auto-advance state
  InterstitialAd? _nextInterstitialAd;
  bool _isLoadingNextAd = false;
  Timer? _onlineIdleTimer;
  int _onlineIdleStage = 0;

  int get onlineIdleStage => _onlineIdleStage;
  @visibleForTesting
  Timer? get onlineIdleTimerForTesting => _onlineIdleTimer;
  @visibleForTesting
  InterstitialAd? get nextInterstitialAdForTesting => _nextInterstitialAd;
  @visibleForTesting
  set nextInterstitialAdForTesting(InterstitialAd? ad) => _nextInterstitialAd = ad;

  /// Active server advertisements cached locally for offline operation.
  List<ManualAd> _cachedServerAds = [];

  /// Authoritative runtime advertisement pool (bundled defaults + active server ads).
  List<ManualAd> _runtimePool = [];

  /// Read-only view of the active runtime advertisement pool.
  List<ManualAd> get runtimePool => List.unmodifiable(_runtimePool);

  /// Active carousel ads (mutually exclusive placement: 'carousel')
  List<Map<String, dynamic>> get activeCarouselAds =>
      _runtimePool.where((a) => a.isActive && a.placement == 'carousel').map((a) => a.toDialogData()).toList();

  /// Active interstitial ads (mutually exclusive placement: 'interstitial')
  List<Map<String, dynamic>> get activeInterstitialAds =>
      _runtimePool.where((a) => a.isActive && a.placement == 'interstitial').map((a) => a.toDialogData()).toList();

  /// Active offline app launch ads (mutually exclusive placement: 'app_launch')
  List<ManualAd> get activeAppLaunchAds =>
      _runtimePool.where((a) => a.isActive && a.isAppLaunch).toList();

  /// Backwards-compatible getter returning raw maps for existing consumers and tests.
  List<Map<String, dynamic>> get activeManualAds =>
      _runtimePool.where((a) => a.isActive).map((a) => a.toDialogData()).toList();

  /// Returns the idle timeout duration for a given manual ad stage.
  /// Sequence: 5s -> 20s -> 50s -> 60s -> 60s -> 60s -> ...
  Duration getManualIdleDelay(int stageIndex) {
    if (manualIdleDelayOverrideForTesting != null) {
      return manualIdleDelayOverrideForTesting!(stageIndex);
    }
    switch (stageIndex) {
      case 0:
        return const Duration(seconds: 5);
      case 1:
        return const Duration(seconds: 20);
      case 2:
        return const Duration(seconds: 50);
      default:
        return const Duration(seconds: 60);
    }
  }

  /// Returns the idle timeout duration for online AdMob ads.
  /// Sequence: 5s -> 20s -> 60s -> 120s -> 240s -> STOP (null)
  Duration? getOnlineIdleDelay(int stageIndex) {
    if (onlineIdleDelayOverrideForTesting != null) {
      return onlineIdleDelayOverrideForTesting!(stageIndex);
    }
    switch (stageIndex) {
      case 0:
        return const Duration(seconds: 5);
      case 1:
        return const Duration(seconds: 20);
      case 2:
        return const Duration(seconds: 60);
      case 3:
        return const Duration(seconds: 120);
      case 4:
        return const Duration(seconds: 240);
      default:
        return null; // STOP
    }
  }

  /// Flag indicating whether server ads have ever been synchronized or restored from cache.
  bool _hasSyncedServerAds = false;

  /// Selects the next manual ad from the runtime pool, ensuring it is DIFFERENT
  /// from the immediately previous manual ad whenever multiple active ads exist.
  /// Filters strictly by placement == 'interstitial'.
  ManualAd getNextManualAd({String? currentlyShowingId}) {
    final activePool = _runtimePool
        .where((ad) => ad.isActive && ad.placement == 'interstitial')
        .toList();

    if (activePool.isEmpty) {
      final bootstrap = ManualAd.emergencyBootstrapAd;
      _previousManualAd = _currentManualAd;
      _currentManualAd = bootstrap;
      return bootstrap;
    }

    if (activePool.length == 1) {
      final singleAd = activePool.first;
      _previousManualAd = _currentManualAd;
      _currentManualAd = singleAd;
      return singleAd;
    }

    final currentId = currentlyShowingId ?? _currentManualAd?.id;
    final currentIndex = currentId != null
        ? activePool.indexWhere((ad) => ad.id == currentId)
        : -1;

    int nextIndex;
    if (currentIndex != -1) {
      nextIndex = (currentIndex + 1) % activePool.length;
    } else {
      nextIndex = _manualRotationIndex % activePool.length;
    }

    // Strict non-repeating constraint: do not show A -> A if alternatives exist
    if (currentId != null && activePool[nextIndex].id == currentId && activePool.length > 1) {
      nextIndex = (nextIndex + 1) % activePool.length;
    }

    final nextAd = activePool[nextIndex];
    _previousManualAd = _currentManualAd;
    _currentManualAd = nextAd;
    _manualRotationIndex = (nextIndex + 1) % activePool.length;

    debugPrint('InterstitialAdService: [ROTATION] Selected manual interstitial ad "${nextAd.title}" (${nextAd.id}). Previous: "${_previousManualAd?.title}" (${_previousManualAd?.id}). Interstitial pool: ${activePool.length}');
    return nextAd;
  }

  /// Key used to persist the last displayed app launch ad ID in local storage
  static const String _kLastAppLaunchAdIdKey = 'last_app_launch_ad_id';
  String? _lastAppLaunchAdId;

  @visibleForTesting
  String? get lastAppLaunchAdIdForTesting => _lastAppLaunchAdId;

  @visibleForTesting
  set lastAppLaunchAdIdForTesting(String? id) => _lastAppLaunchAdId = id;

  /// Selects the next active offline app launch ad from the runtime pool,
  /// maintaining deterministic non-repeating rotation (A -> B -> C -> A),
  /// or returns null if no app launch ads are currently configured or active.
  ManualAd? getNextAppLaunchAd({String? currentlyShowingId}) {
    final activePool = activeAppLaunchAds;
    if (activePool.isEmpty) return null;
    if (activePool.length == 1) {
      final singleAd = activePool.first;
      _lastAppLaunchAdId = singleAd.id;
      PersistenceService().setString(_kLastAppLaunchAdIdKey, singleAd.id);
      if (kDebugMode) {
        debugPrint('[AppLaunchRotation] pool=[${singleAd.id}]');
        debugPrint('[AppLaunchRotation] lastShown=${singleAd.id}');
        debugPrint('[AppLaunchRotation] selected=${singleAd.id}');
      }
      return singleAd;
    }

    final poolIds = activePool.map((a) => a.id).toList();
    final lastId = currentlyShowingId ??
        _lastAppLaunchAdId ??
        PersistenceService().getString(_kLastAppLaunchAdIdKey);

    if (kDebugMode) {
      debugPrint('[AppLaunchRotation] pool=$poolIds');
      debugPrint('[AppLaunchRotation] lastShown=$lastId');
    }

    int nextIndex;
    if (lastId != null) {
      final lastIndex = activePool.indexWhere((ad) => ad.id == lastId);
      if (lastIndex != -1) {
        nextIndex = (lastIndex + 1) % activePool.length;
      } else {
        // Previously selected ad became inactive/deleted, pick first valid ad
        nextIndex = 0;
      }
    } else {
      nextIndex = 0;
    }

    final selectedAd = activePool[nextIndex];
    _lastAppLaunchAdId = selectedAd.id;
    PersistenceService().setString(_kLastAppLaunchAdIdKey, selectedAd.id);

    if (kDebugMode) {
      debugPrint('[AppLaunchRotation] selected=${selectedAd.id}');
    }
    return selectedAd;
  }

  /// Reconciles the manual rotation state when the runtime pool changes
  /// (e.g. after admin deletes, deactivates, or activates ads).
  void _reconcileRotationState() {
    final activeInterstitials = _runtimePool
        .where((ad) => ad.isActive && ad.placement == 'interstitial')
        .toList();

    if (activeInterstitials.isEmpty) {
      _currentManualAd = null;
      _previousManualAd = null;
      _manualRotationIndex = 0;
      return;
    }

    // Invalidate current/previous references if they are no longer active interstitials
    if (_currentManualAd != null && !activeInterstitials.any((ad) => ad.id == _currentManualAd!.id)) {
      debugPrint('InterstitialAdService: [ROTATION_RECONCILE] Currently tracked ad "${_currentManualAd!.id}" no longer active interstitial.');
      _currentManualAd = null;
    }
    if (_previousManualAd != null && !activeInterstitials.any((ad) => ad.id == _previousManualAd!.id)) {
      _previousManualAd = null;
    }

    _manualRotationIndex = _manualRotationIndex % activeInterstitials.length;
  }

  /// Rebuilds the runtime advertisement pool directly from the authoritative server-managed
  /// advertisements (fetched from Firestore when online, or restored from local persistent cache).
  /// Hardcoded bundled assets are strictly removed from the normal runtime pool.
  void _rebuildRuntimePool() {
    final Map<String, ManualAd> pool = {};

    // 1. Authoritative source: Active server-managed ads
    for (final serverAd in _cachedServerAds) {
      if (serverAd.isActive) {
        pool[serverAd.id] = serverAd;
      }
    }

    // 2. Emergency bootstrap fallback: ONLY used if the pool is completely empty
    // (first-launch offline scenario before any server synchronization has ever occurred).
    if (pool.isEmpty && !_hasSyncedServerAds) {
      final bootstrap = ManualAd.emergencyBootstrapAd;
      pool[bootstrap.id] = bootstrap;
    }

    _runtimePool = pool.values.toList();
    _reconcileRotationState();
    debugPrint('InterstitialAdService: [POOL_UPDATED] Shared runtime pool size: ${_runtimePool.length} (Server cached: ${_cachedServerAds.length})');
    notifyListeners();
  }

  /// Loads cached server ads from local persistent storage (SharedPreferences)
  /// so that previously synchronized server ads remain available when offline.
  Future<void> _loadCachedServerAds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_kCachedServerAdsKey);
      if (rawList != null && rawList.isNotEmpty) {
        _hasSyncedServerAds = true;
        _cachedServerAds = rawList.map((str) {
          final Map<String, dynamic> json = jsonDecode(str);
          return ManualAd.fromJson(json);
        }).toList();
        debugPrint('InterstitialAdService: [CACHE_LOAD] Loaded ${_cachedServerAds.length} server ads from local cache.');
      }
    } catch (e) {
      debugPrint('InterstitialAdService: [CACHE_ERROR] Failed to load cached server ads: $e');
    }
    _rebuildRuntimePool();
  }

  /// Persists current server ads to local persistent storage (SharedPreferences).
  Future<void> _saveCachedServerAds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = _cachedServerAds.map((ad) => jsonEncode(ad.toJson())).toList();
      await prefs.setStringList(_kCachedServerAdsKey, rawList);
      debugPrint('InterstitialAdService: [CACHE_SAVE] Persisted ${_cachedServerAds.length} server ads to local cache.');
    } catch (e) {
      debugPrint('InterstitialAdService: [CACHE_ERROR] Failed to save cached server ads: $e');
    }
  }

  /// Asynchronously pre-caches remote media in the background for zero-network playback.
  void _preCacheMedia(List<ManualAd> ads) {
    for (final ad in ads) {
      if (ad.imageUrl.startsWith('http://') || ad.imageUrl.startsWith('https://')) {
        unawaited(() async {
          try {
            await DefaultCacheManager().downloadFile(ad.imageUrl, key: ad.imageUrl);
          } catch (_) {}
        }());
      }
    }
  }

  /// Starts a real-time Firestore listener on the `manual_ads` collection.
  /// Automatically synchronizes whenever an admin creates, updates, activates,
  /// deactivates, or deletes a manual advertisement without requiring app restart.
  void _startFirestoreListener() {
    if (skipFirestoreForTesting) return;
    _firestoreSubscription?.cancel();
    try {
      _firestoreSubscription = FirebaseFirestore.instance
          .collection('manual_ads')
          .snapshots()
          .listen((snapshot) {
        _processFirestoreSnapshot(snapshot);
      }, onError: (e) {
        debugPrint('InterstitialAdService: [REALTIME_SYNC_ERROR] Realtime listener error: $e');
      });
      debugPrint('InterstitialAdService: [REALTIME_SYNC_STARTED] Listening to manual_ads Firestore stream for live admin changes.');
    } catch (e) {
      debugPrint('InterstitialAdService: [REALTIME_SYNC_INIT_ERROR] Realtime listener could not be started: $e');
    }
  }

  void _processFirestoreSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final List<ManualAd> serverActiveAds = [];
    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();
        final bool isActive = data['isActive'] as bool? ?? data['active'] as bool? ?? false;
        if (isActive) {
          final ad = ManualAd.fromMap(doc.id, data);
          serverActiveAds.add(ad);
        }
      } catch (adParseErr) {
        debugPrint('InterstitialAdService: [ADS_PARSE_WARN] Failed to parse ad "${doc.id}": $adParseErr');
      }
    }

    _hasSyncedServerAds = true;
    _cachedServerAds = serverActiveAds;
    _rebuildRuntimePool();
    _saveCachedServerAds();
    _preCacheMedia(_cachedServerAds);

    debugPrint('InterstitialAdService: [REALTIME_SYNC_SUCCESS] Synchronized ${_cachedServerAds.length} active server ads from Firestore live stream. Total runtime pool: ${_runtimePool.length}.');
  }

  /// Synchronizes active manual ads from Firestore when online.
  /// Deduplicates ads by stable document ID and updates the local runtime pool.
  Future<void> syncManualAds() async {
    try {
      final isOffline = isOfflineOverrideForTesting != null
          ? isOfflineOverrideForTesting!()
          : ConnectivityService().isOffline;
      if (isOffline) {
        debugPrint('InterstitialAdService: [ADS_SYNC] Skipping online sync: device is offline.');
        return;
      }

      debugPrint('InterstitialAdService: [ADS_SYNC] Fetching active ads from Firestore...');
      final snap = await FirebaseFirestore.instance
          .collection('manual_ads')
          .where('isActive', isEqualTo: true)
          .get(const GetOptions(source: Source.serverAndCache));

      final List<ManualAd> serverActiveAds = [];
      for (final doc in snap.docs) {
        try {
          final ad = ManualAd.fromMap(doc.id, doc.data());
          serverActiveAds.add(ad);
        } catch (adParseErr) {
          debugPrint('InterstitialAdService: [ADS_PARSE_WARN] Failed to parse ad "${doc.id}": $adParseErr');
        }
      }

      // Authoritative update: server state wins
      _hasSyncedServerAds = true;
      _cachedServerAds = serverActiveAds;
      _rebuildRuntimePool();
      await _saveCachedServerAds();

      // Background non-blocking pre-cache of media
      _preCacheMedia(_cachedServerAds);

      debugPrint('InterstitialAdService: [ADS_SYNC_SUCCESS] Synchronized ${_cachedServerAds.length} active server ads. Total runtime pool: ${_runtimePool.length}.');

      // Ensure realtime listener is also active for subsequent live admin changes
      _startFirestoreListener();
    } catch (e) {
      debugPrint('InterstitialAdService: [ADS_SYNC_ERROR] Sync failed (keeping local cache/bundled ads): $e');
    }
  }

  /// Handles connectivity transitions to automatically refresh server ads when returning online.
  void _onConnectivityChanged() {
    if (!ConnectivityService().isOffline) {
      debugPrint('InterstitialAdService: [CONNECTIVITY] Device returned online. Synchronizing manual ads...');
      syncManualAds();
    }
  }

  /// Initializes the service, binds app lifecycle observation, starts the session timer,
  /// loads local cached ads, and synchronizes the latest server ads with real-time stream.
  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    // 1. Initial pool from bundled defaults
    _rebuildRuntimePool();
    _lastAppLaunchAdId = PersistenceService().getString(_kLastAppLaunchAdIdKey);

    // 2. Load cached server ads from local storage, then sync online
    _loadCachedServerAds().then((_) {
      syncManualAds();
    });

    // 3. Listen for online reconnects
    ConnectivityService().addListener(_onConnectivityChanged);

    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    _loadInterstitialAd();

    debugPrint('InterstitialAdService: [INTERSTITIAL_SESSION_STARTED] Active session timer started. Interval: ${_sessionInterval.inMinutes} minutes (${_sessionInterval.inSeconds}s). Ad Unit: $_adUnitId');
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

  /// Resets the active session timer and eligibility flag.
  /// Called after an app launch advertisement completes so that the normal 5-minute
  /// active session interval starts strictly from zero inside the app.
  void resetSessionTimer() {
    _activeSecondsInCurrentInterval = 0;
    _isEligible = false;
    debugPrint('InterstitialAdService: [SESSION_RESET] Session timer reset to 0s (isEligible=false).');
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

    debugPrint('InterstitialAdService: [INTERSTITIAL_LOADING] Preloading Google interstitial ad ($_adUnitId)...');

    InterstitialAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isLoading = false;
          debugPrint('InterstitialAdService: [INTERSTITIAL_LOADED] AdMob interstitial ad loaded successfully. Unit ID: $_adUnitId');

          // If session became eligible while waiting for ad to load, show it now
          if (_isEligible && !isFullScreenAdShowing) {
            maybeShow(trigger: 'ad_loaded_while_eligible');
          }
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
          _isLoading = false;
          debugPrint('InterstitialAdService: [INTERSTITIAL_LOAD_FAILED] AdMob interstitial failed to load: ${error.message} (code: ${error.code})');
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

  /// Preloads the next AdMob interstitial ad for online idle auto-advance.
  void _loadNextAdMobInterstitial() {
    if (skipAdLoadingForTesting) return;
    if (_isLoadingNextAd || _nextInterstitialAd != null) return;
    _isLoadingNextAd = true;

    InterstitialAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _nextInterstitialAd = ad;
          _isLoadingNextAd = false;
          debugPrint('InterstitialAdService: [NEXT_ADMOB_LOADED] Next AdMob interstitial ad preloaded for online idle auto-advance.');
        },
        onAdFailedToLoad: (error) {
          _nextInterstitialAd = null;
          _isLoadingNextAd = false;
          debugPrint('InterstitialAdService: [NEXT_ADMOB_LOAD_FAILED] Failed to preload next AdMob ad: ${error.message}. Online idle chain will stop gracefully if reached.');
        },
      ),
    );
  }

  void _startOnlineIdleChain() {
    _cancelOnlineIdleTimer();
    _onlineIdleStage = 0;
    _scheduleNextOnlineIdleTimer();
    _loadNextAdMobInterstitial();
  }

  void _scheduleNextOnlineIdleTimer() {
    _onlineIdleTimer?.cancel();
    final delay = getOnlineIdleDelay(_onlineIdleStage);
    if (delay == null) {
      debugPrint('InterstitialAdService: [ONLINE_IDLE_STOP] Reached end of online idle schedule (stage $_onlineIdleStage). Stopping automatic chaining.');
      return;
    }

    debugPrint('InterstitialAdService: [ONLINE_IDLE_SCHEDULED] Online idle stage $_onlineIdleStage scheduled for ${delay.inSeconds}s.');
    _onlineIdleTimer = Timer(delay, _onOnlineIdleTimeout);
  }

  void _onOnlineIdleTimeout() {
    if (!isFullScreenAdShowing) {
      _cancelOnlineIdleTimer();
      return;
    }

    // 1. Subscription check
    final bool isSubscribed = isSubscribedOverrideForTesting != null
        ? isSubscribedOverrideForTesting!()
        : SubscriptionService().isSubscribed;
    if (isSubscribed) {
      debugPrint('InterstitialAdService: [ONLINE_IDLE_STOP] User is subscribed. Stopping online idle chain.');
      _cancelOnlineIdleTimer();
      return;
    }

    // 2. Connectivity check
    final bool isOffline = isOfflineOverrideForTesting != null
        ? isOfflineOverrideForTesting!()
        : ConnectivityService().isOffline;
    if (isOffline) {
      debugPrint('InterstitialAdService: [ONLINE_IDLE_STOP] Device is offline. Stopping online idle chain.');
      _cancelOnlineIdleTimer();
      return;
    }

    // 3. AdMob SDK / availability check: respect SDK state, do not hammer SDK
    if (_nextInterstitialAd == null) {
      debugPrint('InterstitialAdService: [ONLINE_IDLE_STOP] Next AdMob ad is not ready / loaded. Respecting AdMob SDK state, stopping online idle chain safely.');
      _cancelOnlineIdleTimer();
      return;
    }

    // 4. Advance to next online ad
    _onlineIdleStage++;
    final nextAd = _nextInterstitialAd!;
    _nextInterstitialAd = null;

    debugPrint('InterstitialAdService: [ONLINE_IDLE_ADVANCE] Advancing to next online AdMob ad (stage $_onlineIdleStage)...');
    _showAdMobInterstitialInstance(nextAd, trigger: 'online_idle_stage_$_onlineIdleStage');
    _scheduleNextOnlineIdleTimer();
    _loadNextAdMobInterstitial();
  }

  void _cancelOnlineIdleTimer() {
    _onlineIdleTimer?.cancel();
    _onlineIdleTimer = null;
    _onlineIdleStage = 0;
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

  /// Displays the online Google AdMob full-screen interstitial ad and starts online idle chaining.
  Future<bool> _showAdMobInterstitial({required String trigger}) async {
    final adToShow = _interstitialAd!;
    _interstitialAd = null;
    return _showAdMobInterstitialInstance(adToShow, trigger: trigger, isInitial: true);
  }

  Future<bool> _showAdMobInterstitialInstance(InterstitialAd adToShow, {required String trigger, bool isInitial = false}) async {
    isFullScreenAdShowing = true;
    final Completer<bool> completer = Completer<bool>();

    if (isInitial) {
      _startOnlineIdleChain();
    }

    adToShow.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        debugPrint('InterstitialAdService: [INTERSTITIAL_SHOWN] Displayed Google AdMob interstitial ad (trigger: "$trigger").');
      },
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('InterstitialAdService: [INTERSTITIAL_DISMISSED] Google AdMob interstitial ad dismissed by user.');
        ad.dispose();
        _cancelOnlineIdleTimer();
        isFullScreenAdShowing = false;

        // Reset interval and timer for the next 5-minute active session interval
        _isEligible = false;
        _activeSecondsInCurrentInterval = 0;
        debugPrint('InterstitialAdService: [INTERSTITIAL_INTERVAL_RESET] Resetting timer. Next 5-minute active session interval started.');

        // Preload next interstitial ad
        _loadInterstitialAd();

        if (!completer.isCompleted) completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('InterstitialAdService: [INTERSTITIAL_SHOW_FAILED] Failed to show AdMob interstitial: ${error.message} (code: ${error.code})');
        ad.dispose();
        _cancelOnlineIdleTimer();
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
      _cancelOnlineIdleTimer();
      isFullScreenAdShowing = false;
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
      final selectedAd = getNextManualAd();
      currentManualIdleStage = 0;

      await showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.90),
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (dialogContext, anim1, anim2) {
          return ManualInterstitialAdDialog(
            adData: selectedAd.toDialogData(),
            onDismissed: () {
              debugPrint('InterstitialAdService: [OFFLINE_AD_DISMISSED] Offline manual interstitial dismissed by user.');
              isFullScreenAdShowing = false;
              currentManualIdleStage = 0;
              _activeSecondsInCurrentInterval = 0;
              _isEligible = false;
              debugPrint('InterstitialAdService: [INTERSTITIAL_INTERVAL_RESET] Resetting timer. Next 5-minute active session interval started.');

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
      currentManualIdleStage = 0;
      return false;
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _stopTimer();
    _cancelOnlineIdleTimer();
    _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
    _activeSecondsInCurrentInterval = 0;
    _isEligible = false;
    _isLoading = false;
    _isLoadingNextAd = false;
    _hasSyncedServerAds = false;
    _cachedServerAds = [];
    _rebuildRuntimePool();
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _nextInterstitialAd?.dispose();
    _nextInterstitialAd = null;
    isFullScreenAdShowing = false;
    _sessionInterval = defaultSessionInterval;
    _currentManualAd = null;
    _previousManualAd = null;
    _manualRotationIndex = 0;
    _lastAppLaunchAdId = null;
    try {
      PersistenceService().remove(_kLastAppLaunchAdIdKey);
    } catch (_) {}
    currentManualIdleStage = 0;
    isSubscribedOverrideForTesting = null;
    isOfflineOverrideForTesting = null;
    skipAdLoadingForTesting = false;
    skipFirestoreForTesting = false;
    manualIdleDelayOverrideForTesting = null;
    onlineIdleDelayOverrideForTesting = null;
    offlineManualAdPresenterForTesting = null;
    _adUnitId = productionAdUnitId;
  }
}
