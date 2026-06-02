import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../models/subscription_model.dart';
import 'persistence_service.dart';

class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<SubscriptionHistory> _history = [];
  final Set<String> _unlockedResources = {}; 
  bool _isInitialized = false;
  RewardedAd? _rewardedAd;
  bool _isAdLoading = false;
  StreamSubscription? _historySubscription;
  String? _userId;

  List<SubscriptionHistory> get history => _history;
  
  bool get isSubscribed => _history.any((s) => s.status == SubscriptionStatus.active);

  void unlockResource(String title) {
    _unlockedResources.add(title);
    _saveUnlockedResources();
    notifyListeners();
  }

  bool isResourceUnlocked(String title) => _unlockedResources.contains(title);

  SubscriptionHistory? get activeSubscription {
    try {
      return _history.firstWhere((s) => s.status == SubscriptionStatus.active);
    } catch (e) {
      return null;
    }
  }

  List<SubscriptionHistory> get queuedSubscriptions => 
      _history.where((s) => s.status == SubscriptionStatus.queued).toList();

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
  }

  /// Clears the service state. Call on logout.
  void clear() {
    _historySubscription?.cancel();
    _historySubscription = null;
    _userId = null;
    _history = [];
    _unlockedResources.clear();
    _saveHistory();
    _saveUnlockedResources();
    notifyListeners();
  }

  Future<void> _saveUnlockedResources() async {
    await PersistenceService().setStringList('unlocked_resources', _unlockedResources.toList());
  }

  int getDownloadLimit(String packageTitle) {
    switch (packageTitle) {
      case 'Daily Pass':
        return 10;
      case 'Weekly Pass':
        return 30;
      case 'Monthly Pass':
        return 50;
      case 'Semester Pass':
        return 150;
      case 'Yearly Pass':
        return -1; // Unlimited
      default:
        return 0;
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
    if (_userId == null) return;
    
    bool changed = false;
    final now = DateTime.now();
    final batch = _firestore.batch();

    // 1. Check for expired active subscriptions
    for (int i = 0; i < _history.length; i++) {
      if (_history[i].status == SubscriptionStatus.active && _history[i].expiryDate.isBefore(now)) {
        final docRef = _firestore
            .collection('subscriptions')
            .doc(_userId)
            .collection('history')
            .doc(_history[i].id);
        
        batch.update(docRef, {'status': SubscriptionStatus.expired.name});
        changed = true;
      }
    }

    // 2. If no active subscription, try to activate the oldest queued one
    bool currentlySubscribed = _history.any((s) => s.status == SubscriptionStatus.active);
    if (!currentlySubscribed) {
      final queued = _history.where((s) => s.status == SubscriptionStatus.queued).toList();
      if (queued.isNotEmpty) {
        // Sort by purchase date to get the oldest
        queued.sort((a, b) => a.purchaseDate.compareTo(b.purchaseDate));
        final oldestQueued = queued.first;
        
        final duration = oldestQueued.expiryDate.difference(oldestQueued.activationDate);
        final docRef = _firestore
            .collection('subscriptions')
            .doc(_userId)
            .collection('history')
            .doc(oldestQueued.id);

        batch.update(docRef, {
          'status': SubscriptionStatus.active.name,
          'activationDate': now,
          'expiryDate': now.add(duration),
        });
        changed = true;
      }
    }

    if (changed) {
      batch.commit().catchError((e) => debugPrint('SubscriptionService: [ERROR] Batch update failed: $e'));
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
      adUnitId: 'ca-app-pub-3940256099942544/5224354917', // Test ID
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
    if (_rewardedAd == null) {
      _loadRewardedAd();
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        _loadRewardedAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
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
