import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../models/subscription_model.dart';

class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  List<SubscriptionHistory> _history = [];
  bool _isInitialized = false;
  RewardedAd? _rewardedAd;
  bool _isAdLoading = false;

  List<SubscriptionHistory> get history => _history;
  bool get isSubscribed => _history.any((s) => s.isActive && s.expiryDate.isAfter(DateTime.now()));

  Future<void> init() async {
    if (_isInitialized) return;
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('subscription_history') ?? [];
    _history = historyJson
        .map((j) => SubscriptionHistory.fromJson(jsonDecode(j)))
        .toList();
    _isInitialized = true;
    _checkExpirations();
    _loadRewardedAd();
    notifyListeners();
  }

  void _checkExpirations() {
    bool changed = false;
    final now = DateTime.now();
    for (int i = 0; i < _history.length; i++) {
      if (_history[i].isActive && _history[i].expiryDate.isBefore(now)) {
        // In a real app, you might update the status in a DB
        // For this prototype, we'll just let the getter handle it or update local state
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = _history.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList('subscription_history', historyJson);
  }

  Future<void> addSubscription(SubscriptionPackage package) async {
    // Simulate payment process delay
    await Future.delayed(const Duration(seconds: 2));

    final now = DateTime.now();
    final newSub = SubscriptionHistory(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      packageTitle: package.title,
      amount: package.price,
      transactionCode: 'TXN${DateTime.now().millisecondsSinceEpoch}',
      purchaseDate: now,
      expiryDate: now.add(package.duration),
      isActive: true,
    );

    // Deactivate old active subscriptions of the same type or all for simplicity
    for (var sub in _history) {
      // In this simple logic, we just add a new one and the isSubscribed check will find the latest active one
    }

    _history.insert(0, newSub);
    await _saveHistory();
    notifyListeners();
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
      // If ad not ready, we could show a message or just wait. 
      // For this task, we'll assume it's loading or show an error if it fails repeatedly.
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
