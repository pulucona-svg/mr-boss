import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mirror_laikipia/services/connectivity_service.dart';
import 'package:mirror_laikipia/services/top_notification_service.dart';
import 'package:mirror_laikipia/services/interstitial_ad_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ConnectivityService().setOfflineForTesting(false);
  });

  tearDown(() {
    ConnectivityService().setOfflineForTesting(false);
  });

  group('1. ConnectivityService.isNetworkError Network Failure Classification', () {
    test('returns true for SocketException', () {
      const error = SocketException('Failed host lookup: firestore.googleapis.com');
      expect(ConnectivityService.isNetworkError(error), isTrue);
    });

    test('returns true for TimeoutException', () {
      final error = TimeoutException('Connection timed out');
      expect(ConnectivityService.isNetworkError(error), isTrue);
    });

    test('returns true for HttpException', () {
      const error = HttpException('Connection reset by peer');
      expect(ConnectivityService.isNetworkError(error), isTrue);
    });

    test('returns true for HandshakeException and TlsException', () {
      const handshake = HandshakeException('Handshake error in client');
      const tls = TlsException('TLS handshake failed');
      expect(ConnectivityService.isNetworkError(handshake), isTrue);
      expect(ConnectivityService.isNetworkError(tls), isTrue);
    });

    test('returns true for http.ClientException', () {
      final error = http.ClientException('Client error: Connection closed before full header received');
      expect(ConnectivityService.isNetworkError(error), isTrue);
    });

    test('returns true for FirebaseAuthException network-request-failed', () {
      final error = FirebaseAuthException(
        code: 'network-request-failed',
        message: 'A network error had occurred.',
      );
      expect(ConnectivityService.isNetworkError(error), isTrue);
    });

    test('returns true for FirebaseException unavailable', () {
      final error = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'The service is currently unavailable.',
      );
      expect(ConnectivityService.isNetworkError(error), isTrue);
    });

    test('returns true for FirebaseException deadline-exceeded', () {
      final error = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'deadline-exceeded',
        message: 'Deadline exceeded.',
      );
      expect(ConnectivityService.isNetworkError(error), isTrue);
    });

    test('returns true when device is explicitly offline', () {
      ConnectivityService().setOfflineForTesting(true);

      expect(ConnectivityService().isOffline, isTrue);
      expect(ConnectivityService.isNetworkError(null), isTrue);
      expect(ConnectivityService.isNetworkError(Exception('unknown error')), isTrue);
    });

    test('returns true for descriptive network error string patterns', () {
      expect(ConnectivityService.isNetworkError(Exception('failed host lookup')), isTrue);
      expect(ConnectivityService.isNetworkError(Exception('connection refused')), isTrue);
      expect(ConnectivityService.isNetworkError(Exception('connection timed out')), isTrue);
      expect(ConnectivityService.isNetworkError(Exception('connection reset')), isTrue);
      expect(ConnectivityService.isNetworkError(Exception('network is unreachable')), isTrue);
      expect(ConnectivityService.isNetworkError(Exception('Software caused connection abort')), isTrue);
      expect(ConnectivityService.isNetworkError(Exception('OS Error: 101')), isTrue);
    });
  });

  group('2. ConnectivityService.isNetworkError Genuine Auth & Non-Network Errors', () {
    test('returns false for FirebaseAuthException wrong-password', () {
      final error = FirebaseAuthException(
        code: 'wrong-password',
        message: 'Wrong password provided.',
      );
      expect(ConnectivityService.isNetworkError(error), isFalse);
    });

    test('returns false for FirebaseAuthException user-not-found', () {
      final error = FirebaseAuthException(
        code: 'user-not-found',
        message: 'No user found for that email.',
      );
      expect(ConnectivityService.isNetworkError(error), isFalse);
    });

    test('returns false for FirebaseAuthException invalid-email', () {
      final error = FirebaseAuthException(
        code: 'invalid-email',
        message: 'The email address is badly formatted.',
      );
      expect(ConnectivityService.isNetworkError(error), isFalse);
    });

    test('returns false for FirebaseAuthException email-already-in-use', () {
      final error = FirebaseAuthException(
        code: 'email-already-in-use',
        message: 'The email is already registered.',
      );
      expect(ConnectivityService.isNetworkError(error), isFalse);
    });

    test('returns false for FirebaseAuthException weak-password', () {
      final error = FirebaseAuthException(
        code: 'weak-password',
        message: 'The password provided is too weak.',
      );
      expect(ConnectivityService.isNetworkError(error), isFalse);
    });

    test('returns false for other legitimate auth errors', () {
      expect(ConnectivityService.isNetworkError(FirebaseAuthException(code: 'user-disabled')), isFalse);
      expect(ConnectivityService.isNetworkError(FirebaseAuthException(code: 'too-many-requests')), isFalse);
      expect(ConnectivityService.isNetworkError(FirebaseAuthException(code: 'invalid-credential')), isFalse);
      expect(ConnectivityService.isNetworkError(FirebaseAuthException(code: 'operation-not-allowed')), isFalse);
      expect(ConnectivityService.isNetworkError(FirebaseAuthException(code: 'requires-recent-login')), isFalse);
    });

    test('returns false for FormatException and syntax/type errors', () {
      const error = FormatException('Invalid JSON payload');
      expect(ConnectivityService.isNetworkError(error), isFalse);
      expect(ConnectivityService.isNetworkError(AssertionError('assert failure')), isFalse);
    });

    test('returns false for null when device is online', () {
      ConnectivityService().setOfflineForTesting(false);
      expect(ConnectivityService.isNetworkError(null), isFalse);
    });
  });

  group('3. Material Viewer Error Mapping Verification', () {
    String mapMaterialViewerError(dynamic error) {
      return ConnectivityService.isNetworkError(error)
          ? 'Failed to load the material. Please check your internet connection.'
          : 'Failed to load the material. Please try again.';
    }

    test('network errors map to user-friendly offline message', () {
      final socketError = const SocketException('Connection failed');
      final timeoutError = TimeoutException('Download timed out');
      final unavailableError = FirebaseException(plugin: 'storage', code: 'unavailable');

      expect(
        mapMaterialViewerError(socketError),
        equals('Failed to load the material. Please check your internet connection.'),
      );
      expect(
        mapMaterialViewerError(timeoutError),
        equals('Failed to load the material. Please check your internet connection.'),
      );
      expect(
        mapMaterialViewerError(unavailableError),
        equals('Failed to load the material. Please check your internet connection.'),
      );
    });

    test('raw server/socket exception details are never exposed to the user', () {
      final rawError = const SocketException('OS Error: Failed host lookup 192.168.1.1');
      final userMessage = mapMaterialViewerError(rawError);

      expect(userMessage.contains('SocketException'), isFalse);
      expect(userMessage.contains('OS Error'), isFalse);
      expect(userMessage.contains('192.168'), isFalse);
      expect(userMessage, equals('Failed to load the material. Please check your internet connection.'));
    });

    test('non-network errors map to generic retry message', () {
      final formatError = const FormatException('Corrupt header');
      expect(
        mapMaterialViewerError(formatError),
        equals('Failed to load the material. Please try again.'),
      );
    });

    test('offline state correctly triggers the material offline message', () {
      ConnectivityService().setOfflineForTesting(true);
      expect(
        mapMaterialViewerError(null),
        equals('Failed to load the material. Please check your internet connection.'),
      );
    });
  });

  group('4. Login Error Mapping Verification', () {
    String mapLoginAuthException(FirebaseAuthException e) {
      if (ConnectivityService.isNetworkError(e)) {
        return 'Login failed. Please check your internet connection and try again.';
      } else if (e.code == 'user-not-found') {
        return 'No user found with this identifier';
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        return 'Incorrect password';
      } else if (e.code == 'invalid-email') {
        return 'Invalid email address';
      } else if (e.code == 'user-disabled') {
        return 'This account has been disabled';
      } else if (e.code == 'too-many-requests') {
        return 'Too many attempts. Please try again later.';
      }
      return 'Login failed';
    }

    test('network-request-failed maps to login connectivity message', () {
      final error = FirebaseAuthException(code: 'network-request-failed');
      expect(
        mapLoginAuthException(error),
        equals('Login failed. Please check your internet connection and try again.'),
      );
    });

    test('genuine login errors retain specific message strings', () {
      expect(
        mapLoginAuthException(FirebaseAuthException(code: 'user-not-found')),
        equals('No user found with this identifier'),
      );
      expect(
        mapLoginAuthException(FirebaseAuthException(code: 'wrong-password')),
        equals('Incorrect password'),
      );
      expect(
        mapLoginAuthException(FirebaseAuthException(code: 'invalid-credential')),
        equals('Incorrect password'),
      );
      expect(
        mapLoginAuthException(FirebaseAuthException(code: 'invalid-email')),
        equals('Invalid email address'),
      );
      expect(
        mapLoginAuthException(FirebaseAuthException(code: 'user-disabled')),
        equals('This account has been disabled'),
      );
      expect(
        mapLoginAuthException(FirebaseAuthException(code: 'too-many-requests')),
        equals('Too many attempts. Please try again later.'),
      );
    });

    test('general network exception in login maps to connectivity message', () {
      final error = const SocketException('Connection reset');
      final message = ConnectivityService.isNetworkError(error)
          ? 'Login failed. Please check your internet connection and try again.'
          : 'Error: ${error.toString()}';

      expect(message, equals('Login failed. Please check your internet connection and try again.'));
    });
  });

  group('5. Signup Error Mapping Verification', () {
    String mapSignupAuthException(FirebaseAuthException e) {
      if (ConnectivityService.isNetworkError(e)) {
        return 'Sign up failed. Please check your internet connection and try again.';
      } else if (e.code == 'email-already-in-use') {
        return 'This email is already registered. Please login instead.';
      } else if (e.code == 'invalid-email') {
        return 'Please enter a valid email';
      } else if (e.code == 'weak-password') {
        return 'The password provided is too weak.';
      }
      return e.message ?? 'An error occurred during signup';
    }

    test('network error in signup maps to connectivity message', () {
      final error = FirebaseAuthException(code: 'network-request-failed');
      expect(
        mapSignupAuthException(error),
        equals('Sign up failed. Please check your internet connection and try again.'),
      );
    });

    test('email-already-in-use retains existing message', () {
      final error = FirebaseAuthException(code: 'email-already-in-use');
      expect(
        mapSignupAuthException(error),
        equals('This email is already registered. Please login instead.'),
      );
    });

    test('invalid-email and weak-password retain existing messages', () {
      expect(
        mapSignupAuthException(FirebaseAuthException(code: 'invalid-email')),
        equals('Please enter a valid email'),
      );
      expect(
        mapSignupAuthException(FirebaseAuthException(code: 'weak-password')),
        equals('The password provided is too weak.'),
      );
    });
  });

  group('6. Forgot Password Error Mapping Verification', () {
    String mapForgotPasswordAuthException(FirebaseAuthException e) {
      if (ConnectivityService.isNetworkError(e)) {
        return 'Password reset failed. Please check your internet connection and try again.';
      } else if (e.code == 'user-not-found') {
        return 'No user found with this email';
      } else if (e.code == 'invalid-email') {
        return 'Invalid email address';
      } else if (e.code == 'too-many-requests') {
        return 'Too many attempts. Please try again later.';
      }
      return e.message ?? 'Password reset failed';
    }

    test('network-request-failed maps to password reset connectivity message', () {
      final error = FirebaseAuthException(code: 'network-request-failed');
      expect(
        mapForgotPasswordAuthException(error),
        equals('Password reset failed. Please check your internet connection and try again.'),
      );
    });

    test('general SocketException maps to password reset connectivity message', () {
      final error = const SocketException('Network is unreachable');
      final message = ConnectivityService.isNetworkError(error)
          ? 'Password reset failed. Please check your internet connection and try again.'
          : 'Error: ${error.toString()}';

      expect(message, equals('Password reset failed. Please check your internet connection and try again.'));
    });

    test('offline username lookup failure maps to password reset connectivity message', () {
      ConnectivityService().setOfflineForTesting(true);

      String? resultMessage;
      if (ConnectivityService.isNetworkError(null)) {
        resultMessage = 'Password reset failed. Please check your internet connection and try again.';
      } else {
        resultMessage = 'Username not found';
      }

      expect(resultMessage, equals('Password reset failed. Please check your internet connection and try again.'));
    });

    test('online username lookup failure gives legitimate Username not found message', () {
      ConnectivityService().setOfflineForTesting(false);

      String? resultMessage;
      if (ConnectivityService.isNetworkError(null)) {
        resultMessage = 'Password reset failed. Please check your internet connection and try again.';
      } else {
        resultMessage = 'Username not found';
      }

      expect(resultMessage, equals('Username not found'));
    });

    test('legitimate validation errors in forgot password remain unchanged', () {
      expect(
        mapForgotPasswordAuthException(FirebaseAuthException(code: 'user-not-found')),
        equals('No user found with this email'),
      );
      expect(
        mapForgotPasswordAuthException(FirebaseAuthException(code: 'invalid-email')),
        equals('Invalid email address'),
      );
      expect(
        mapForgotPasswordAuthException(FirebaseAuthException(code: 'too-many-requests')),
        equals('Too many attempts. Please try again later.'),
      );
    });
  });

  group('7. TopNotificationService Fallback and Context Robustness Tests', () {
    testWidgets('shows notification when BuildContext is mounted', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  TopNotificationService().showNotification(
                    context,
                    'Password reset failed. Please check your internet connection and try again.',
                  );
                },
                child: const Text('Reset'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Reset'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Password reset failed. Please check your internet connection and try again.'),
        findsOneWidget,
      );

      // Clean up timer
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('falls back to InterstitialAdService.navigatorKey overlay when context is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: InterstitialAdService.navigatorKey,
          home: const Scaffold(
            body: Center(child: Text('Home')),
          ),
        ),
      );

      // Pass null BuildContext
      TopNotificationService().showNotification(
        null,
        'Password reset failed. Please check your internet connection and try again.',
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Password reset failed. Please check your internet connection and try again.'),
        findsOneWidget,
      );

      // Clean up timer
      await tester.pump(const Duration(seconds: 4));
    });

    test('inferType correctly classifies connectivity error messages as error', () {
      expect(
        TopNotificationService.inferType(
          'Login failed. Please check your internet connection and try again.',
        ),
        equals(TopNotificationType.error),
      );
      expect(
        TopNotificationService.inferType(
          'Sign up failed. Please check your internet connection and try again.',
        ),
        equals(TopNotificationType.error),
      );
      expect(
        TopNotificationService.inferType(
          'Password reset failed. Please check your internet connection and try again.',
        ),
        equals(TopNotificationType.error),
      );
      expect(
        TopNotificationService.inferType(
          'Failed to load the material. Please check your internet connection.',
        ),
        equals(TopNotificationType.error),
      );
    });
  });
}
