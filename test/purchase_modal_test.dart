import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/models/subscription_model.dart';
import 'package:mirror_laikipia/widgets/purchase_modal.dart';
import 'package:mirror_laikipia/providers/user_provider.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';

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

  Widget createTestWidget(SubscriptionPackage package, {String phone = '+254712345678'}) {
    return ProviderScope(
      overrides: [
        userProfileProvider.overrideWith((ref) => MockUserProfileNotifier()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PurchaseModal(
            package: package,
            phoneNumber: phone,
            onSuccess: () {},
          ),
        ),
      ),
    );
  }

  group('PurchaseModal Kenyan Phone, Payment Method & Responsive Tests', () {
    testWidgets('1. Phone field prefills in local 07 format from profile +254, editable, and M-PESA is default', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(dailyPackage, phone: '+254712345678'));
      await tester.pumpAndSettle();

      // Check title and details
      expect(find.text('CONFIRM PAYMENT'), findsOneWidget);
      expect(find.text('Daily Pass'), findsOneWidget);
      expect(find.text('Ksh.5'), findsOneWidget);

      // Check phone prefill is normalized to Kenyan local 10-digit format (0712345678)
      final phoneField = find.byType(TextField);
      expect(phoneField, findsOneWidget);
      final TextField fieldWidget = tester.widget<TextField>(phoneField);
      expect(fieldWidget.controller?.text, '0712345678');

      // Edit phone number to valid 07XXXXXXXX
      await tester.enterText(phoneField, '0799887766');
      await tester.pump();
      expect(fieldWidget.controller?.text, '0799887766');

      // Edit phone number to valid 01XXXXXXXX
      await tester.enterText(phoneField, '0112345678');
      await tester.pump();
      expect(fieldWidget.controller?.text, '0112345678');

      // Instruction text
      expect(find.text('Please select your preferred method of payment'), findsOneWidget);

      // 3 horizontal buttons exist
      expect(find.text('M-PESA'), findsWidgets);
      expect(find.text('Airtel Money'), findsOneWidget);
      expect(find.text('Mastercard'), findsWidgets);

      // M-PESA is default selected
      expect(find.text('You will receive an M-Pesa prompt requesting payment of Ksh.5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('2. 9 digits makes phone number invalid and disables Purchase button', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(dailyPackage, phone: '+254712345678'));
      await tester.pumpAndSettle();

      final phoneField = find.byType(TextField);
      // Enter 9 digits
      await tester.enterText(phoneField, '071234567');
      await tester.pump();

      // Check text color is red
      final TextField fieldWidget = tester.widget<TextField>(phoneField);
      expect(fieldWidget.style?.color, Colors.redAccent);

      // Check ElevatedButton is disabled
      final purchaseButtonFinder = find.byType(ElevatedButton);
      final ElevatedButton button = tester.widget<ElevatedButton>(purchaseButtonFinder);
      expect(button.onPressed, isNull);
    });

    testWidgets('3. 11 digits cannot be entered (maxLength: 10 strictly enforced)', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(dailyPackage, phone: '+254712345678'));
      await tester.pumpAndSettle();

      final phoneField = find.byType(TextField);
      // Attempt to enter 11 digits
      await tester.enterText(phoneField, '07123456789');
      await tester.pump();

      final TextField fieldWidget = tester.widget<TextField>(phoneField);
      // Field enforces maxLength: 10
      expect(fieldWidget.controller?.text.length, 10);
      expect(fieldWidget.controller?.text, '0712345678');
    });

    testWidgets('4. Empty phone field shows 07XXXXXXXX hint placeholder and disables button', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(dailyPackage, phone: ''));
      await tester.pumpAndSettle();

      final phoneField = find.byType(TextField);
      final TextField fieldWidget = tester.widget<TextField>(phoneField);
      expect(fieldWidget.controller?.text, '');
      expect(fieldWidget.decoration?.hintText, '07XXXXXXXX');

      // Purchase button is disabled
      final purchaseButtonFinder = find.byType(ElevatedButton);
      final ElevatedButton button = tester.widget<ElevatedButton>(purchaseButtonFinder);
      expect(button.onPressed, isNull);
    });

    testWidgets('5. Airtel Money selection shows Airtel Money prompt', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(dailyPackage));
      await tester.pumpAndSettle();

      // Tap Airtel Money
      await tester.tap(find.text('Airtel Money'));
      await tester.pumpAndSettle();

      // M-PESA prompt disappears, Airtel Money prompt appears
      expect(find.text('You will receive an M-Pesa prompt requesting payment of Ksh.5'), findsNothing);
      expect(find.text('You will receive an Airtel Money prompt requesting payment of Ksh.5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('6. Mastercard below KES 100 shows restriction notice and blocks', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(dailyPackage));
      await tester.pumpAndSettle();

      // Tap Mastercard
      await tester.tap(find.text('Mastercard'));
      await tester.pumpAndSettle();

      // Card payment restriction notice appears
      expect(find.text('Card payment does not support payments below Ksh.100.'), findsWidgets);

      // Purchase button is disabled
      final purchaseButtonFinder = find.byType(ElevatedButton);
      final ElevatedButton button = tester.widget<ElevatedButton>(purchaseButtonFinder);
      expect(button.onPressed, isNull);
    });

    testWidgets('7. Mastercard at or above KES 100 shows clean card form', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(monthlyPackage));
      await tester.pumpAndSettle();

      // Tap Mastercard
      await tester.tap(find.text('Mastercard'));
      await tester.pumpAndSettle();

      // Card form fields are visible
      expect(find.text('CARD DETAILS'), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(find.byIcon(Icons.credit_card), findsOneWidget);
      expect(find.byIcon(Icons.date_range), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('8. Responsive layout on 360px device has ZERO overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget(monthlyPackage));
      await tester.pumpAndSettle();

      // Switch between tabs repeatedly
      await tester.tap(find.text('Airtel Money'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mastercard'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('M-PESA'));
      await tester.pumpAndSettle();

      // No overflows occurred
      expect(tester.takeException(), isNull);
    });
  });
}
