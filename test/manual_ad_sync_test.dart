import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/models/manual_ad.dart';
import 'package:mirror_laikipia/services/interstitial_ad_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InterstitialAdService service;

  setUp(() {
    service = InterstitialAdService();
    service.resetForTesting();
  });

  tearDown(() {
    service.resetForTesting();
  });

  group('Unified Server-Managed Manual Ad Architecture Tests', () {
    test('1. ManualAd serialization round-trip strictly preserves all fields and media type', () {
      final originalVideo = ManualAd(
        id: 'ad_vid_123',
        title: 'Video Deal',
        subtitle: 'Watch our brand promo',
        imageUrl: 'https://ik.imagekit.io/ubgbitinve/MANUAL_ADS/promo.mp4',
        contactUrl: 'https://wa.me/254100000000',
        colorValue: 0xFF20C8FF,
        isActive: true,
        isAsset: false,
        type: 'video',
        mediaFileId: 'file_999',
      );

      final jsonMap = originalVideo.toJson();
      final restored = ManualAd.fromJson(jsonMap);

      expect(restored.id, equals('ad_vid_123'));
      expect(restored.title, equals('Video Deal'));
      expect(restored.subtitle, equals('Watch our brand promo'));
      expect(restored.imageUrl, equals('https://ik.imagekit.io/ubgbitinve/MANUAL_ADS/promo.mp4'));
      expect(restored.contactUrl, equals('https://wa.me/254100000000'));
      expect(restored.colorValue, equals(0xFF20C8FF));
      expect(restored.isActive, isTrue);
      expect(restored.isAsset, isFalse);
      expect(restored.type, equals('video'));
      expect(restored.mediaFileId, equals('file_999'));

      final dialogData = restored.toDialogData();
      expect(dialogData['type'], equals('video'));
      expect(dialogData['url'], equals('https://ik.imagekit.io/ubgbitinve/MANUAL_ADS/promo.mp4'));
      expect(dialogData['isAsset'], isFalse);
    });

    test('2. Emergency bootstrap fallback is isolated and used only when pool is completely empty', () {
      final bootstrap = ManualAd.emergencyBootstrapAd;
      expect(bootstrap.id, equals('emergency_bootstrap_cyber'));
      expect(bootstrap.isAsset, isTrue);

      // On clean reset with no cached server ads, emergency fallback is present
      expect(service.runtimePool.length, equals(1));
      expect(service.runtimePool.first.id, equals('emergency_bootstrap_cyber'));
    });

    test('3. Server-managed ads populate the shared runtime pool and displace emergency bootstrap', () {
      final migratedCyber = ManualAd(
        id: 'default_cyber',
        title: 'Davy Cybers 💻',
        subtitle: 'Professional cyber services',
        imageUrl: 'https://ik.imagekit.io/ubgbitinve/MANUAL_ADS/migrated_ad_cyber_f19k-5YqA.jpeg',
        contactUrl: 'https://wa.me/254108462492',
        colorValue: 0xFF20C8FF,
        isActive: true,
        isAsset: false,
        type: 'image',
        mediaFileId: '6ab76c2aead997d09a0a3b46',
      );

      final migratedData = ManualAd(
        id: 'default_data',
        title: 'Manu Data 🌐',
        subtitle: 'Affordable data plans',
        imageUrl: 'https://ik.imagekit.io/ubgbitinve/MANUAL_ADS/migrated_ad_data_r7GyB3Q2G.jpeg',
        contactUrl: 'https://wa.me/254108462492',
        colorValue: 0xFF00A85A,
        isActive: true,
        isAsset: false,
        type: 'image',
        mediaFileId: '6ab76c31ead997d09a0a4ae1',
      );

      final videoAd = ManualAd(
        id: 'video_ad_1',
        title: 'Video Promo',
        subtitle: 'Dynamic video clip',
        imageUrl: 'https://ik.imagekit.io/ubgbitinve/MANUAL_ADS/154559_xeS1juCav.mp4',
        contactUrl: 'https://wa.me/254108462492',
        colorValue: 0xFFFF8A00,
        isActive: true,
        isAsset: false,
        type: 'video',
        mediaFileId: '6ab75a7cead997d09a928efa',
      );

      // Set authoritative server ads
      service.setCachedServerAdsForTesting([migratedCyber, migratedData, videoAd]);

      final pool = service.runtimePool;
      expect(pool.length, equals(3));
      // Emergency bootstrap should NOT be in the pool once server ads are present
      expect(pool.any((a) => a.id == 'emergency_bootstrap_cyber'), isFalse);

      // Verify all ads have remote ImageKit URLs and isAsset == false
      for (final ad in pool) {
        expect(ad.isAsset, isFalse);
        expect(ad.imageUrl, startsWith('https://ik.imagekit.io/'));
      }
    });

    test('4. Inactive server ads are excluded from the shared runtime pool', () {
      final activeAd = ManualAd(
        id: 'ad_active',
        title: 'Active Promo',
        subtitle: 'Shown to users',
        imageUrl: 'https://ik.imagekit.io/active.jpg',
        contactUrl: 'https://wa.me/254000',
        colorValue: 0xFF00FF00,
        isActive: true,
        isAsset: false,
        type: 'image',
      );

      final inactiveAd = ManualAd(
        id: 'ad_inactive',
        title: 'Paused Promo',
        subtitle: 'Hidden from users',
        imageUrl: 'https://ik.imagekit.io/inactive.jpg',
        contactUrl: 'https://wa.me/254000',
        colorValue: 0xFF00FF00,
        isActive: false, // Paused by admin
        isAsset: false,
        type: 'image',
      );

      service.setCachedServerAdsForTesting([activeAd, inactiveAd]);

      final pool = service.runtimePool;
      expect(pool.length, equals(1));
      expect(pool.first.id, equals('ad_active'));
      expect(pool.any((a) => a.id == 'ad_inactive'), isFalse);
    });

    test('5. Both Banner/Carousel and Interstitial share identical activeManualAds', () {
      final sharedAd = ManualAd(
        id: 'shared_ad_1',
        title: 'Unified Ad',
        subtitle: 'Rendered in banner or full-screen dialog',
        imageUrl: 'https://ik.imagekit.io/shared.jpg',
        contactUrl: 'https://wa.me/254000',
        colorValue: 0xFF20C8FF,
        isActive: true,
        isAsset: false,
        type: 'image',
      );

      service.setCachedServerAdsForTesting([sharedAd]);

      final activeAdsMap = service.activeManualAds;
      expect(activeAdsMap.length, equals(1));
      expect(activeAdsMap.first['id'], equals('shared_ad_1'));
      expect(activeAdsMap.first['title'], equals('Unified Ad'));
      expect(activeAdsMap.first['type'], equals('image'));
      expect(activeAdsMap.first['isAsset'], isFalse);
    });

    test('6. Interstitial cooldown interval is configured to exactly 5 minutes', () {
      expect(
        InterstitialAdService.defaultSessionInterval,
        equals(const Duration(minutes: 5)),
      );
      expect(service.sessionInterval, equals(const Duration(minutes: 5)));
    });

    test('7. Strict non-repeating manual rotation across active ads (never A -> A when alternatives exist)', () {
      final adA = ManualAd(id: 'ad_A', title: 'Ad A', subtitle: 'Sub A', imageUrl: 'https://ik.imagekit.io/a.jpg', contactUrl: 'https://wa.me/1', colorValue: 0xFF111111, isActive: true, isAsset: false, type: 'image');
      final adB = ManualAd(id: 'ad_B', title: 'Ad B', subtitle: 'Sub B', imageUrl: 'https://ik.imagekit.io/b.jpg', contactUrl: 'https://wa.me/2', colorValue: 0xFF222222, isActive: true, isAsset: false, type: 'image');
      final adC = ManualAd(id: 'ad_C', title: 'Ad C', subtitle: 'Sub C', imageUrl: 'https://ik.imagekit.io/c.jpg', contactUrl: 'https://wa.me/3', colorValue: 0xFF333333, isActive: true, isAsset: false, type: 'image');
      final adD = ManualAd(id: 'ad_D', title: 'Ad D', subtitle: 'Sub D', imageUrl: 'https://ik.imagekit.io/d.jpg', contactUrl: 'https://wa.me/4', colorValue: 0xFF444444, isActive: true, isAsset: false, type: 'image');

      service.setCachedServerAdsForTesting([adA, adB, adC, adD]);

      final first = service.getNextManualAd();
      final second = service.getNextManualAd();
      final third = service.getNextManualAd();
      final fourth = service.getNextManualAd();
      final fifth = service.getNextManualAd();

      // No adjacent identical ads
      expect(second.id, isNot(equals(first.id)));
      expect(third.id, isNot(equals(second.id)));
      expect(fourth.id, isNot(equals(third.id)));
      expect(fifth.id, isNot(equals(fourth.id)));

      // Verifies cyclic rotation
      expect([adA.id, adB.id, adC.id, adD.id], contains(first.id));
      expect([adA.id, adB.id, adC.id, adD.id], contains(second.id));
      expect([adA.id, adB.id, adC.id, adD.id], contains(third.id));
      expect([adA.id, adB.id, adC.id, adD.id], contains(fourth.id));
    });

    test('8. Single active manual ad safely reuses the only ad without crashing or looping endlessly', () {
      final singleAd = ManualAd(id: 'only_ad', title: 'Solo Ad', subtitle: 'Sole sponsor', imageUrl: 'https://ik.imagekit.io/solo.jpg', contactUrl: 'https://wa.me/1', colorValue: 0xFF111111, isActive: true, isAsset: false, type: 'image');

      service.setCachedServerAdsForTesting([singleAd]);

      final first = service.getNextManualAd();
      final second = service.getNextManualAd();
      final third = service.getNextManualAd();

      expect(first.id, equals('only_ad'));
      expect(second.id, equals('only_ad'));
      expect(third.id, equals('only_ad'));
    });

    test('9. Inactive or deleted ad is immediately purged from rotation without restart', () {
      final adA = ManualAd(id: 'ad_A', title: 'Ad A', subtitle: 'Sub A', imageUrl: 'https://ik.imagekit.io/a.jpg', contactUrl: 'https://wa.me/1', colorValue: 0xFF111111, isActive: true, isAsset: false, type: 'image');
      final adB = ManualAd(id: 'ad_B', title: 'Ad B', subtitle: 'Sub B', imageUrl: 'https://ik.imagekit.io/b.jpg', contactUrl: 'https://wa.me/2', colorValue: 0xFF222222, isActive: true, isAsset: false, type: 'image');

      service.setCachedServerAdsForTesting([adA, adB]);
      final picked1 = service.getNextManualAd();
      expect([adA.id, adB.id], contains(picked1.id));

      // Admin deactivates adA
      final adADeactivated = adA.copyWith(isActive: false);
      service.setCachedServerAdsForTesting([adADeactivated, adB]);

      // All subsequent rotations must only select adB
      for (int i = 0; i < 5; i++) {
        final next = service.getNextManualAd();
        expect(next.id, equals('ad_B'));
      }
    });

    test('10. Manual idle delay schedule strictly adheres to 5s -> 20s -> 50s -> 60s -> 60s ...', () {
      expect(service.getManualIdleDelay(0), equals(const Duration(seconds: 5)));
      expect(service.getManualIdleDelay(1), equals(const Duration(seconds: 20)));
      expect(service.getManualIdleDelay(2), equals(const Duration(seconds: 50)));
      expect(service.getManualIdleDelay(3), equals(const Duration(seconds: 60)));
      expect(service.getManualIdleDelay(4), equals(const Duration(seconds: 60)));
      expect(service.getManualIdleDelay(10), equals(const Duration(seconds: 60)));
    });

    test('11. Online idle delay schedule strictly adheres to 5s -> 20s -> 60s -> 120s -> 240s -> STOP', () {
      expect(service.getOnlineIdleDelay(0), equals(const Duration(seconds: 5)));
      expect(service.getOnlineIdleDelay(1), equals(const Duration(seconds: 20)));
      expect(service.getOnlineIdleDelay(2), equals(const Duration(seconds: 60)));
      expect(service.getOnlineIdleDelay(3), equals(const Duration(seconds: 120)));
      expect(service.getOnlineIdleDelay(4), equals(const Duration(seconds: 240)));
      expect(service.getOnlineIdleDelay(5), isNull); // STOP
      expect(service.getOnlineIdleDelay(6), isNull); // STOP
    });

    test('12. Reset for testing clears rotation state and stops idle timers', () {
      final adA = ManualAd(id: 'ad_A', title: 'Ad A', subtitle: 'Sub A', imageUrl: 'https://ik.imagekit.io/a.jpg', contactUrl: 'https://wa.me/1', colorValue: 0xFF111111, isActive: true, isAsset: false, type: 'image');
      service.setCachedServerAdsForTesting([adA]);
      service.getNextManualAd();

      expect(service.currentManualAd, isNotNull);

      service.resetForTesting();

      expect(service.currentManualAd, isNull);
      expect(service.previousManualAd, isNull);
      expect(service.currentManualIdleStage, equals(0));
      expect(service.onlineIdleStage, equals(0));
      expect(service.onlineIdleTimerForTesting, isNull);
    });
  });
}
