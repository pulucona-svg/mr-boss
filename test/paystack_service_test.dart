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

  group('PaystackService Kenyan Phone Formatting & Normalization Tests', () {
    test('1. 10-digit 07XXXXXXXX accepted', () {
      expect(PaystackService.isValidKenyaPhone('0712345678'), true);
      expect(PaystackService.isValidKenyaPhone('0799887766'), true);
    });

    test('2. 10-digit 01XXXXXXXX accepted', () {
      expect(PaystackService.isValidKenyaPhone('0112345678'), true);
      expect(PaystackService.isValidKenyaPhone('0100123456'), true);
    });

    test('3. 9 digits invalid', () {
      expect(PaystackService.isValidKenyaPhone('071234567'), false);
      expect(PaystackService.isValidKenyaPhone('011234567'), false);
    });

    test('4. 11 digits invalid', () {
      expect(PaystackService.isValidKenyaPhone('07123456789'), false);
      expect(PaystackService.isValidKenyaPhone('01123456789'), false);
    });

    test('5. Non-Kenyan prefix invalid', () {
      expect(PaystackService.isValidKenyaPhone('0512345678'), false);
      expect(PaystackService.isValidKenyaPhone('0212345678'), false);
    });

    test('6. +254 backend normalization works', () {
      expect(PaystackService.normalizeKenyanPhone('0712345678'), '+254712345678');
      expect(PaystackService.normalizeKenyanPhone('0112345678'), '+254112345678');
      expect(PaystackService.normalizeKenyanPhone('254712345678'), '+254712345678');
      expect(PaystackService.normalizeKenyanPhone('+254712345678'), '+254712345678');
    });

    test('7. Profile +254 phone displays locally as 07/01 format', () {
      expect(PaystackService.formatToLocalKenyaPhone('+254712345678'), '0712345678');
      expect(PaystackService.formatToLocalKenyaPhone('+254112345678'), '0112345678');
      expect(PaystackService.formatToLocalKenyaPhone('254712345678'), '0712345678');
      expect(PaystackService.formatToLocalKenyaPhone('0712345678'), '0712345678');
      expect(PaystackService.formatToLocalKenyaPhone('+254 712 345 678'), '0712345678');
      expect(PaystackService.formatToLocalKenyaPhone('0712-345-678'), '0712345678');
    });
  });

  group('PaystackService Memory & Security Tests', () {
    test('8. M-PESA remembers last successful number', () async {
      final service = PaystackService();
      expect(service.getLastSuccessfulPhone(PaystackPaymentMethod.mpesa), isNull);

      await service.saveLastSuccessfulPhone(PaystackPaymentMethod.mpesa, '0712345678');
      expect(service.getLastSuccessfulPhone(PaystackPaymentMethod.mpesa), '0712345678');
      // Does not alter Airtel
      expect(service.getLastSuccessfulPhone(PaystackPaymentMethod.airtelMoney), isNull);
    });

    test('9. Airtel remembers last successful number', () async {
      final service = PaystackService();
      await service.saveLastSuccessfulPhone(PaystackPaymentMethod.airtelMoney, '0112345678');
      expect(service.getLastSuccessfulPhone(PaystackPaymentMethod.airtelMoney), '0112345678');
    });

    test('10. Safe card metadata memory (brand + last4 only, no raw credentials)', () async {
      final service = PaystackService();
      await service.saveLastCardMetadata(brand: 'Mastercard', last4: '4242');

      final display = service.getLastCardMetadata();
      expect(display, 'Mastercard •••• 4242');

      // Verify raw card number or CVV is NEVER stored in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('card_number'), isNull);
      expect(prefs.getString('card_cvv'), isNull);
      expect(prefs.getString('card_pin'), isNull);
    });

    test('11. Card below Ksh.100 is blocked by PaystackService', () async {
      final service = PaystackService();
      const dailyPass = SubscriptionPackage(
        id: 'daily',
        title: 'Daily Pass',
        price: 5.0,
        duration: Duration(days: 1),
      );

      final result = await service.processPayment(
        package: dailyPass,
        method: PaystackPaymentMethod.mastercard,
        phoneNumber: '0712345678',
        email: 'test@example.com',
      );

      expect(result.success, false);
      expect(result.message, 'Card payment does not support payments below Ksh.100.');
    });
  });

  group('PaystackService Unresolved Payments & Offline Persistence Tests', () {
    test('12. Unresolved payment persistence and cleanup', () async {
      final service = PaystackService();
      expect(service.getUnresolvedPayments().isEmpty, true);

      await service.saveUnresolvedPayment(
        reference: 'ML_DAILY_TEST_123',
        packageId: 'daily',
        method: PaystackPaymentMethod.mpesa,
        phoneNumber: '0712345678',
      );

      final unresolved = service.getUnresolvedPayments();
      expect(unresolved.length, 1);
      expect(unresolved.first['reference'], 'ML_DAILY_TEST_123');
      expect(unresolved.first['packageId'], 'daily');
      expect(unresolved.first['method'], 'mpesa');

      // Remove after resolution
      await service.removeUnresolvedPayment('ML_DAILY_TEST_123');
      expect(service.getUnresolvedPayments().isEmpty, true);
    });

    test('13. Duplicate unresolved payment reference does not duplicate entry', () async {
      final service = PaystackService();
      await service.saveUnresolvedPayment(
        reference: 'ML_DAILY_DUP_REF',
        packageId: 'daily',
        method: PaystackPaymentMethod.mpesa,
        phoneNumber: '0712345678',
      );
      await service.saveUnresolvedPayment(
        reference: 'ML_DAILY_DUP_REF',
        packageId: 'daily',
        method: PaystackPaymentMethod.mpesa,
        phoneNumber: '0712345678',
      );

      final unresolved = service.getUnresolvedPayments();
      expect(unresolved.length, 1);
      expect(unresolved.first['reference'], 'ML_DAILY_DUP_REF');
    });
  });

  group('SubscriptionHistory Paystack Metadata & Compatibility Tests', () {
    test('14. SubscriptionHistory correctly carries Paystack reference and numeric transaction ID', () {
      final now = DateTime.now();
      final history = SubscriptionHistory(
        id: 'sub_123',
        packageTitle: 'Monthly Pass',
        amount: 100.0,
        transactionCode: 'ML_MONTHLY_12345_abc', // Paystack transaction reference
        paystackTransactionId: 987654321,
        paystackReference: 'ML_MONTHLY_12345_abc',
        paymentChannel: 'mobile_money',
        operatorReceiptNumber: 'QWE123RTY',
        purchaseDate: now,
        activationDate: now,
        expiryDate: now.add(const Duration(days: 30)),
        status: SubscriptionStatus.active,
      );

      expect(history.transactionCode, 'ML_MONTHLY_12345_abc');
      expect(history.paystackTransactionId, 987654321);
      expect(history.paystackReference, 'ML_MONTHLY_12345_abc');
      expect(history.paymentChannel, 'mobile_money');
      expect(history.operatorReceiptNumber, 'QWE123RTY');

      // Test JSON round-trip
      final json = history.toJson();
      expect(json['transactionCode'], 'ML_MONTHLY_12345_abc');
      expect(json['paystackTransactionId'], 987654321);

      final restored = SubscriptionHistory.fromJson(json);
      expect(restored.transactionCode, 'ML_MONTHLY_12345_abc');
      expect(restored.paystackTransactionId, 987654321);
    });

    test('15. Legacy SubscriptionHistory without optional Paystack fields parses safely', () {
      final legacyJson = {
        'id': 'legacy_1',
        'packageTitle': 'Daily Pass',
        'amount': 5.0,
        'transactionCode': 'TXN12345678',
        'purchaseDate': DateTime.now().toIso8601String(),
        'activationDate': DateTime.now().toIso8601String(),
        'expiryDate': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
        'status': 'active',
        'downloadCount': 0,
      };

      final sub = SubscriptionHistory.fromJson(legacyJson);
      expect(sub.transactionCode, 'TXN12345678');
      expect(sub.paystackTransactionId, isNull);
      expect(sub.paystackReference, isNull);
    });
  });
}
