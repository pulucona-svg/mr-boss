import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/models/manual_ad.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/services/manual_ad_view_tracker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ManualAdViewTracker tracker;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
    await PersistenceService().clearAll();

    tracker = ManualAdViewTracker();
    tracker.resetForTesting();
    tracker.isOfflineOverrideForTesting = () => false;
  });

  tearDown(() {
    tracker.resetForTesting();
  });

  group('ManualAdViewTracker Unit Tests', () {
    test('1. recordDisplay increments pending view count locally without network', () async {
      await tracker.initialize();

      expect(tracker.totalPendingViews, equals(0));
      expect(tracker.getPendingViews('ad_safari_01'), equals(0));

      tracker.recordDisplay('ad_safari_01');
      tracker.recordDisplay('ad_safari_01');
      tracker.recordDisplay('ad_campus_02');

      expect(tracker.getPendingViews('ad_safari_01'), equals(2));
      expect(tracker.getPendingViews('ad_campus_02'), equals(1));
      expect(tracker.totalPendingViews, equals(3));
    });

    test('2. recordDisplay ignores invalid IDs and emergency bootstrap', () async {
      await tracker.initialize();

      tracker.recordDisplay('');
      tracker.recordDisplay('   ');
      tracker.recordDisplay('emergency_bootstrap_cyber');

      expect(tracker.totalPendingViews, equals(0));
    });

    test('3. Disk persistence saves and reloads pending views', () async {
      await tracker.initialize();

      tracker.recordDisplay('ad_laikipia_print');
      tracker.recordDisplay('ad_laikipia_print');
      expect(tracker.getPendingViews('ad_laikipia_print'), equals(2));

      final raw = PersistenceService().getString('manual_ad_pending_views_v1');
      expect(raw, isNotNull);
      expect(raw, contains('"ad_laikipia_print":2'));
    });

    test('4. Disk reload restores un-synced counts upon initialization', () async {
      // Pre-seed disk via PersistenceService directly
      PersistenceService().setString(
        'manual_ad_pending_views_v1',
        '{"ad_res_1": 4, "ad_res_2": 7}',
      );

      await tracker.initialize();

      expect(tracker.getPendingViews('ad_res_1'), equals(4));
      expect(tracker.getPendingViews('ad_res_2'), equals(7));
      expect(tracker.totalPendingViews, equals(11));
    });

    test('5. Offline guard prevents network sync while offline', () async {
      tracker.isOfflineOverrideForTesting = () => true;
      await tracker.initialize();

      tracker.recordDisplay('ad_offline_test');
      expect(tracker.getPendingViews('ad_offline_test'), equals(1));

      bool syncAttempted = false;
      tracker.syncCallOverrideForTesting = ({required batchId, required deltas}) async {
        syncAttempted = true;
        return true;
      };

      final result = await tracker.syncPendingViews();
      expect(result, isFalse);
      expect(syncAttempted, isFalse);
      expect(tracker.getPendingViews('ad_offline_test'), equals(1));
    });

    test('6. Snapshot isolation deducts only batch quantities on success', () async {
      tracker.isOfflineOverrideForTesting = () => false;
      await tracker.initialize();

      tracker.recordDisplay('ad_promo_A');
      tracker.recordDisplay('ad_promo_A'); // 2 views
      tracker.recordDisplay('ad_promo_B'); // 1 view

      expect(tracker.getPendingViews('ad_promo_A'), equals(2));
      expect(tracker.getPendingViews('ad_promo_B'), equals(1));

      String? sentBatchId;
      Map<String, int>? sentDeltas;

      tracker.syncCallOverrideForTesting = ({required batchId, required deltas}) async {
        sentBatchId = batchId;
        sentDeltas = deltas;

        // Simulate new view occurring while sync is in-flight
        tracker.recordDisplay('ad_promo_A'); // 3rd view for A

        return true; // Server responds success
      };

      final bool success = await tracker.syncPendingViews();

      expect(success, isTrue);
      expect(sentBatchId, isNotNull);
      expect(sentBatchId!.isNotEmpty, isTrue);
      expect(sentDeltas, equals({'ad_promo_A': 2, 'ad_promo_B': 1}));

      // Ad A had 2 + 1 = 3 views. Deducted 2. Remaining must be 1.
      expect(tracker.getPendingViews('ad_promo_A'), equals(1));
      // Ad B had 1 view. Deducted 1. Remaining must be 0.
      expect(tracker.getPendingViews('ad_promo_B'), equals(0));
      expect(tracker.totalPendingViews, equals(1));
    });

    test('7. Network or server error retains pending views intact', () async {
      tracker.isOfflineOverrideForTesting = () => false;
      await tracker.initialize();

      tracker.recordDisplay('ad_fail_safe');
      expect(tracker.getPendingViews('ad_fail_safe'), equals(1));

      tracker.syncCallOverrideForTesting = ({required batchId, required deltas}) async {
        throw Exception('Server 500 internal error or network timeout');
      };

      final bool success = await tracker.syncPendingViews();

      expect(success, isFalse);
      expect(tracker.getPendingViews('ad_fail_safe'), equals(1));
      expect(tracker.totalPendingViews, equals(1));
    });

    test('8. ManualAd data model preserves and serializes views count correctly', () {
      final adMap = {
        'id': 'test_ad_101',
        'title': 'Laikipia Bookstore',
        'subtitle': 'Get 20% off all textbooks this semester',
        'imageUrl': 'https://example.com/books.jpg',
        'contactUrl': 'https://wa.me/254700000000',
        'colorValue': 0xFF20C8FF,
        'isActive': true,
        'isAsset': false,
        'type': 'image',
        'placement': 'carousel',
        'views': 1245,
      };

      final ad = ManualAd.fromMap('test_ad_101', adMap);
      expect(ad.views, equals(1245));

      final serializedMap = ad.toMap();
      expect(serializedMap['views'], equals(1245));

      final copiedAd = ad.copyWith(views: 1246);
      expect(copiedAd.views, equals(1246));
      expect(copiedAd.id, equals('test_ad_101'));
      expect(copiedAd.title, equals('Laikipia Bookstore'));
    });
  });
}
