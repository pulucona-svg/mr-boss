import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mirror_laikipia/models/subscription_model.dart';
import 'package:mirror_laikipia/services/subscription_service.dart';
import 'package:mirror_laikipia/screens/subscription_screen.dart';
import 'package:mirror_laikipia/providers/service_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Promotional Trial Model Tests', () {
    test('PromotionalStageInfo.fromMap correctly parses valid data', () {
      final map = {
        'stageNumber': 1,
        'title': '2-Month Free Trial',
        'durationDescription': '2 calendar months',
        'claimedCount': 12,
        'maxClaims': 50,
        'remainingClaims': 38,
        'deadlineUtc': '2026-12-30T23:59:59.000Z',
      };

      final info = PromotionalStageInfo.fromMap(map);
      expect(info.stageNumber, 1);
      expect(info.title, '2-Month Free Trial');
      expect(info.durationDescription, '2 calendar months');
      expect(info.claimedCount, 12);
      expect(info.maxClaims, 50);
      expect(info.remainingClaims, 38);
      expect(info.deadlineUtc.isUtc, isTrue);
      expect(info.deadlineUtc.year, 2026);
    });

    test('PromotionalCampaignState.fromMap correctly parses full state', () {
      final map = {
        'campaignActive': true,
        'activeStage': {
          'stageNumber': 2,
          'title': '1-Month Free Trial',
          'durationDescription': '1 calendar month',
          'claimedCount': 10,
          'maxClaims': 45,
          'remainingClaims': 35,
          'deadlineUtc': '2027-03-01T23:59:59.000Z',
        },
        'userStatus': {
          'isAuthenticated': true,
          'hasClaimed': false,
          'isEligible': true,
        },
      };

      final state = PromotionalCampaignState.fromMap(map);
      expect(state.campaignActive, isTrue);
      expect(state.isEligible, isTrue);
      expect(state.hasClaimed, isFalse);
      expect(state.activeStage?.stageNumber, 2);
      expect(state.activeStage?.title, '1-Month Free Trial');
      expect(state.activeStage?.remainingClaims, 35);
    });
  });

  group('Promotional Trial Download Limit Tests', () {
    final service = SubscriptionService();

    test('Recognizes promotional trial passes and standard passes', () {
      expect(service.getDownloadLimit('Daily Pass'), 10);
      expect(service.getDownloadLimit('Weekly Pass'), 30);
      expect(service.getDownloadLimit('1-Week Free Trial'), 30);
      expect(service.getDownloadLimit('Monthly Pass'), 50);
      expect(service.getDownloadLimit('1-Month Free Trial'), 50);
      expect(service.getDownloadLimit('2-Month Free Trial'), 150);
      expect(service.getDownloadLimit('Semester Pass'), 150);
      expect(service.getDownloadLimit('Yearly Pass'), -1);
      expect(service.getDownloadLimit('Promotional Pass (2-Month)'), 100);
      expect(service.getDownloadLimit('Unknown Pass'), 0);
    });
  });

  group('SubscriptionScreen Promotional UI Tests', () {
    testWidgets('Renders special promotion card when user is eligible', (tester) async {
      final service = SubscriptionService();
      service.clear();

      // Configure eligible campaign state for testing
      service.setPromotionalStateForTesting(
        PromotionalCampaignState(
          campaignActive: true,
          isEligible: true,
          hasClaimed: false,
          activeStage: PromotionalStageInfo(
            stageNumber: 1,
            title: '2-Month Free Trial',
            durationDescription: '2 calendar months',
            claimedCount: 5,
            maxClaims: 50,
            remainingClaims: 45,
            deadlineUtc: DateTime.utc(2026, 12, 30, 23, 59, 59),
          ),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subscriptionServiceProvider.overrideWith((ref) => service),
          ],
          child: const MaterialApp(
            home: SubscriptionScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify SPECIAL PROMOTION banner appears
      expect(find.text('SPECIAL PROMOTION'), findsOneWidget);
      expect(find.text('STAGE 1 • LIMITED CLAIMS'), findsOneWidget);
      expect(find.text('2-Month Free Trial'), findsOneWidget);
      expect(find.text('45 of 50 left'), findsOneWidget);
      expect(find.text('Claim Free Trial'), findsOneWidget);
      expect(find.text('FREE'), findsOneWidget);

      // Verify standard packages still exist
      expect(find.text('SELECT A PACKAGE'), findsOneWidget);
      expect(find.text('Daily Pass'), findsOneWidget);
      expect(find.text('Weekly Pass'), findsOneWidget);
    });

    testWidgets('Hides promotion card when user has already claimed', (tester) async {
      final service = SubscriptionService();
      service.clear();

      // Configure claimed state
      service.setPromotionalStateForTesting(
        PromotionalCampaignState(
          campaignActive: true,
          isEligible: false,
          hasClaimed: true,
          ineligibilityReason: 'You have already claimed a promotional trial.',
          activeStage: PromotionalStageInfo(
            stageNumber: 1,
            title: '2-Month Free Trial',
            durationDescription: '2 calendar months',
            claimedCount: 6,
            maxClaims: 50,
            remainingClaims: 44,
            deadlineUtc: DateTime.utc(2026, 12, 30, 23, 59, 59),
          ),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subscriptionServiceProvider.overrideWith((ref) => service),
          ],
          child: const MaterialApp(
            home: SubscriptionScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify SPECIAL PROMOTION banner does NOT appear
      expect(find.text('SPECIAL PROMOTION'), findsNothing);
      expect(find.text('Claim Free Trial'), findsNothing);

      // Standard packages must still be shown
      expect(find.text('SELECT A PACKAGE'), findsOneWidget);
      expect(find.text('Daily Pass'), findsOneWidget);
    });

    testWidgets('Renders PROMOTIONAL OFFER notice card when user has active paid subscription', (tester) async {
      final service = SubscriptionService();
      service.clear();

      final paidExpiry = DateTime.utc(2026, 11, 15, 12, 0, 0);

      service.setPromotionalStateForTesting(
        PromotionalCampaignState(
          campaignActive: true,
          isEligible: false,
          hasClaimed: false,
          ineligibilityReason: 'active_paid_subscription',
          latestPaidExpiry: paidExpiry,
          activeStage: PromotionalStageInfo(
            stageNumber: 1,
            title: '2-Month Free Trial',
            durationDescription: '2 calendar months',
            claimedCount: 15,
            maxClaims: 50,
            remainingClaims: 35,
            deadlineUtc: DateTime.utc(2026, 12, 30, 23, 59, 59),
          ),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subscriptionServiceProvider.overrideWith((ref) => service),
          ],
          child: const MaterialApp(
            home: SubscriptionScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify PROMOTIONAL OFFER notice card is displayed explaining ineligibility
      expect(find.text('PROMOTIONAL OFFER'), findsOneWidget);
      expect(find.text('2-Month Free Trial (2 calendar months)'), findsOneWidget);
      expect(find.textContaining('You currently have an active paid subscription'), findsOneWidget);
      expect(find.text('Claim Free Trial'), findsNothing);
    });
  });

  group('Dynamic Temporal Entitlement Evaluation Tests', () {
    final activationDate = DateTime(2026, 10, 13, 12, 0, 0);
    final expiryDate = DateTime(2026, 10, 20, 12, 0, 0);

    test('Effective entitlement at the exact activation time (inclusive)', () {
      final sub = SubscriptionHistory(
        id: '1',
        packageTitle: 'Weekly Pass',
        amount: 30,
        transactionCode: 'TX_1',
        purchaseDate: activationDate,
        activationDate: activationDate,
        expiryDate: expiryDate,
        status: SubscriptionStatus.active,
      );

      // activationDate <= time
      expect(sub.isEffectiveAt(activationDate), isTrue);
    });

    test('Effective entitlement at the exact expiry time (exclusive)', () {
      final sub = SubscriptionHistory(
        id: '1',
        packageTitle: 'Weekly Pass',
        amount: 30,
        transactionCode: 'TX_1',
        purchaseDate: activationDate,
        activationDate: activationDate,
        expiryDate: expiryDate,
        status: SubscriptionStatus.active,
      );

      // time < expiryDate
      expect(sub.isEffectiveAt(expiryDate), isFalse);
    });

    test('Effective entitlement inside window and outside window', () {
      final sub = SubscriptionHistory(
        id: '1',
        packageTitle: 'Weekly Pass',
        amount: 30,
        transactionCode: 'TX_1',
        purchaseDate: activationDate,
        activationDate: activationDate,
        expiryDate: expiryDate,
        status: SubscriptionStatus.active,
      );

      // 1 minute before activation
      expect(sub.isEffectiveAt(activationDate.subtract(const Duration(minutes: 1))), isFalse);

      // Halfway through window
      expect(sub.isEffectiveAt(DateTime(2026, 10, 16, 12, 0, 0)), isTrue);

      // 1 second after expiry
      expect(sub.isEffectiveAt(expiryDate.add(const Duration(seconds: 1))), isFalse);
    });

    test('Terminated entitlement fails closed even if time is inside window', () {
      final sub = SubscriptionHistory(
        id: '1',
        packageTitle: 'Weekly Pass',
        amount: 30,
        transactionCode: 'TX_1',
        purchaseDate: activationDate,
        activationDate: activationDate,
        expiryDate: expiryDate,
        status: SubscriptionStatus.terminated,
      );

      expect(sub.isEffectiveAt(DateTime(2026, 10, 15)), isFalse);
    });

    test('Unknown or malformed subscription status fails closed', () {
      final sub = SubscriptionHistory(
        id: '1',
        packageTitle: 'Unknown Pass',
        amount: 30,
        transactionCode: 'TX_1',
        purchaseDate: activationDate,
        activationDate: activationDate,
        expiryDate: expiryDate,
        status: SubscriptionStatus.unknown,
      );

      expect(sub.isEffectiveAt(DateTime(2026, 10, 15)), isFalse);
    });

    test('Unknown or malformed JSON status parses as SubscriptionStatus.unknown', () {
      final json = {
        'id': 'sub_malformed',
        'packageTitle': 'Corrupted Pass',
        'amount': 50.0,
        'transactionCode': 'TX_BAD',
        'purchaseDate': activationDate.toIso8601String(),
        'activationDate': activationDate.toIso8601String(),
        'expiryDate': expiryDate.toIso8601String(),
        'status': 'corrupted_or_unexpected_value',
        'downloadCount': 0,
      };

      final parsed = SubscriptionHistory.fromJson(json);
      expect(parsed.status, SubscriptionStatus.unknown);
      expect(parsed.isEffectiveAt(DateTime(2026, 10, 15)), isFalse);

      final firestoreParsed = SubscriptionHistory.fromFirestore(json, 'sub_malformed');
      expect(firestoreParsed.status, SubscriptionStatus.unknown);
      expect(firestoreParsed.isEffectiveAt(DateTime(2026, 10, 15)), isFalse);
    });

    test('Expired entitlement fails closed even if expiryDate is in the future', () {
      final sub = SubscriptionHistory(
        id: 'sub_expired_future',
        packageTitle: 'Weekly Pass',
        amount: 30,
        transactionCode: 'TX_EXP',
        purchaseDate: activationDate,
        activationDate: activationDate,
        expiryDate: expiryDate, // In the future relative to test evaluation instant
        status: SubscriptionStatus.expired,
      );

      // Even though activationDate <= 2026-10-15 < expiryDate, expired status MUST fail closed
      expect(sub.isEffectiveAt(DateTime(2026, 10, 15)), isFalse);
    });

    test('Refunded, revoked, and cancelled statuses parse as unknown and fail closed', () {
      for (final badStatus in ['refunded', 'revoked', 'cancelled']) {
        final json = {
          'id': 'sub_$badStatus',
          'packageTitle': 'Pass',
          'amount': 30.0,
          'transactionCode': 'TX_$badStatus',
          'purchaseDate': activationDate.toIso8601String(),
          'activationDate': activationDate.toIso8601String(),
          'expiryDate': expiryDate.toIso8601String(),
          'status': badStatus,
          'downloadCount': 0,
        };

        final parsed = SubscriptionHistory.fromJson(json);
        expect(parsed.status, SubscriptionStatus.unknown, reason: 'Status $badStatus should map to unknown');
        expect(parsed.isEffectiveAt(DateTime(2026, 10, 15)), isFalse);

        final firestoreParsed = SubscriptionHistory.fromFirestore(json, 'sub_$badStatus');
        expect(firestoreParsed.status, SubscriptionStatus.unknown);
        expect(firestoreParsed.isEffectiveAt(DateTime(2026, 10, 15)), isFalse);
      }
    });

    test('Valid queued pass activates at intended boundary', () {
      final queuedActivation = DateTime(2026, 10, 20, 12, 0, 0);
      final queuedExpiry = DateTime(2026, 10, 27, 12, 0, 0);
      final sub = SubscriptionHistory(
        id: 'queued_sub',
        packageTitle: 'Weekly Pass',
        amount: 30,
        transactionCode: 'TX_Q',
        purchaseDate: DateTime(2026, 10, 13, 12, 0, 0),
        activationDate: queuedActivation,
        expiryDate: queuedExpiry,
        status: SubscriptionStatus.queued,
      );

      // Before activationDate
      expect(sub.isEffectiveAt(queuedActivation.subtract(const Duration(seconds: 1))), isFalse);

      // Exact activation boundary (inclusive)
      expect(sub.isEffectiveAt(queuedActivation), isTrue);

      // Mid-flight
      expect(sub.isEffectiveAt(DateTime(2026, 10, 23, 12, 0, 0)), isTrue);

      // Exact expiry boundary (exclusive)
      expect(sub.isEffectiveAt(queuedExpiry), isFalse);
    });

    test('Expired subscriptions are excluded from queuedSubscriptions even if timestamps are future', () {
      final service = SubscriptionService();
      service.clear();

      final futureDate = DateTime.now().add(const Duration(days: 5));
      final farFutureDate = DateTime.now().add(const Duration(days: 12));

      final expiredWithFutureDates = SubscriptionHistory(
        id: 'exp_future',
        packageTitle: 'Corrupted Pass',
        amount: 30,
        transactionCode: 'TX_EXP',
        purchaseDate: DateTime.now(),
        activationDate: futureDate,
        expiryDate: farFutureDate,
        status: SubscriptionStatus.expired,
      );

      final validQueued = SubscriptionHistory(
        id: 'valid_q',
        packageTitle: 'Weekly Pass',
        amount: 30,
        transactionCode: 'TX_VALID',
        purchaseDate: DateTime.now(),
        activationDate: futureDate,
        expiryDate: farFutureDate,
        status: SubscriptionStatus.queued,
      );

      service.setHistoryForTesting([expiredWithFutureDates, validQueued]);

      final queued = service.queuedSubscriptions;
      expect(queued.length, 1);
      expect(queued.first.id, 'valid_q');
    });
  });
}
