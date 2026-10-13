import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../models/subscription_model.dart';
import 'persistence_service.dart';
import 'interstitial_ad_service.dart';


class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseFunctions get _functions => FirebaseFunctions.instance;
  List<SubscriptionHistory> _history = [];
  final Set<String> _unlockedResources = {}; 
  bool _isInitialized = false;
  RewardedAd? _rewardedAd;
  bool _isAdLoading = false;
  StreamSubscription? _historySubscription;
  String? _userId;

  // Promotional Campaign State
  PromotionalCampaignState? _promotionalState;
  bool _isLoadingPromoStatus = false;
  bool _isClaimingTrial = false;
  String? _promoError;

  PromotionalCampaignState? get promotionalState => _promotionalState;
  bool get isLoadingPromoStatus => _isLoadingPromoStatus;
  bool get isClaimingTrial => _isClaimingTrial;
  String? get promoError => _promoError;

  @visibleForTesting
  void setPromotionalStateForTesting(PromotionalCampaignState? state) {
    _promotionalState = state;
    try {
      notifyListeners();
    } catch (_) {}
  }

  List<SubscriptionHistory> get history => _history;

  @visibleForTesting
  void setHistoryForTesting(List<SubscriptionHistory> list) {
    _history = list;
    try {
      notifyListeners();
    } catch (_) {}
  }
  
  bool? _overrideIsSubscribed;

  bool get isSubscribed => _overrideIsSubscribed ?? _history.any((s) => s.isEffectiveNow);

  @visibleForTesting
  set isSubscribedForTesting(bool value) {
    _overrideIsSubscribed = value;
    try {
      notifyListeners();
    } catch (_) {}
  }

  void unlockResource(String title) {
    _unlockedResources.add(title);
    _saveUnlockedResources();
    notifyListeners();
  }

  bool isResourceUnlocked(String title) => _unlockedResources.contains(title);

  SubscriptionHistory? get activeSubscription {
    try {
      return _history.firstWhere((s) => s.isEffectiveNow);
    } catch (e) {
      return null;
    }
  }

  List<SubscriptionHistory> get queuedSubscriptions {
    final now = DateTime.now();
    return _history.where((s) =>
      s.status != SubscriptionStatus.expired &&
      s.status != SubscriptionStatus.terminated &&
      s.status != SubscriptionStatus.unknown &&
      now.isBefore(s.activationDate) &&
      s.activationDate.isBefore(s.expiryDate)
    ).toList();
  }

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    
    // 1. Load from local cache for offline/initial use
    final historyJson = PersistenceService().getStringList('subscription_history') ?? [];
    _history = historyJson
        .map((j) => SubscriptionHistory.fromJson(jsonDecode(j)))
        .toList();

    final unlocked = PersistenceService().getStringList('unlocked_resources') ?? [];
    _unlockedResources.addAll(unlocked);
    
    _updateSubscriptionStates();
    _loadRewardedAd();
    notifyListeners();

    // 2. Setup real-time sync if user is logged in
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      initialize(currentUser.uid);
    }
  }

  /// Starts real-time synchronization with Firestore for the given user.
  void initialize(String userId) {
    if (_userId == userId) return;
    _userId = userId;
    
    _historySubscription?.cancel();
    
    debugPrint('SubscriptionService: [DEBUG] Initializing sync for user: $userId');
    
    _historySubscription = _firestore
        .collection('subscriptions')
        .doc(userId)
        .collection('history')
        .snapshots()
        .listen((snapshot) {
      _history = snapshot.docs
          .map((doc) => SubscriptionHistory.fromFirestore(doc.data(), doc.id))
          .toList();
      
      // Sort by purchase date (newest first)
      _history.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
      
      _saveHistory();
      _updateSubscriptionStates();
      notifyListeners();
      debugPrint('SubscriptionService: [DEBUG] Subscription history synced from Firestore. Count: ${_history.length}');
    }, onError: (e) {
      debugPrint('SubscriptionService: [ERROR] Firestore listener failed: $e');
    });

    // Check promotional trial campaign eligibility
    fetchPromotionalCampaignStatus(silent: true);
  }

  /// Clears the service state. Call on logout.
  void clear() {
    _historySubscription?.cancel();
    _historySubscription = null;
    _userId = null;
    _history = [];
    _unlockedResources.clear();
    _overrideIsSubscribed = null;
    _promotionalState = null;
    _promoError = null;
    _isClaimingTrial = false;
    _saveHistory();
    _saveUnlockedResources();
    try {
      notifyListeners();
    } catch (_) {}
  }

  @override
  // ignore: must_call_super
  void dispose() {
    // Singleton instance persists across app lifecycle and test cases.
  }

  Future<void> _saveUnlockedResources() async {
    await PersistenceService().setStringList('unlocked_resources', _unlockedResources.toList());
  }

  int getDownloadLimit(String packageTitle) {
    switch (packageTitle) {
      case 'Daily Pass':
        return 10;
      case 'Weekly Pass':
      case '1-Week Free Trial':
        return 30;
      case 'Monthly Pass':
      case '1-Month Free Trial':
        return 50;
      case 'Semester Pass':
      case '2-Month Free Trial':
        return 150;
      case 'Yearly Pass':
        return -1; // Unlimited
      default:
        if (packageTitle.contains('2-Month') || packageTitle.contains('2 Month')) return 100;
        if (packageTitle.contains('1-Month') || packageTitle.contains('1 Month')) return 50;
        if (packageTitle.contains('Week') || packageTitle.contains('7-Day')) return 30;
        return 0;
    }
  }

  /// Fetches the latest promotional trial campaign status and user eligibility
  Future<void> fetchPromotionalCampaignStatus({bool silent = false}) async {
    if (!silent) {
      _isLoadingPromoStatus = true;
      _promoError = null;
      notifyListeners();
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      final callable = _functions.httpsCallable('getPromotionalCampaignStatus');
      final result = await callable.call({
        if (user?.email != null) 'userEmail': user!.email,
      });

      if (result.data is Map) {
        _promotionalState = PromotionalCampaignState.fromMap(
          Map<dynamic, dynamic>.from(result.data as Map),
        );
      }
    } catch (e) {
      debugPrint('SubscriptionService: [WARN] Failed to fetch promotional campaign status: $e');
    } finally {
      if (!silent) {
        _isLoadingPromoStatus = false;
        notifyListeners();
      }
    }
  }

  /// Claims the currently active promotional trial atomically
  Future<Map<String, dynamic>> claimPromotionalTrial() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      const msg = 'Please sign in to claim a promotional trial.';
      _promoError = msg;
      notifyListeners();
      return {'success': false, 'message': msg};
    }

    _isClaimingTrial = true;
    _promoError = null;
    notifyListeners();

    try {
      final callable = _functions.httpsCallable('claimPromotionalTrial');
      final result = await callable.call({
        'userEmail': user.email,
      });

      final data = result.data is Map ? Map<String, dynamic>.from(result.data as Map) : <String, dynamic>{};

      // Refresh campaign status to update UI immediately
      await fetchPromotionalCampaignStatus(silent: true);

      _isClaimingTrial = false;
      notifyListeners();
      return {
        'success': true,
        'message': data['message'] ?? 'Promotional trial activated successfully!',
        'data': data,
      };
    } on FirebaseFunctionsException catch (e) {
      final errorMsg = e.message ?? 'Failed to claim promotional trial.';
      _promoError = errorMsg;
      _isClaimingTrial = false;
      notifyListeners();
      return {'success': false, 'message': errorMsg};
    } catch (e) {
      final errorMsg = e.toString().replaceFirst(RegExp(r'^Exception: '), '');
      _promoError = errorMsg;
      _isClaimingTrial = false;
      notifyListeners();
      return {'success': false, 'message': errorMsg};
    }
  }

  bool canDownload() {
    final active = activeSubscription;
    if (active == null) return false;
    
    final limit = getDownloadLimit(active.packageTitle);
    if (limit == -1) return true;
    
    return active.downloadCount < limit;
  }

  Future<void> recordDownload() async {
    final active = activeSubscription;
    if (active != null && _userId != null) {
      try {
        await _firestore
            .collection('subscriptions')
            .doc(_userId)
            .collection('history')
            .doc(active.id)
            .update({'downloadCount': FieldValue.increment(1)});
      } catch (e) {
        debugPrint('SubscriptionService: [ERROR] Failed to record download in Firestore: $e');
        // Fallback to local update if Firestore fails (will sync later when online)
        for (int i = 0; i < _history.length; i++) {
          if (_history[i].id == active.id) {
            _history[i] = _history[i].copyWith(downloadCount: _history[i].downloadCount + 1);
            break;
          }
        }
        await _saveHistory();
        notifyListeners();
      }
    }
  }

  void _updateSubscriptionStates() {
    // Dynamic access is calculated in real time via isEffectiveNow.
    // Client-side Firestore batch writes are omitted to strictly obey firestore.rules (isAdmin only).
    _reconcileSubscriptionStatusBackend();
  }

  Future<void> _reconcileSubscriptionStatusBackend() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final callable = _functions.httpsCallable('reconcileUserSubscriptions');
        await callable.call();
      }
    } catch (e) {
      debugPrint('SubscriptionService: [DEBUG] Backend status reconciliation skipped: $e');
    }
  }

  Future<void> _saveHistory() async {
    final historyJson = _history.map((s) => jsonEncode(s.toJson())).toList();
    await PersistenceService().setStringList('subscription_history', historyJson);
  }

  Future<void> addSubscription(SubscriptionPackage package) async {
    if (_userId == null) return;

    // Simulate payment process delay
    await Future.delayed(const Duration(seconds: 2));

    final now = DateTime.now();
    bool hasActive = isSubscribed;

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final newSub = SubscriptionHistory(
      id: id,
      packageTitle: package.title,
      amount: package.price,
      transactionCode: 'TXN${DateTime.now().millisecondsSinceEpoch}',
      purchaseDate: now,
      activationDate: now, 
      expiryDate: now.add(package.duration),
      status: hasActive ? SubscriptionStatus.queued : SubscriptionStatus.active,
    );

    try {
      await _firestore
          .collection('subscriptions')
          .doc(_userId)
          .collection('history')
          .doc(id)
          .set(newSub.toFirestore());
      
      debugPrint('SubscriptionService: [DEBUG] New subscription added to Firestore.');
    } catch (e) {
      debugPrint('SubscriptionService: [ERROR] Failed to add subscription to Firestore: $e');
      // Even if Firestore fails, we can't easily fallback here without a local-only implementation
      // which we are trying to avoid. But for UX, we might want to show it locally.
      rethrow;
    }
  }

  Future<void> terminateSubscription(String id) async {
    if (_userId == null) return;

    try {
      await _firestore
          .collection('subscriptions')
          .doc(_userId)
          .collection('history')
          .doc(id)
          .update({'status': SubscriptionStatus.terminated.name});
      
      _updateSubscriptionStates(); // Try to activate next in queue
    } catch (e) {
      debugPrint('SubscriptionService: [ERROR] Failed to terminate subscription in Firestore: $e');
    }
  }

  void _loadRewardedAd() {
    if (_isAdLoading) return;
    _isAdLoading = true;

    RewardedAd.load(
      adUnitId: 'ca-app-pub-6360381092649351/9633647084', // Production ID
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isAdLoading = false;
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          _rewardedAd = null;
          _isAdLoading = false;
          debugPrint('RewardedAd failed to load: $error');
          // Retry loading after some time
          Future.delayed(const Duration(seconds: 10), _loadRewardedAd);
        },
      ),
    );
  }

  Future<void> showRewardedAd({required Function onRewardEarned}) async {
    if (InterstitialAdService.isFullScreenAdShowing) {
      debugPrint('SubscriptionService: Full-screen ad already displaying, cannot show rewarded ad.');
      return;
    }

    if (_rewardedAd == null) {
      _loadRewardedAd();
      return;
    }

    InterstitialAdService.isFullScreenAdShowing = true;

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        InterstitialAdService.isFullScreenAdShowing = false;
        ad.dispose();
        _rewardedAd = null;
        _loadRewardedAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        InterstitialAdService.isFullScreenAdShowing = false;
        ad.dispose();
        _rewardedAd = null;
        _loadRewardedAd();
      },
    );

    await _rewardedAd!.show(onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
      onRewardEarned();
    });
  }
}
