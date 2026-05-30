import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../models/subscription_model.dart';
import 'persistence_service.dart';

class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  List<SubscriptionHistory> _history = [];
  final Set<String> _unlockedResources = {}; 
  bool _isInitialized = false;
  RewardedAd? _rewardedAd;
  bool _isAdLoading = false;

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
    
    final historyJson = PersistenceService().getStringList('subscription_history') ?? [];
    _history = historyJson
        .map((j) => SubscriptionHistory.fromJson(jsonDecode(j)))
        .toList();

    final unlocked = PersistenceService().getStringList('unlocked_resources') ?? [];
    _unlockedResources.addAll(unlocked);
    
    _updateSubscriptionStates();
    _loadRewardedAd();
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
    if (active != null) {
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

  void _updateSubscriptionStates() {
    bool changed = false;
    final now = DateTime.now();

    // 1. Check for expired active subscriptions
    for (int i = 0; i < _history.length; i++) {
      if (_history[i].status == SubscriptionStatus.active && _history[i].expiryDate.isBefore(now)) {
        _history[i] = _history[i].copyWith(status: SubscriptionStatus.expired);
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
        final oldestQueuedId = queued.first.id;
        
        for (int i = 0; i < _history.length; i++) {
          if (_history[i].id == oldestQueuedId) {
            final duration = _history[i].expiryDate.difference(_history[i].activationDate);
            _history[i] = _history[i].copyWith(
              status: SubscriptionStatus.active,
              activationDate: now,
              expiryDate: now.add(duration),
            );
            changed = true;
            break;
          }
        }
      }
    }

    if (changed) {
      _saveHistory();
      notifyListeners();
    }
  }

  Future<void> _saveHistory() async {
    final historyJson = _history.map((s) => jsonEncode(s.toJson())).toList();
    await PersistenceService().setStringList('subscription_history', historyJson);
  }

  Future<void> addSubscription(SubscriptionPackage package) async {
    // Simulate payment process delay
    await Future.delayed(const Duration(seconds: 2));

    final now = DateTime.now();
    bool hasActive = isSubscribed;

    final newSub = SubscriptionHistory(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      packageTitle: package.title,
      amount: package.price,
      transactionCode: 'TXN${DateTime.now().millisecondsSinceEpoch}',
      purchaseDate: now,
      activationDate: hasActive ? now : now, // Placeholder, will be updated if queued
      expiryDate: hasActive ? now.add(package.duration) : now.add(package.duration),
      status: hasActive ? SubscriptionStatus.queued : SubscriptionStatus.active,
    );

    _history.insert(0, newSub);
    await _saveHistory();
    notifyListeners();
  }

  Future<void> terminateSubscription(String id) async {
    bool changed = false;
    for (int i = 0; i < _history.length; i++) {
      if (_history[i].id == id) {
        _history[i] = _history[i].copyWith(status: SubscriptionStatus.terminated);
        changed = true;
        break;
      }
    }

    if (changed) {
      _updateSubscriptionStates(); // This will auto-activate the next in queue if needed
      await _saveHistory();
      notifyListeners();
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
