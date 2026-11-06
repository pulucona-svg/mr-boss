import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../models/xp_transaction.dart';
import 'interstitial_ad_service.dart';

class XPService extends ChangeNotifier {
  static final XPService _instance = XPService._internal();
  factory XPService() => _instance;
  XPService._internal();

  /// EXACT LIVE rewarded-video ad unit ID reused from project configuration
  static const String liveRewardedVideoAdUnitId = 'ca-app-pub-6360381092649351/9633647084';

  /// Official Google Mobile Ads test rewarded interstitial ad unit ID for Android.
  /// This will be swapped with the live production ad unit ID once created in the AdMob Console.
  static const String defaultRewardedInterstitialAdUnitId = 'ca-app-pub-3940256099942544/5354046379';

  static String rewardedInterstitialAdUnitId = defaultRewardedInterstitialAdUnitId;

  // Legacy alias for backwards compatibility
  static const String liveRewardedAdUnitId = liveRewardedVideoAdUnitId;

  static const int videoRewardXp = 5;
  static const int interstitialRewardXp = 7;
  static const int adCooldownSeconds = 30;
  static const int maxAdsPerDay = 20;

  FirebaseFirestore? _customFirestore;
  FirebaseFirestore get _firestore => _customFirestore ?? FirebaseFirestore.instance;

  FirebaseFunctions? _customFunctions;
  FirebaseFunctions get _functions => _customFunctions ?? FirebaseFunctions.instance;

  @visibleForTesting
  void setFirestoreForTesting(FirebaseFirestore firestore) => _customFirestore = firestore;

  @visibleForTesting
  void setFunctionsForTesting(FirebaseFunctions functions) => _customFunctions = functions;

  RewardedAd? _rewardedVideoAd;
  bool _isVideoLoading = false;
  bool _isVideoLoaded = false;

  RewardedInterstitialAd? _rewardedInterstitialAd;
  bool _isInterstitialLoading = false;
  bool _isInterstitialLoaded = false;

  bool _isProcessingReward = false;
  String? _lastError;

  // Server-authoritative daily counts and cooldown
  int _remainingVideoToday = maxAdsPerDay;
  int _remainingInterstitialToday = maxAdsPerDay;
  int _cooldownSecondsRemaining = 0;
  Timer? _cooldownTimer;

  bool get isVideoAdLoaded => _isVideoLoaded && _rewardedVideoAd != null;
  bool get isVideoAdLoading => _isVideoLoading;

  bool get isInterstitialAdLoaded => _isInterstitialLoaded && _rewardedInterstitialAd != null;
  bool get isInterstitialAdLoading => _isInterstitialLoading;

  // Legacy getters
  bool get isAdLoaded => isVideoAdLoaded;
  bool get isAdLoading => isVideoAdLoading;

  bool get isProcessingReward => _isProcessingReward;
  String? get lastError => _lastError;

  int get remainingVideoToday => _remainingVideoToday;
  int get remainingInterstitialToday => _remainingInterstitialToday;
  int get cooldownSecondsRemaining => _cooldownSecondsRemaining;
  bool get isCooldownActive => _cooldownSecondsRemaining > 0;

  void initialize() {
    loadRewardedVideoAd();
    loadRewardedInterstitialAd();
  }

  /// Starts or resumes the global 30-second cooldown timer
  void startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    _cooldownSecondsRemaining = seconds;
    notifyListeners();

    if (_cooldownSecondsRemaining <= 0) return;

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cooldownSecondsRemaining > 1) {
        _cooldownSecondsRemaining--;
        notifyListeners();
      } else {
        _cooldownSecondsRemaining = 0;
        timer.cancel();
        _cooldownTimer = null;
        notifyListeners();
      }
    });
  }

  /// Synchronizes authoritative remaining allowances and cooldown from backend
  Future<void> syncRewardStatus() async {
    try {
      final statusCallable = _functions.httpsCallable('getAdRewardStatus');
      final result = await statusCallable.call();
      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] == true) {
        _remainingVideoToday = (data['remainingVideoToday'] as num?)?.toInt() ?? _remainingVideoToday;
        _remainingInterstitialToday = (data['remainingInterstitialToday'] as num?)?.toInt() ?? _remainingInterstitialToday;
        final serverCooldown = (data['cooldownRemainingSeconds'] as num?)?.toInt() ?? 0;

        if (serverCooldown > 0) {
          startCooldown(serverCooldown);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('XPService: syncRewardStatus error (non-fatal): $e');
    }
  }

  /// Loads the rewarded video ad using the live production AdMob ad unit ID
  void loadRewardedVideoAd() {
    if (_isVideoLoading || (_isVideoLoaded && _rewardedVideoAd != null)) return;
    _isVideoLoading = true;

    RewardedAd.load(
      adUnitId: liveRewardedVideoAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedVideoAd = ad;
          _isVideoLoaded = true;
          _isVideoLoading = false;
          _lastError = null;
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          _rewardedVideoAd = null;
          _isVideoLoaded = false;
          _isVideoLoading = false;
          _lastError = error.message;
          debugPrint('XPService: RewardedVideoAd failed to load: $error');
          notifyListeners();
          Future.delayed(const Duration(seconds: 15), loadRewardedVideoAd);
        },
      ),
    );
  }

  // Legacy method name
  void loadRewardedAd() => loadRewardedVideoAd();

  /// Loads the rewarded interstitial ad using the Rewarded Interstitial format
  void loadRewardedInterstitialAd() {
    if (_isInterstitialLoading || (_isInterstitialLoaded && _rewardedInterstitialAd != null)) return;
    _isInterstitialLoading = true;

    RewardedInterstitialAd.load(
      adUnitId: rewardedInterstitialAdUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedInterstitialAd = ad;
          _isInterstitialLoaded = true;
          _isInterstitialLoading = false;
          _lastError = null;
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          _rewardedInterstitialAd = null;
          _isInterstitialLoaded = false;
          _isInterstitialLoading = false;
          _lastError = error.message;
          debugPrint('XPService: RewardedInterstitialAd failed to load: $error');
          notifyListeners();
          Future.delayed(const Duration(seconds: 15), loadRewardedInterstitialAd);
        },
      ),
    );
  }

  /// Initiates backend session, presents the chosen ad format, and authoritatively claims XP upon completion
  Future<void> showRewardedAdForXP({
    String rewardType = 'rewarded_video',
    required void Function(int xpEarned, String message) onSuccess,
    required void Function(String errorMessage) onFailure,
  }) async {
    if (InterstitialAdService.isFullScreenAdShowing) {
      onFailure('Another advertisement or modal is currently active.');
      return;
    }

    // Global cooldown guard
    if (_cooldownSecondsRemaining > 0) {
      onFailure('You can watch another ad in $_cooldownSecondsRemaining seconds.');
      return;
    }

    if (_isProcessingReward) {
      onFailure('Processing reward, please wait...');
      return;
    }

    final isInterstitial = rewardType == 'rewarded_interstitial';

    // Format daily limit guard (client-side pre-check)
    if (isInterstitial && _remainingInterstitialToday <= 0) {
      onFailure('Daily rewarded interstitial limit of 20 reached. Come back tomorrow!');
      return;
    }
    if (!isInterstitial && _remainingVideoToday <= 0) {
      onFailure('Daily rewarded ad limit of 20 reached. Come back tomorrow!');
      return;
    }

    // Ensure corresponding ad object is ready
    if (isInterstitial && _rewardedInterstitialAd == null) {
      loadRewardedInterstitialAd();
      onFailure('Rewarded interstitial is preparing. Please try again in a few moments.');
      return;
    }
    if (!isInterstitial && _rewardedVideoAd == null) {
      loadRewardedVideoAd();
      onFailure('Rewarded video is preparing. Please try again in a few moments.');
      return;
    }

    _isProcessingReward = true;
    notifyListeners();

    try {
      // 1. Request one-time server-controlled session nonce with rewardType
      final startSessionCallable = _functions.httpsCallable('startAdRewardSession');
      final sessionResult = await startSessionCallable.call({'rewardType': rewardType});
      final sessionData = Map<String, dynamic>.from(sessionResult.data as Map);

      if (sessionData['success'] != true) {
        final reason = sessionData['reason'] as String?;
        final remainingSec = (sessionData['remainingSeconds'] as num?)?.toInt();
        if (reason == 'cooldown' && remainingSec != null) {
          startCooldown(remainingSec);
        }

        final message = sessionData['message'] as String? ?? 'Unable to start reward session.';
        _isProcessingReward = false;
        notifyListeners();
        onFailure(message);
        return;
      }

      final sessionId = sessionData['sessionId'] as String;

      // 2. Present ad with full-screen guards
      InterstitialAdService.isFullScreenAdShowing = true;
      bool rewardEarnedOnDevice = false;

      if (isInterstitial) {
        final ad = _rewardedInterstitialAd!;
        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (adInstance) async {
            InterstitialAdService.isFullScreenAdShowing = false;
            adInstance.dispose();
            _rewardedInterstitialAd = null;
            _isInterstitialLoaded = false;
            loadRewardedInterstitialAd();

            if (!rewardEarnedOnDevice) {
              _isProcessingReward = false;
              notifyListeners();
              onFailure('Advertisement was closed before completion. No XP awarded.');
            }
          },
          onAdFailedToShowFullScreenContent: (adInstance, error) {
            InterstitialAdService.isFullScreenAdShowing = false;
            adInstance.dispose();
            _rewardedInterstitialAd = null;
            _isInterstitialLoaded = false;
            _isProcessingReward = false;
            loadRewardedInterstitialAd();
            notifyListeners();
            onFailure('Failed to display advertisement: ${error.message}');
          },
        );

        await ad.show(onUserEarnedReward: (adWithoutView, reward) async {
          rewardEarnedOnDevice = true;
          await _claimRewardOnBackend(
            sessionId: sessionId,
            onSuccess: onSuccess,
            onFailure: onFailure,
          );
        });
      } else {
        final ad = _rewardedVideoAd!;
        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (adInstance) async {
            InterstitialAdService.isFullScreenAdShowing = false;
            adInstance.dispose();
            _rewardedVideoAd = null;
            _isVideoLoaded = false;
            loadRewardedVideoAd();

            if (!rewardEarnedOnDevice) {
              _isProcessingReward = false;
              notifyListeners();
              onFailure('Advertisement was closed before completion. No XP awarded.');
            }
          },
          onAdFailedToShowFullScreenContent: (adInstance, error) {
            InterstitialAdService.isFullScreenAdShowing = false;
            adInstance.dispose();
            _rewardedVideoAd = null;
            _isVideoLoaded = false;
            _isProcessingReward = false;
            loadRewardedVideoAd();
            notifyListeners();
            onFailure('Failed to display advertisement: ${error.message}');
          },
        );

        await ad.show(onUserEarnedReward: (adWithoutView, reward) async {
          rewardEarnedOnDevice = true;
          await _claimRewardOnBackend(
            sessionId: sessionId,
            onSuccess: onSuccess,
            onFailure: onFailure,
          );
        });
      }
    } catch (e) {
      _isProcessingReward = false;
      InterstitialAdService.isFullScreenAdShowing = false;
      notifyListeners();
      debugPrint('XPService: Exception during showRewardedAdForXP: $e');

      final errStr = e.toString();
      if (errStr.contains('cooldown') || errStr.contains('Please wait')) {
        startCooldown(adCooldownSeconds);
        onFailure('Please wait 30 seconds between ad rewards.');
      } else if (errStr.contains('limit') || errStr.contains('maximum')) {
        onFailure('Daily rewarded ad limit of 20 reached. Come back tomorrow!');
      } else {
        onFailure('Unable to complete reward verification: $e');
      }
    }
  }

  /// Convenience wrapper for the +7 XP Rewarded Interstitial
  Future<void> showRewardedInterstitialForXP({
    required void Function(int xpEarned, String message) onSuccess,
    required void Function(String errorMessage) onFailure,
  }) {
    return showRewardedAdForXP(
      rewardType: 'rewarded_interstitial',
      onSuccess: onSuccess,
      onFailure: onFailure,
    );
  }

  /// Convenience wrapper for the +5 XP Rewarded Video
  Future<void> showRewardedVideoForXP({
    required void Function(int xpEarned, String message) onSuccess,
    required void Function(String errorMessage) onFailure,
  }) {
    return showRewardedAdForXP(
      rewardType: 'rewarded_video',
      onSuccess: onSuccess,
      onFailure: onFailure,
    );
  }

  /// Helper to claim reward authoritatively on backend
  Future<void> _claimRewardOnBackend({
    required String sessionId,
    required void Function(int xpEarned, String message) onSuccess,
    required void Function(String errorMessage) onFailure,
  }) async {
    try {
      final claimCallable = _functions.httpsCallable('claimAdReward');
      final claimResult = await claimCallable.call({'sessionId': sessionId});
      final claimData = Map<String, dynamic>.from(claimResult.data as Map);

      _isProcessingReward = false;

      if (claimData['success'] == true) {
        final xpEarned = (claimData['xpEarned'] as num?)?.toInt() ?? 5;
        final message = claimData['message'] as String? ?? 'Reward claimed! +$xpEarned XP added to your balance.';

        // Update remaining counts
        if (claimData['remainingVideoToday'] != null) {
          _remainingVideoToday = (claimData['remainingVideoToday'] as num).toInt();
        }
        if (claimData['remainingInterstitialToday'] != null) {
          _remainingInterstitialToday = (claimData['remainingInterstitialToday'] as num).toInt();
        }

        // Trigger global 30-second cooldown
        startCooldown(adCooldownSeconds);
        notifyListeners();

        onSuccess(xpEarned, message);
      } else {
        notifyListeners();
        onFailure(claimData['message'] as String? ?? 'Failed to claim ad reward.');
      }
    } catch (claimErr) {
      _isProcessingReward = false;
      notifyListeners();
      debugPrint('XPService: Error claiming ad reward: $claimErr');
      onFailure('Verification failed: ${claimErr.toString()}');
    }
  }

  /// Streams the authenticated user's XP transactions in real-time
  Stream<List<XPTransaction>> streamTransactions(String userId) {
    if (userId.isEmpty) return const Stream.empty();

    return _firestore
        .collection('users')
        .doc(userId)
        .collection('xp_transactions')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => XPTransaction.fromFirestore(doc.data(), doc.id))
          .toList();
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _rewardedVideoAd?.dispose();
    _rewardedInterstitialAd?.dispose();
    super.dispose();
  }
}
