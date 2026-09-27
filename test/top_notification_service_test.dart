import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/services/top_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TopNotificationService Type & Color Tests', () {
    test('1. Type inference correctly categorizes failure/error messages as error', () {
      expect(TopNotificationService.inferType('Payment failed. Please try again.'), TopNotificationType.error);
      expect(TopNotificationService.inferType('Payment was not completed or expired. Please try again.'), TopNotificationType.error);
      expect(TopNotificationService.inferType('Payment was reversed.'), TopNotificationType.error);
      expect(TopNotificationService.inferType('Payment error: network failure'), TopNotificationType.error);
      expect(TopNotificationService.inferType('You are currently offline. Please check your internet connection.'), TopNotificationType.error);
      expect(TopNotificationService.inferType('Please enter a valid 10-digit phone number'), TopNotificationType.error);
      expect(TopNotificationService.inferType('Please enter a valid 16-digit card number.'), TopNotificationType.error);
      expect(TopNotificationService.inferType('Card payment does not support payments below Ksh.100.'), TopNotificationType.error);
      expect(TopNotificationService.inferType('Payment confirmation timed out.'), TopNotificationType.error);
    });

    test('2. Type inference correctly categorizes success messages as success', () {
      expect(TopNotificationService.inferType('Subscription successful. Enjoy ad-free access!'), TopNotificationType.success);
      expect(TopNotificationService.inferType('Welcome back to Mirror Laikipia'), TopNotificationType.success);
      expect(TopNotificationService.inferType('Password set successfully'), TopNotificationType.success);
      expect(TopNotificationService.inferType('Payment confirmed! Activating subscription...'), TopNotificationType.success);
      expect(TopNotificationService.inferType('Verification email sent.'), TopNotificationType.success);
    });

    test('3. Type inference detects warning and info messages', () {
      expect(TopNotificationService.inferType('Warning: Battery low'), TopNotificationType.warning);
      expect(TopNotificationService.inferType('Caution: Action required'), TopNotificationType.warning);
      expect(TopNotificationService.inferType('Apple Sign-In coming soon'), TopNotificationType.info);
    });

    testWidgets('4. Error notification renders in red with error icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  TopNotificationService().showNotification(
                    context,
                    'Payment failed. Please try again.',
                    type: TopNotificationType.error,
                  );
                },
                child: const Text('Show Error'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Error'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Payment failed. Please try again.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

      final containerFinder = find.byWidgetPredicate((widget) {
        if (widget is Container && widget.decoration is BoxDecoration) {
          final box = widget.decoration as BoxDecoration;
          return box.color == Colors.red.shade600;
        }
        return false;
      });
      expect(containerFinder, findsOneWidget);

      // Clean up timer
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('5. Success notification renders in green with check icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  TopNotificationService().showNotification(
                    context,
                    'Subscription successful. Enjoy ad-free access!',
                    type: TopNotificationType.success,
                  );
                },
                child: const Text('Show Success'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Success'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Subscription successful. Enjoy ad-free access!'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

      final containerFinder = find.byWidgetPredicate((widget) {
        if (widget is Container && widget.decoration is BoxDecoration) {
          final box = widget.decoration as BoxDecoration;
          return box.color == Colors.green.shade600;
        }
        return false;
      });
      expect(containerFinder, findsOneWidget);

      // Clean up timer
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
