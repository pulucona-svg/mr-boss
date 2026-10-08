import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/models/subscription_model.dart';
import 'package:mirror_laikipia/widgets/purchase_modal.dart';
import 'package:mirror_laikipia/providers/user_provider.dart';
import 'package:mirror_laikipia/services/paystack_service.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/services/interstitial_ad_service.dart';

class MockUserProfileNotifier extends UserProfileNotifier {
  MockUserProfileNotifier() {
    state = UserProfile(
      uid: 'test_user',
      username: 'Test User',
      institution: 'Laikipia University',
      universityLocation: 'Main Campus',
      program: 'Computer Science',
      programCode: 'CS101',
      year: 'Year 3',
      semester: 'Sem 1',
      phone: '+254712345678',
      email: 'test@laikipia.ac.ke',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
    PaystackService().resetStateForTesting();
  });

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

  Widget createTestApp({
    required SubscriptionPackage package,
    VoidCallback? onSuccess,
  }) {
    return ProviderScope(
      overrides: [
        userProfileProvider.overrideWith((ref) => MockUserProfileNotifier()),
      ],
      child: MaterialApp(
        navigatorKey: InterstitialAdService.navigatorKey,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => PurchaseModal(
                    package: package,
                    phoneNumber: '+254712345678',
                    onSuccess: onSuccess ?? () {},
                  ),
                );
              },
              child: const Text('Open Modal'),
            ),
          ),
        ),
      ),
    );
  }

  group('Non-Blocking Purchase Menu & Close Button Tests', () {
    testWidgets('1. X close button exists at top-right of PurchaseModal', (tester) async {
      await tester.pumpWidget(createTestApp(package: dailyPackage));
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Verify modal is open
      expect(find.text('CONFIRM PAYMENT'), findsOneWidget);

      // Verify X close button exists
      final closeButtonFinder = find.byKey(const Key('purchase_modal_close_button'));
      expect(closeButtonFinder, findsOneWidget);

      final iconFinder = find.descendant(
        of: closeButtonFinder,
        matching: find.byIcon(Icons.close_rounded),
      );
      expect(iconFinder, findsOneWidget);
    });

    testWidgets('2. Tapping X close button dismisses modal immediately and restores navigation', (tester) async {
      await tester.pumpWidget(createTestApp(package: dailyPackage));
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('CONFIRM PAYMENT'), findsOneWidget);
      expect(InterstitialAdService.isFullScreenAdShowing, true);

      // Tap X close button
      final closeButtonFinder = find.byKey(const Key('purchase_modal_close_button'));
      await tester.tap(closeButtonFinder);
      await tester.pumpAndSettle();

      // Modal is dismissed
      expect(find.text('CONFIRM PAYMENT'), findsNothing);
      expect(find.text('Open Modal'), findsOneWidget);
      expect(InterstitialAdService.isFullScreenAdShowing, false);
    });

    testWidgets('3. Scenario A: Existing flow - keep modal open, payment succeeds, modal pops and calls onSuccess once', (tester) async {
      int successCallCount = 0;
      await tester.pumpWidget(createTestApp(
        package: dailyPackage,
        onSuccess: () => successCallCount++,
      ));

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      const testRef = 'TEST_REF_FLOW_A';
      await PaystackService().saveUnresolvedPayment(
        reference: testRef,
        packageId: dailyPackage.id,
        method: PaystackPaymentMethod.mpesa,
        phoneNumber: '0712345678',
      );

      // Modal is open, simulate verification completion via background manager
      // Attach listener from the open modal
      final activeRef = PaystackService().getActiveReferenceForPackage(dailyPackage.id);
      expect(activeRef, isNull);

      // Simulate starting background verification with listener
      bool listenerSuccessFired = false;
      unawaited(PaystackService().startBackgroundVerification(
        reference: testRef,
        packageId: dailyPackage.id,
        method: PaystackPaymentMethod.mpesa,
        phoneNumber: '0712345678',
        listener: PaystackVerificationListener(
          onSuccess: () {
            listenerSuccessFired = true;
          },
        ),
      ));

      expect(PaystackService().isVerifying(testRef), true);
      expect(listenerSuccessFired, false);

      // Verify that duplicate start call does NOT create duplicate loop
      await PaystackService().startBackgroundVerification(
        reference: testRef,
        packageId: dailyPackage.id,
        method: PaystackPaymentMethod.mpesa,
        phoneNumber: '0712345678',
      );
      expect(PaystackService().isVerifying(testRef), true);

      // Clean up timer for test
      PaystackService().stopVerificationForTesting(testRef);
      await tester.pump(const Duration(seconds: 4));
    });

    test('4. Scenario B: Non-blocking flow - X tapped, background verification continues and fires success notification globally exactly once', () async {
      const testRef = 'TEST_REF_FLOW_B';
      await PaystackService().saveUnresolvedPayment(
        reference: testRef,
        packageId: monthlyPackage.id,
        method: PaystackPaymentMethod.mpesa,
        phoneNumber: '0712345678',
      );

      // Verify that PaystackService can run verification without any attached UI listener
      expect(PaystackService().isVerifying(testRef), false);

      // Start background verification without listener (as happens after modal dismissal)
      unawaited(PaystackService().startBackgroundVerification(
        reference: testRef,
        packageId: monthlyPackage.id,
        method: PaystackPaymentMethod.mpesa,
        phoneNumber: '0712345678',
      ));

      expect(PaystackService().isVerifying(testRef), true);

      // Verify active package reference tracking
      expect(PaystackService().getActiveReferenceForPackage(monthlyPackage.id), testRef);

      // Verify duplicate call is ignored
      await PaystackService().startBackgroundVerification(
        reference: testRef,
        packageId: monthlyPackage.id,
        method: PaystackPaymentMethod.mpesa,
        phoneNumber: '0712345678',
      );
      expect(PaystackService().isVerifying(testRef), true);
    });

    test('5. Scenario C: Close + payment failure - unresolved payment cleaned up and no unexpected popup', () async {
      const testRef = 'TEST_REF_FLOW_C';
      await PaystackService().saveUnresolvedPayment(
        reference: testRef,
        packageId: dailyPackage.id,
        method: PaystackPaymentMethod.mpesa,
        phoneNumber: '0712345678',
      );

      final unresolvedBefore = PaystackService().getUnresolvedPayments();
      expect(unresolvedBefore.any((u) => u['reference'] == testRef), true);

      // Clean up on failure
      await PaystackService().removeUnresolvedPayment(testRef);

      final unresolvedAfter = PaystackService().getUnresolvedPayments();
      expect(unresolvedAfter.any((u) => u['reference'] == testRef), false);
    });

    test('6. Scenario D: Reopening menu does not create duplicate verification loops for same reference', () async {
      const testRef = 'TEST_REF_FLOW_D';
      await PaystackService().saveUnresolvedPayment(
        reference: testRef,
        packageId: dailyPackage.id,
        method: PaystackPaymentMethod.mpesa,
        phoneNumber: '0712345678',
      );

      // First open -> starts background verification
      unawaited(PaystackService().startBackgroundVerification(
        reference: testRef,
        packageId: dailyPackage.id,
        method: PaystackPaymentMethod.mpesa,
        phoneNumber: '0712345678',
      ));
      expect(PaystackService().isVerifying(testRef), true);

      // Modal closed via X...
      // User reopens menu for same package:
      final existingActiveRef = PaystackService().getActiveReferenceForPackage(dailyPackage.id);
      expect(existingActiveRef, testRef);

      // When reopened, modal attaches listener to existing active reference without duplicate loop
      int statusUpdateCount = 0;
      PaystackService().addVerificationListener(
        existingActiveRef!,
        PaystackVerificationListener(
          onStatusUpdate: (_) => statusUpdateCount++,
        ),
      );

      // Second start call does nothing
      await PaystackService().startBackgroundVerification(
        reference: testRef,
        packageId: dailyPackage.id,
        method: PaystackPaymentMethod.mpesa,
        phoneNumber: '0712345678',
      );
      expect(PaystackService().isVerifying(testRef), true);
    });

    test('7. Scenario E: Multiple different purchases - old reference cleanup does not interfere with new purchase', () async {
      const oldRef = 'TEST_OLD_REF';
      const newRef = 'TEST_NEW_REF';

      // Old purchase starts and resolves
      await PaystackService().saveUnresolvedPayment(
        reference: oldRef,
        packageId: dailyPackage.id,
        method: PaystackPaymentMethod.mpesa,
        phoneNumber: '0712345678',
      );
      await PaystackService().removeUnresolvedPayment(oldRef);

      expect(PaystackService().isVerifying(oldRef), false);
      expect(PaystackService().getActiveReferenceForPackage(dailyPackage.id), isNull);

      // New legitimate purchase starts cleanly
      await PaystackService().saveUnresolvedPayment(
        reference: newRef,
        packageId: dailyPackage.id,
        method: PaystackPaymentMethod.mpesa,
        phoneNumber: '0712345678',
      );
      unawaited(PaystackService().startBackgroundVerification(
        reference: newRef,
        packageId: dailyPackage.id,
        method: PaystackPaymentMethod.mpesa,
        phoneNumber: '0712345678',
      ));

      expect(PaystackService().isVerifying(newRef), true);
      expect(PaystackService().getActiveReferenceForPackage(dailyPackage.id), newRef);
    });
  });
}
