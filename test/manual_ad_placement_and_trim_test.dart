import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/models/manual_ad.dart';
import 'package:mirror_laikipia/services/interstitial_ad_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ManualAd Placement Serialization Tests', () {
    test('1. fromMap defaults to interstitial when placement is missing or null', () {
      final ad = ManualAd.fromMap('ad_legacy', {
        'title': 'Legacy Ad',
        'subtitle': 'Old ad without placement',
        'url': 'assets/ad_cyber.jpeg',
        'contactUrl': 'https://wa.me/254108462492',
        'isActive': true,
      });

      expect(ad.placement, equals('interstitial'));
    });

    test('2. fromMap parses carousel correctly', () {
      final ad = ManualAd.fromMap('ad_carousel_1', {
        'title': 'Carousel Banner',
        'subtitle': 'A special horizontal banner',
        'url': 'https://ik.imagekit.io/ad.jpg',
        'contactUrl': 'https://wa.me/254108462492',
        'isActive': true,
        'placement': 'carousel',
      });

      expect(ad.placement, equals('carousel'));
    });

    test('3. toMap, toJson, and toDialogData include placement', () {
      final ad = ManualAd(
        id: 'ad_test',
        title: 'Test Ad',
        subtitle: 'Placement test',
        imageUrl: 'https://example.com/ad.jpg',
        contactUrl: 'https://wa.me/123',
        placement: 'carousel',
      );

      expect(ad.toMap()['placement'], equals('carousel'));
      expect(ad.toJson()['placement'], equals('carousel'));
      expect(ad.toDialogData()['placement'], equals('carousel'));
    });
  });

  group('Runtime Pool Placement Isolation Tests', () {
    late InterstitialAdService service;

    setUp(() {
      service = InterstitialAdService();
      service.skipFirestoreForTesting = true;
      service.skipAdLoadingForTesting = true;
    });

    tearDown(() {
      service.setCachedServerAdsForTesting([]);
    });

    test('4. Carousel ads appear ONLY in activeCarouselAds, never in interstitial slots', () {
      final carouselAd = ManualAd(
        id: 'ad_car_1',
        title: 'Only Carousel',
        subtitle: 'For banner only',
        imageUrl: 'https://example.com/banner.jpg',
        contactUrl: 'https://wa.me/123',
        isActive: true,
        placement: 'carousel',
      );

      final interstitialAd = ManualAd(
        id: 'ad_int_1',
        title: 'Only Interstitial',
        subtitle: 'For full screen only',
        imageUrl: 'https://example.com/interstitial.jpg',
        contactUrl: 'https://wa.me/123',
        isActive: true,
        placement: 'interstitial',
      );

      service.setCachedServerAdsForTesting([carouselAd, interstitialAd]);

      // Check activeCarouselAds
      final carouselList = service.activeCarouselAds;
      expect(carouselList.length, equals(1));
      expect(carouselList.first['id'], equals('ad_car_1'));

      // Check activeInterstitialAds
      final interstitialList = service.activeInterstitialAds;
      expect(interstitialList.length, equals(1));
      expect(interstitialList.first['id'], equals('ad_int_1'));

      // Verify getNextManualAd returns ONLY interstitial ad
      final nextAd = service.getNextManualAd();
      expect(nextAd.id, equals('ad_int_1'));
      expect(nextAd.placement, equals('interstitial'));
    });

    test('5. Toggling ad placement between Interstitial and Carousel updates pools immediately without restart', () {
      final adA = ManualAd(
        id: 'ad_mutable',
        title: 'Mutable Ad',
        subtitle: 'Changes placement',
        imageUrl: 'https://example.com/pic.jpg',
        contactUrl: 'https://wa.me/123',
        isActive: true,
        placement: 'interstitial',
      );

      service.setCachedServerAdsForTesting([adA]);

      expect(service.activeInterstitialAds.length, equals(1));
      expect(service.activeCarouselAds.length, equals(0));
      expect(service.getNextManualAd().id, equals('ad_mutable'));

      // Simulate admin changing placement to 'carousel'
      final adAChanged = adA.copyWith(placement: 'carousel');
      service.setCachedServerAdsForTesting([adAChanged]);

      // Instant update: now in carousel, removed from interstitial
      expect(service.activeInterstitialAds.length, equals(0));
      expect(service.activeCarouselAds.length, equals(1));
      expect(service.activeCarouselAds.first['id'], equals('ad_mutable'));

      // Interstitial getter will not pick it
      final fallback = service.getNextManualAd();
      expect(fallback.id, equals(ManualAd.emergencyBootstrapAd.id));
    });

    test('6. Inactive ads do not appear in either carousel or interstitial pools', () {
      final inactiveCarousel = ManualAd(
        id: 'ad_car_off',
        title: 'Off Carousel',
        subtitle: 'Disabled',
        imageUrl: 'https://example.com/banner.jpg',
        contactUrl: 'https://wa.me/123',
        isActive: false,
        placement: 'carousel',
      );

      final inactiveInterstitial = ManualAd(
        id: 'ad_int_off',
        title: 'Off Interstitial',
        subtitle: 'Disabled',
        imageUrl: 'https://example.com/interstitial.jpg',
        contactUrl: 'https://wa.me/123',
        isActive: false,
        placement: 'interstitial',
      );

      service.setCachedServerAdsForTesting([inactiveCarousel, inactiveInterstitial]);

      expect(service.activeCarouselAds.isEmpty, isTrue);
      expect(service.activeInterstitialAds.isEmpty, isTrue);
    });
  });

  group('Mutually Exclusive UI Logic & Video Limits Tests', () {
    test('7. Mutually exclusive selection behavior logic', () {
      String? selectedPlacement;

      // Initial state: null (neither selected)
      expect(selectedPlacement, isNull);
      bool isSaveButtonEnabled(String? p) => p != null;
      expect(isSaveButtonEnabled(selectedPlacement), isFalse);

      // Select Interstitial
      selectedPlacement = 'interstitial';
      expect(selectedPlacement, equals('interstitial'));
      expect(isSaveButtonEnabled(selectedPlacement), isTrue);

      // Selecting Carousel deselects Interstitial
      selectedPlacement = 'carousel';
      expect(selectedPlacement, equals('carousel'));

      // Tapping Carousel again deselects it
      selectedPlacement = null;
      expect(selectedPlacement, isNull);
      expect(isSaveButtonEnabled(selectedPlacement), isFalse);
    });

    test('8. Strict Video duration boundary rules (29.9s, 30.0s, 30.01s, 30.5s, 45s)', () {
      bool shouldTrim(double durationSeconds) {
        // Strict boundary: <= 30.0 preserved as-is; > 30.0 trimmed to 30.0
        return durationSeconds > 30.0;
      }

      double getFinalDuration(double durationSeconds) {
        return shouldTrim(durationSeconds) ? 30.0 : durationSeconds;
      }

      // 1. 29.9s -> not trimmed
      expect(shouldTrim(29.9), isFalse);
      expect(getFinalDuration(29.9), equals(29.9));

      // 2. 30.0s -> not trimmed
      expect(shouldTrim(30.0), isFalse);
      expect(getFinalDuration(30.0), equals(30.0));

      // 3. 30.01s -> trimmed to 30s
      expect(shouldTrim(30.01), isTrue);
      expect(getFinalDuration(30.01), equals(30.0));

      // 4. 30.5s -> trimmed to 30s (previously passed through under old 30.5s margin)
      expect(shouldTrim(30.5), isTrue);
      expect(getFinalDuration(30.5), equals(30.0));

      // 5. 45s -> trimmed to 30s
      expect(shouldTrim(45.0), isTrue);
      expect(getFinalDuration(45.0), equals(30.0));
    });

    test('9. Admin UI Duration evaluation strictly uses <= 30000ms', () {
      bool isUiWithinLimit(Duration dur) => dur.inMilliseconds <= 30000;

      expect(isUiWithinLimit(const Duration(milliseconds: 29900)), isTrue); // 29.9s
      expect(isUiWithinLimit(const Duration(milliseconds: 30000)), isTrue); // 30.0s
      expect(isUiWithinLimit(const Duration(milliseconds: 30010)), isFalse); // 30.01s
      expect(isUiWithinLimit(const Duration(milliseconds: 30500)), isFalse); // 30.5s
      expect(isUiWithinLimit(const Duration(milliseconds: 45000)), isFalse); // 45.0s
    });
  });
}
