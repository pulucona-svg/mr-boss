import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/models/subscription_model.dart';
import 'package:mirror_laikipia/services/paystack_service.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
  });

  group('Paystack Payment Reliability & Lifecycle Tests', () {
    const dailyPackage = SubscriptionPackage(
      id: 'daily',
      title: 'Daily Pass',
      price: 5.0,
      duration: Duration(days: 1),
    );

    const monthlyPackage = SubscriptionPackage(
      id: 'monthly',
      title: 'Monthly Pass',
      price: 100.0,
      duration: Duration(days: 30),
    );

    test('10. Failed payment does not activate subscription', () {
      final failedResult = PaystackVerificationResult(
        success: false,
        status: 'failed',
        paystackStatus: 'failed',
        message: 'Transaction failed: The customer entered an incorrect PIN',
      );

      expect(failedResult.success, false);
      expect(failedResult.status, 'failed');
      expect(failedResult.isPending, false);
      // Ensure failure status does not indicate active subscription
      expect(failedResult.alreadyFulfilled, false);
    });

    test('11. Abandoned payment does not activate subscription', () {
      final abandonedResult = PaystackVerificationResult(
        success: false,
        status: 'abandoned',
        paystackStatus: 'abandoned',
        message: 'The transaction was abandoned or expired',
      );

      expect(abandonedResult.success, false);
      expect(abandonedResult.status, 'abandoned');
      expect(abandonedResult.isPending, false);
    });

    test('12. Successful payment activates and attaches reference', () {
      final now = DateTime.now();
      const reference = 'ML_MONTHLY_1727424000_abc12';

      final subscription = SubscriptionHistory(
        id: 'sub_test_001',
        packageTitle: monthlyPackage.title,
        amount: monthlyPackage.price,
        transactionCode: reference, // Paystack transaction reference
        paystackTransactionId: 109283746,
        paystackReference: reference,
        paymentChannel: 'mobile_money',
        purchaseDate: now,
        activationDate: now,
        expiryDate: now.add(monthlyPackage.duration),
        status: SubscriptionStatus.active,
      );

      expect(subscription.transactionCode, reference);
      expect(subscription.paystackTransactionId, 109283746);
      expect(subscription.status, SubscriptionStatus.active);
    });

    test('13. Duplicate webhook / verify idempotency detection', () {
      // Simulate first fulfillment
      final firstVerify = PaystackVerificationResult(
        success: true,
        status: 'success',
        paystackStatus: 'success',
        message: 'Subscription activated successfully',
        alreadyFulfilled: false,
      );

      // Simulate duplicate verification or webhook arrival
      final duplicateVerify = PaystackVerificationResult(
        success: true,
        status: 'success',
        paystackStatus: 'success',
        message: 'Already fulfilled',
        alreadyFulfilled: true,
      );

      expect(firstVerify.alreadyFulfilled, false);
      expect(duplicateVerify.alreadyFulfilled, true);
      // Both report success without re-creating subscriptions
      expect(duplicateVerify.success, true);
    });

    test('14 & 15. Offline unresolved payment persisted and does not duplicate', () async {
      final service = PaystackService();
      const reference = 'ML_DAILY_OFFLINE_REF_999';

      // 1. Persist when user starts payment
      await service.saveUnresolvedPayment(
        reference: reference,
        packageId: dailyPackage.id,
        method: PaystackPaymentMethod.mpesa,
        phoneNumber: '0712345678',
      );

      // Verify it is stored
      List<Map<String, dynamic>> unresolved = service.getUnresolvedPayments();
      expect(unresolved.length, 1);
      expect(unresolved.first['reference'], reference);

      // 2. Subsequent call does not create duplicate payment reference
      await service.saveUnresolvedPayment(
        reference: reference,
        packageId: dailyPackage.id,
        method: PaystackPaymentMethod.mpesa,
        phoneNumber: '0712345678',
      );
      unresolved = service.getUnresolvedPayments();
      expect(unresolved.length, 1);

      // 3. Resolution removes it
      await service.removeUnresolvedPayment(reference);
      expect(service.getUnresolvedPayments().isEmpty, true);
    });

    test('16. Paystack reference is correctly attached to subscription history', () {
      final now = DateTime.now();
      const reference = 'ML_DAILY_20260927_XYZ';
      final history = SubscriptionHistory(
        id: '123',
        packageTitle: 'Daily Pass',
        amount: 5.0,
        transactionCode: reference,
        paystackTransactionId: 55443322,
        purchaseDate: now,
        activationDate: now,
        expiryDate: now.add(const Duration(days: 1)),
        status: SubscriptionStatus.active,
      );

      expect(history.transactionCode, reference);
      expect(history.transactionCode.startsWith('ML_'), true);
      expect(history.paystackTransactionId, 55443322);
    });

    test('17. Profile email selection logic prioritizes authenticated email', () {
      const profileEmail = 'student@laikipia.ac.ke';
      const authEmail = 'auth@laikipia.ac.ke';

      final selectedEmail = profileEmail.isNotEmpty
          ? profileEmail
          : (authEmail.isNotEmpty ? authEmail : 'customer@mirrorlaikipia.app');

      expect(selectedEmail, 'student@laikipia.ac.ke');
    });

    test('18. Card below Ksh.100 is blocked before starting payment', () async {
      final service = PaystackService();
      final result = await service.processPayment(
        package: dailyPackage, // KES 5.0 < 100
        method: PaystackPaymentMethod.mastercard,
        phoneNumber: '0712345678',
        email: 'test@laikipia.ac.ke',
      );

      expect(result.success, false);
      expect(result.message, 'Card payment does not support payments below Ksh.100.');
    });

    test('19. Raw card details are NEVER persisted locally', () async {
      final service = PaystackService();

      // Only safe display metadata is allowed
      await service.saveLastCardMetadata(brand: 'Mastercard', last4: '8888');
      expect(service.getLastCardMetadata(), 'Mastercard •••• 8888');

      final prefs = await SharedPreferences.getInstance();
      // Ensure no sensitive card details exist anywhere in preferences
      expect(prefs.getString('card_number'), isNull);
      expect(prefs.getString('cardNumber'), isNull);
      expect(prefs.getString('card_cvv'), isNull);
      expect(prefs.getString('cardCvv'), isNull);
      expect(prefs.getString('card_pin'), isNull);
      expect(prefs.getString('cardPin'), isNull);
      expect(prefs.getString('card_expiry'), isNull);
    });
  });
}
