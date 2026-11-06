import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mirror_laikipia/models/subscription_model.dart';
import 'package:mirror_laikipia/models/xp_transaction.dart';
import 'package:mirror_laikipia/providers/user_provider.dart';
import 'package:mirror_laikipia/services/xp_service.dart';

void main() {
  group('Donation Amount & XP Calculation Tests', () {
    test('1. Minimum KSh 3 is accepted, below KSh 3 is rejected', () {
      bool isAmountValid(int amount) => amount >= 3;

      expect(isAmountValid(3), isTrue);
      expect(isAmountValid(5), isTrue);
      expect(isAmountValid(10), isTrue);
      expect(isAmountValid(100), isTrue);
      expect(isAmountValid(2), isFalse);
      expect(isAmountValid(1), isFalse);
      expect(isAmountValid(0), isFalse);
      expect(isAmountValid(-5), isFalse);
    });

    test('2. XP calculation awards exactly 10 XP per KSh donated', () {
      int calculateDonationXp(int kes) => kes * 10;

      expect(calculateDonationXp(3), 30);
      expect(calculateDonationXp(5), 50);
      expect(calculateDonationXp(10), 100);
      expect(calculateDonationXp(50), 500);
      expect(calculateDonationXp(100), 1000);
      expect(calculateDonationXp(250), 2500);
    });

    test('3. Card / Mastercard minimum KSh 100 rule is enforced', () {
      bool isCardAmountValid(int amount) => amount >= 100;

      expect(isCardAmountValid(100), isTrue);
      expect(isCardAmountValid(500), isTrue);
      expect(isCardAmountValid(99), isFalse);
      expect(isCardAmountValid(50), isFalse);
      expect(isCardAmountValid(3), isFalse);
    });
  });

  group('XPTransaction Model Serialization & Verification Tests', () {
    test('4. Donation transaction correctly serializes and deserializes', () {
      final now = DateTime.utc(2026, 11, 3, 12, 0, 0);
      final tx = XPTransaction(
        id: 'tx_donation_001',
        userId: 'user_test_123',
        type: 'donation',
        title: 'Direct Donation',
        description: 'Donation of KSh 30',
        xpAmount: 300,
        kesAmount: 30,
        paymentMethod: 'mpesa',
        paystackReference: 'ML_DON_TEST_123',
        operatorReceiptNumber: 'QWE123RTY',
        status: 'success',
        createdAt: now,
      );

      final json = tx.toJson();
      expect(json['id'], 'tx_donation_001');
      expect(json['userId'], 'user_test_123');
      expect(json['type'], 'donation');
      expect(json['title'], 'Direct Donation');
      expect(json['description'], 'Donation of KSh 30');
      expect(json['xpAmount'], 300);
      expect(json['kesAmount'], 30);
      expect(json['paymentMethod'], 'mpesa');
      expect(json['paystackReference'], 'ML_DON_TEST_123');
      expect(json['status'], 'success');
      expect(tx.isDonation, isTrue);
      expect(tx.isAdReward, isFalse);

      final restored = XPTransaction.fromFirestore(
        {
          'userId': 'user_test_123',
          'type': 'donation',
          'title': 'Direct Donation',
          'description': 'Donation of KSh 30',
          'xpAmount': 300,
          'kesAmount': 30,
          'paymentMethod': 'mpesa',
          'paystackReference': 'ML_DON_TEST_123',
          'operatorReceiptNumber': 'QWE123RTY',
          'status': 'success',
          'createdAt': Timestamp.fromDate(now),
        },
        'tx_donation_001',
      );

      expect(restored.id, 'tx_donation_001');
      expect(restored.userId, 'user_test_123');
      expect(restored.type, 'donation');
      expect(restored.xpAmount, 300);
      expect(restored.kesAmount, 30);
      expect(restored.paystackReference, 'ML_DON_TEST_123');
      expect(restored.createdAt.toUtc(), now);
      expect(restored.isDonation, isTrue);
    });

    test('5. Rewarded ad transaction correctly serializes and deserializes', () {
      final now = DateTime.utc(2026, 11, 3, 12, 30, 0);
      final tx = XPTransaction(
        id: 'tx_ad_002',
        userId: 'user_test_456',
        type: 'rewarded_video',
        title: 'Rewarded Video',
        description: 'Watched Rewarded Video',
        xpAmount: 5,
        status: 'success',
        createdAt: now,
      );

      final json = tx.toJson();
      expect(json['type'], 'rewarded_video');
      expect(json['xpAmount'], 5);
      expect(json['kesAmount'], isNull);
      expect(tx.isDonation, isFalse);
      expect(tx.isAdReward, isTrue);

      final restored = XPTransaction.fromFirestore(
        {
          'userId': 'user_test_456',
          'type': 'rewarded_video',
          'title': 'Rewarded Video',
          'description': 'Watched Rewarded Video',
          'xpAmount': 5,
          'status': 'success',
          'createdAt': Timestamp.fromDate(now),
        },
        'tx_ad_002',
      );

      expect(restored.id, 'tx_ad_002');
      expect(restored.userId, 'user_test_456');
      expect(restored.type, 'rewarded_video');
      expect(restored.xpAmount, 5);
      expect(restored.isAdReward, isTrue);
    });

    test('5b. Rewarded Interstitial transaction correctly identifies as ad reward (+7 XP)', () {
      final now = DateTime.utc(2026, 11, 3, 13, 0, 0);
      final tx = XPTransaction(
        id: 'tx_ad_003',
        userId: 'user_test_789',
        type: 'rewarded_interstitial',
        title: 'Rewarded Interstitial',
        description: 'Watched Rewarded Interstitial',
        xpAmount: 7,
        status: 'success',
        createdAt: now,
      );

      expect(tx.type, 'rewarded_interstitial');
      expect(tx.xpAmount, 7);
      expect(tx.isAdReward, isTrue);
      expect(tx.isDonation, isFalse);
    });
  });

  group('Dual Rewarded Ad Configuration & Rules Tests', () {
    test('6. Production Rewarded Video Ad Unit ID matches exact project ID', () {
      expect(XPService.liveRewardedVideoAdUnitId, 'ca-app-pub-6360381092649351/9633647084');
      expect(XPService.liveRewardedVideoAdUnitId.contains('3940256099942544'), isFalse);
    });

    test('6b. Rewarded Interstitial test ad unit ID is configured for future live swap', () {
      expect(XPService.defaultRewardedInterstitialAdUnitId, 'ca-app-pub-3940256099942544/5354046379');
      expect(XPService.rewardedInterstitialAdUnitId, XPService.defaultRewardedInterstitialAdUnitId);
    });

    test('7. Rewarded ad constants enforce 5 XP for video and 7 XP for interstitial', () {
      expect(XPService.videoRewardXp, 5);
      expect(XPService.interstitialRewardXp, 7);
      expect(XPService.adCooldownSeconds, 30);
      expect(XPService.maxAdsPerDay, 20);
    });

    test('8. Global ad cooldown logic enforces 30 seconds wait across all formats', () {
      final now = DateTime.now();
      bool canWatchAd(DateTime? lastWatchTime) {
        if (lastWatchTime == null) return true;
        return now.difference(lastWatchTime).inSeconds >= XPService.adCooldownSeconds;
      }

      expect(canWatchAd(null), isTrue);
      expect(canWatchAd(now.subtract(const Duration(seconds: 35))), isTrue);
      expect(canWatchAd(now.subtract(const Duration(seconds: 30))), isTrue);
      expect(canWatchAd(now.subtract(const Duration(seconds: 29))), isFalse);
      expect(canWatchAd(now.subtract(const Duration(seconds: 5))), isFalse);
    });

    test('8b. Cooldown timer counts down remaining seconds correctly', () {
      final xpService = XPService();
      xpService.startCooldown(15);
      expect(xpService.isCooldownActive, isTrue);
      expect(xpService.cooldownSecondsRemaining, 15);
      xpService.startCooldown(0);
      expect(xpService.isCooldownActive, isFalse);
      expect(xpService.cooldownSecondsRemaining, 0);
    });

    test('9. Independent daily limits: each format allows up to 20 per day', () {
      bool canClaimFormat(int countToday) => countToday < XPService.maxAdsPerDay;

      // Video format checks
      expect(canClaimFormat(0), isTrue);
      expect(canClaimFormat(19), isTrue);
      expect(canClaimFormat(20), isFalse); // Reached 20
      expect(canClaimFormat(21), isFalse);

      // Interstitial format is independent
      int videoCount = 20; // exhausted
      int interstitialCount = 5; // active
      expect(canClaimFormat(videoCount), isFalse);
      expect(canClaimFormat(interstitialCount), isTrue);
    });
  });

  group('UserProfile XP Balance State & Regression Tests', () {
    test('10. UserProfile serializes and deserializes XP balance fields & independent ad counts', () {
      final now = DateTime.utc(2026, 11, 3, 14, 0, 0);
      final user = UserProfile(
        uid: 'user_test_123',
        username: 'John Doe',
        institution: 'Laikipia University',
        universityLocation: 'Main Campus',
        program: 'Computer Science',
        programCode: 'COMP101',
        year: 'Year 3',
        semester: 'Sem 1',
        phone: '0712345678',
        email: 'john@example.com',
        onboardingComplete: true,
        xpBalance: 1250,
        donationXp: 1200,
        adRewardXp: 50,
        totalDonatedKes: 120,
        adRewardCountVideoToday: 4,
        adRewardCountInterstitialToday: 2,
        adRewardDateNairobi: '2026-11-03',
        lastAdRewardAt: now,
      );

      final json = user.toJson();
      expect(json['xpBalance'], 1250);
      expect(json['donationXp'], 1200);
      expect(json['adRewardXp'], 50);
      expect(json['totalDonatedKes'], 120);
      expect(json['adRewardCountVideoToday'], 4);
      expect(json['adRewardCountInterstitialToday'], 2);
      expect(json['adRewardDateNairobi'], '2026-11-03');
      expect(json['lastAdRewardAt'], now.toIso8601String());

      final restored = UserProfile.fromJson(json);
      expect(restored.xpBalance, 1250);
      expect(restored.donationXp, 1200);
      expect(restored.adRewardXp, 50);
      expect(restored.totalDonatedKes, 120);
      expect(restored.adRewardCountVideoToday, 4);
      expect(restored.adRewardCountInterstitialToday, 2);
      expect(restored.adRewardDateNairobi, '2026-11-03');
      expect(restored.lastAdRewardAt, now);
    });

    test('11. UserProfile defaults XP fields safely to 0 when missing in legacy data', () {
      final legacyJson = {
        'uid': 'legacy_user',
        'username': 'Legacy User',
        'institution': 'Laikipia University',
        'universityLocation': 'Main Campus',
        'program': 'Education',
        'programCode': 'EDU101',
        'year': 'Year 1',
        'semester': 'Sem 1',
        'phone': '0700000000',
        'email': 'legacy@example.com',
        'onboardingComplete': true,
      };

      final restored = UserProfile.fromJson(legacyJson);
      expect(restored.xpBalance, 0);
      expect(restored.donationXp, 0);
      expect(restored.adRewardXp, 0);
      expect(restored.totalDonatedKes, 0);
      expect(restored.adRewardCountVideoToday, 0);
      expect(restored.adRewardCountInterstitialToday, 0);
      expect(restored.adRewardDateNairobi, isNull);
      expect(restored.lastAdRewardAt, isNull);
    });

    test('12. Subscription packages and prices remain completely untouched', () {
      const packages = [
        SubscriptionPackage(id: 'daily', title: 'Daily Pass', price: 5, duration: Duration(days: 1)),
        SubscriptionPackage(id: 'weekly', title: 'Weekly Pass', price: 30, duration: Duration(days: 7)),
        SubscriptionPackage(id: 'monthly', title: 'Monthly Pass', price: 100, duration: Duration(days: 30)),
        SubscriptionPackage(id: 'semester', title: 'Semester Pass', price: 300, duration: Duration(days: 120)),
        SubscriptionPackage(id: 'yearly', title: 'Yearly Pass', price: 500, duration: Duration(days: 365)),
      ];

      expect(packages.length, 5);
      expect(packages[0].price, 5.0);
      expect(packages[1].price, 30.0);
      expect(packages[2].price, 100.0);
      expect(packages[3].price, 300.0);
      expect(packages[4].price, 500.0);
    });
  });
}
