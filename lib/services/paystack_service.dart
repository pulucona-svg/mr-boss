import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/subscription_model.dart';
import 'connectivity_service.dart';
import 'persistence_service.dart';
import 'top_notification_service.dart';

class PaystackVerificationListener {
  final void Function(String message)? onStatusUpdate;
  final void Function()? onSuccess;
  final void Function(String errorMessage)? onFailure;

  const PaystackVerificationListener({
    this.onStatusUpdate,
    this.onSuccess,
    this.onFailure,
  });
}

enum PaystackPaymentMethod {
  mpesa,
  airtelMoney,
  mastercard,
}

class PaystackPaymentResult {
  final bool success;
  final String? reference;
  final String? paystackStatus;
  final String? message;
  final String? displayText;
  final String? authorizationUrl;
  final String? accessCode;
  final PaystackPaymentMethod method;

  const PaystackPaymentResult({
    required this.success,
    this.reference,
    this.paystackStatus,
    this.message,
    this.displayText,
    this.authorizationUrl,
    this.accessCode,
    required this.method,
  });
}

class PaystackVerificationResult {
  final bool success;
  final String status; // 'success', 'pending', 'pay_offline', 'ongoing', 'failed', 'abandoned', 'reversed', 'offline'
  final String? paystackStatus;
  final String message;
  final String? displayText;
  final bool isPending;
  final bool alreadyFulfilled;

  const PaystackVerificationResult({
    required this.success,
    required this.status,
    this.paystackStatus,
    required this.message,
    this.displayText,
    this.isPending = false,
    this.alreadyFulfilled = false,
  });
}

class PaystackService {
  static final PaystackService _instance = PaystackService._internal();
  factory PaystackService() => _instance;
  PaystackService._internal();

  /// Live public key (Safe client-side key)
  static const String livePublicKey = 'pk_live_0cce763dfa92cfac595d0d78d954897a2fe9b036';
  static const String testPublicKey = livePublicKey;

  /// Minimum transaction threshold for card payments in Kenya on Paystack
  static const double minCardAmount = 100.0;

  /// Currency code for Kenya
  static const String currency = 'KES';

  FirebaseFunctions? _customFunctions;
  FirebaseFunctions get _functions => _customFunctions ?? FirebaseFunctions.instance;

  @visibleForTesting
  set customFunctions(FirebaseFunctions? functions) => _customFunctions = functions;

  bool _isInitialized = false;

  /// Set of currently running background verification references to prevent duplicate loops
  final Set<String> _activeVerifications = {};

  /// Set of completed references that have already fired success notification
  final Set<String> _notifiedSuccessReferences = {};

  /// Map of reference to active listeners for UI status updates
  final Map<String, List<PaystackVerificationListener>> _listeners = {};

  /// Map of reference to active package ID
  final Map<String, String> _activePackageIds = {};

  /// Last known status message for active references
  final Map<String, String> _lastStatusMessages = {};

  /// Check whether a reference has an active background verification loop
  bool isVerifying(String reference) => _activeVerifications.contains(reference);

  /// Get active reference for a package if any is running
  String? getActiveReferenceForPackage(String packageId) {
    for (final entry in _activePackageIds.entries) {
      if (entry.value == packageId && _activeVerifications.contains(entry.key)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Get last known status message for an active reference
  String? getLastStatusMessage(String reference) => _lastStatusMessages[reference];

  /// Attach a listener for UI updates on a pending reference
  void addVerificationListener(String reference, PaystackVerificationListener listener) {
    _listeners.putIfAbsent(reference, () => []).add(listener);
  }

  /// Remove a listener when UI is unmounted or dismissed
  void removeVerificationListener(String reference, PaystackVerificationListener listener) {
    _listeners[reference]?.remove(listener);
    if (_listeners[reference]?.isEmpty ?? false) {
      _listeners.remove(reference);
    }
  }

  @visibleForTesting
  void resetStateForTesting() {
    _activeVerifications.clear();
    _notifiedSuccessReferences.clear();
    _listeners.clear();
    _activePackageIds.clear();
    _lastStatusMessages.clear();
  }

  @visibleForTesting
  void stopVerificationForTesting(String reference) {
    _activeVerifications.remove(reference);
    _activePackageIds.remove(reference);
    _lastStatusMessages.remove(reference);
    _listeners.remove(reference);
  }

  /// Keys for SharedPreferences
  static const String keyUnresolvedPayments = 'unresolved_paystack_payments';
  static const String keyLastMpesaPhone = 'last_successful_mpesa_phone';
  static const String keyLastAirtelPhone = 'last_successful_airtel_phone';
  static const String keyLastCardDisplay = 'last_successful_card_display';

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Attach connectivity listener to automatically synchronize unresolved payments
    ConnectivityService().addListener(_onConnectivityChanged);

    // Initial check if already online
    if (!ConnectivityService().isOffline) {
      unawaited(syncUnresolvedPayments());
    }
  }

  void _onConnectivityChanged() {
    if (!ConnectivityService().isOffline) {
      debugPrint('PaystackService: Device back online. Checking unresolved payments...');
      unawaited(syncUnresolvedPayments());
    }
  }

  /// Formats any valid Kenyan phone number to 10-digit local format: 07XXXXXXXX or 01XXXXXXXX
  static String formatToLocalKenyaPhone(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'\s+|-'), '').trim();
    if (cleaned.startsWith('+254')) {
      cleaned = cleaned.substring(4);
      return '0$cleaned';
    } else if (cleaned.startsWith('254')) {
      cleaned = cleaned.substring(3);
      return '0$cleaned';
    } else if (cleaned.startsWith('0')) {
      return cleaned;
    } else if (cleaned.startsWith('7') || cleaned.startsWith('1')) {
      return '0$cleaned';
    }
    return cleaned;
  }

  /// Validates whether a phone number is a strictly valid 10-digit Kenyan local phone
  static bool isValidKenyaPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) return false;
    return digits.startsWith('07') || digits.startsWith('01');
  }

  /// Normalizes Kenyan local phone (07... / 01...) to E.164 (+254...)
  static String normalizeKenyanPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10 && digits.startsWith('0')) {
      return '+254${digits.substring(1)}';
    }
    if (digits.startsWith('254') && digits.length == 12) {
      return '+$digits';
    }
    if (phone.startsWith('+254')) return phone;
    return phone;
  }

  /// Remember last successful mobile-money number locally
  Future<void> saveLastSuccessfulPhone(PaystackPaymentMethod method, String phone) async {
    final localPhone = formatToLocalKenyaPhone(phone);
    if (!isValidKenyaPhone(localPhone)) return;

    if (method == PaystackPaymentMethod.mpesa) {
      await PersistenceService().setString(keyLastMpesaPhone, localPhone);
    } else if (method == PaystackPaymentMethod.airtelMoney) {
      await PersistenceService().setString(keyLastAirtelPhone, localPhone);
    }
  }

  String? getLastSuccessfulPhone(PaystackPaymentMethod method) {
    if (method == PaystackPaymentMethod.mpesa) {
      return PersistenceService().getString(keyLastMpesaPhone);
    } else if (method == PaystackPaymentMethod.airtelMoney) {
      return PersistenceService().getString(keyLastAirtelPhone);
    }
    return null;
  }

  /// Safe card display metadata storage ONLY (No full number, CVV, or PIN)
  Future<void> saveLastCardMetadata({required String brand, required String last4}) async {
    final display = '$brand •••• $last4';
    await PersistenceService().setString(keyLastCardDisplay, display);
  }

  String? getLastCardMetadata() {
    return PersistenceService().getString(keyLastCardDisplay);
  }

  /// Persist unresolved payment reference locally
  Future<void> saveUnresolvedPayment({
    required String reference,
    required String packageId,
    required PaystackPaymentMethod method,
    required String phoneNumber,
  }) async {
    try {
      final list = getUnresolvedPayments();
      // Avoid duplicates
      list.removeWhere((item) => item['reference'] == reference);
      list.add({
        'reference': reference,
        'packageId': packageId,
        'method': method.name,
        'phoneNumber': phoneNumber,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final encodedList = list.map((e) => jsonEncode(e)).toList();
      await PersistenceService().setStringList(keyUnresolvedPayments, encodedList);
      debugPrint('PaystackService: Persisted unresolved payment: $reference');
    } catch (e) {
      debugPrint('PaystackService: Error saving unresolved payment: $e');
    }
  }

  /// Remove resolved payment from local storage
  Future<void> removeUnresolvedPayment(String reference) async {
    try {
      final list = getUnresolvedPayments();
      list.removeWhere((item) => item['reference'] == reference);
      final encodedList = list.map((e) => jsonEncode(e)).toList();
      await PersistenceService().setStringList(keyUnresolvedPayments, encodedList);
      debugPrint('PaystackService: Removed resolved payment reference: $reference');
    } catch (e) {
      debugPrint('PaystackService: Error removing unresolved payment: $e');
    }
  }

  /// Get list of unresolved payments
  List<Map<String, dynamic>> getUnresolvedPayments() {
    try {
      final stringList = PersistenceService().getStringList(keyUnresolvedPayments) ?? [];
      return stringList
          .map((s) => Map<String, dynamic>.from(jsonDecode(s) as Map))
          .toList();
    } catch (e) {
      debugPrint('PaystackService: Error loading unresolved payments: $e');
      return [];
    }
  }

  /// Synchronize unresolved payments with backend
  Future<void> syncUnresolvedPayments() async {
    if (ConnectivityService().isOffline) return;

    final unresolved = getUnresolvedPayments();
    if (unresolved.isEmpty) return;

    debugPrint('PaystackService: Synchronizing ${unresolved.length} unresolved payments...');

    for (final item in unresolved) {
      final reference = item['reference'] as String?;
      if (reference == null || reference.isEmpty) continue;
      // Skip reference if a live background verification loop is already polling it
      if (_activeVerifications.contains(reference)) continue;

      try {
        final verifyResult = await verifyPayment(reference);
        if (verifyResult.success || verifyResult.alreadyFulfilled) {
          debugPrint('PaystackService: Unresolved payment $reference verified successfully!');
          await removeUnresolvedPayment(reference);
          final methodStr = item['method'] as String?;
          final phone = item['phoneNumber'] as String?;
          if (phone != null && phone.isNotEmpty) {
            final method = methodStr == 'airtelMoney'
                ? PaystackPaymentMethod.airtelMoney
                : PaystackPaymentMethod.mpesa;
            await saveLastSuccessfulPhone(method, phone);
          }
          _handleVerificationSuccess(reference);
        } else if (verifyResult.status == 'failed' ||
                   verifyResult.status == 'abandoned' ||
                   verifyResult.status == 'reversed') {
          debugPrint('PaystackService: Unresolved payment $reference concluded with status: ${verifyResult.status}');
          await removeUnresolvedPayment(reference);
        } else {
          // Still pending/pay_offline
          final timestamp = item['timestamp'] as int? ?? 0;
          final ageMs = DateTime.now().millisecondsSinceEpoch - timestamp;
          // If older than 24 hours, discard
          if (ageMs > 24 * 60 * 60 * 1000) {
            await removeUnresolvedPayment(reference);
          }
        }
      } catch (e) {
        debugPrint('PaystackService: Failed to sync payment $reference: $e');
      }
    }
  }

  /// Initiates payment securely through backend Firebase Callable
  Future<PaystackPaymentResult> processPayment({
    required SubscriptionPackage package,
    required PaystackPaymentMethod method,
    required String phoneNumber,
    required String email,
    String? cardHolderName,
    String? cardNumber,
    String? expiryDate,
    String? cvv,
  }) async {
    // 1. Guard check for Mastercard below KES 100
    if (method == PaystackPaymentMethod.mastercard && package.price < minCardAmount) {
      return PaystackPaymentResult(
        success: false,
        paystackStatus: 'failed',
        message: 'Card payment does not support payments below Ksh.100.',
        method: method,
      );
    }

    final normalizedPhone = normalizeKenyanPhone(phoneNumber);
    final paymentMethodName = method == PaystackPaymentMethod.mpesa
        ? 'mpesa'
        : (method == PaystackPaymentMethod.airtelMoney ? 'airtelMoney' : 'mastercard');

    try {
      final callable = _functions.httpsCallable('initializePaystackPayment');
      final result = await callable.call({
        'packageId': package.id,
        'paymentMethod': paymentMethodName,
        'phoneNumber': normalizedPhone,
        'userEmail': email,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      final isSuccess = data['success'] == true;

      return PaystackPaymentResult(
        success: isSuccess,
        reference: data['reference'],
        paystackStatus: data['paystackStatus'],
        displayText: data['displayText'],
        authorizationUrl: data['authorizationUrl'],
        accessCode: data['accessCode'],
        message: data['message'] ?? data['displayText'] ?? (isSuccess ? 'Payment initialized' : 'Payment failed'),
        method: method,
      );
    } catch (e) {
      debugPrint('PaystackService: Backend initialization failed: $e');
      return PaystackPaymentResult(
        success: false,
        paystackStatus: 'failed',
        message: e.toString().contains('Card payment does not support')
            ? 'Card payment does not support payments below Ksh.100.'
            : 'Payment initialization failed. Please try again.',
        method: method,
      );
    }
  }

  /// Verifies transaction completion with backend
  Future<PaystackVerificationResult> verifyPayment(String reference) async {
    try {
      final callable = _functions.httpsCallable('verifyPaystackPayment');
      final result = await callable.call({'reference': reference});
      final data = Map<String, dynamic>.from(result.data as Map);

      final isSuccess = data['success'] == true;
      final status = (data['status'] as String?) ?? (isSuccess ? 'success' : 'pending');
      final paystackStatus = data['paystackStatus'] as String?;
      final message = (data['message'] as String?) ?? (isSuccess ? 'Payment verified' : 'Waiting for payment confirmation...');
      final displayText = data['displayText'] as String?;
      final isPending = data['isPending'] == true || status == 'pending' || status == 'pay_offline' || status == 'ongoing';
      final alreadyFulfilled = data['alreadyFulfilled'] == true;

      return PaystackVerificationResult(
        success: isSuccess,
        status: status,
        paystackStatus: paystackStatus,
        message: message,
        displayText: displayText,
        isPending: isPending,
        alreadyFulfilled: alreadyFulfilled,
      );
    } catch (e) {
      debugPrint('PaystackService: Verify call error: $e');
      final isOffline = ConnectivityService().isOffline;
      return PaystackVerificationResult(
        success: false,
        status: isOffline ? 'offline' : 'error',
        message: isOffline
            ? 'Payment confirmation pending. We will verify your payment when connectivity returns.'
            : 'Verification check failed: $e',
        isPending: true,
      );
    }
  }

  void _notifyStatus(String reference, String message) {
    final list = _listeners[reference];
    if (list != null) {
      for (final l in List<PaystackVerificationListener>.from(list)) {
        l.onStatusUpdate?.call(message);
      }
    }
  }

  void _handleVerificationSuccess(String reference) {
    if (_notifiedSuccessReferences.contains(reference)) return;

    final list = _listeners.remove(reference);
    if (list != null && list.isNotEmpty) {
      // Modal is open with an active listener: let the modal update its UI and pop
      for (final l in List<PaystackVerificationListener>.from(list)) {
        l.onSuccess?.call();
      }
      _notifiedSuccessReferences.add(reference);
    } else {
      // Modal is closed / dismissed: trigger existing green success notification globally!
      _notifiedSuccessReferences.add(reference);
      TopNotificationService().showNotification(
        null,
        'Subscription successful. Enjoy ad-free access!',
        type: TopNotificationType.success,
      );
    }
  }

  void _handleVerificationFailure(String reference, String errorMessage) {
    final list = _listeners.remove(reference);
    if (list != null && list.isNotEmpty) {
      for (final l in List<PaystackVerificationListener>.from(list)) {
        l.onFailure?.call(errorMessage);
      }
    } else {
      debugPrint('PaystackService: Payment $reference failed in background. Modal closed, suppressed popup.');
    }
  }

  void _handleVerificationTimeout(String reference, String timeoutMessage) {
    final list = _listeners.remove(reference);
    if (list != null && list.isNotEmpty) {
      for (final l in List<PaystackVerificationListener>.from(list)) {
        l.onFailure?.call(timeoutMessage);
      }
    } else {
      debugPrint('PaystackService: Payment $reference timed out in background. Modal closed, suppressed popup.');
    }
  }

  /// Initiates or attaches to the background verification polling loop.
  /// Survives modal dismissal, screen navigation, and widget lifecycle disposal.
  Future<void> startBackgroundVerification({
    required String reference,
    required String packageId,
    required PaystackPaymentMethod method,
    required String phoneNumber,
    String? cardNumber,
    PaystackVerificationListener? listener,
  }) async {
    if (listener != null) {
      addVerificationListener(reference, listener);
    }

    // Guard against starting duplicate polling loops for the same reference
    if (_activeVerifications.contains(reference)) {
      debugPrint('PaystackService: Verification loop already active for $reference');
      return;
    }

    _activeVerifications.add(reference);
    _activePackageIds[reference] = packageId;

    // Safe verification polling loop (up to 180 seconds per Paystack Kenya mobile-money documentation)
    const int maxPollSeconds = 180;
    const int pollIntervalSeconds = 3;
    final int maxAttempts = maxPollSeconds ~/ pollIntervalSeconds;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      if (!_activeVerifications.contains(reference)) return;

      await Future.delayed(const Duration(seconds: pollIntervalSeconds));
      if (!_activeVerifications.contains(reference)) return;

      // Check if connection was lost while awaiting authorization
      if (ConnectivityService().isOffline) {
        const offlineMsg = 'Payment confirmation is pending. We will verify your payment when connectivity returns.';
        _lastStatusMessages[reference] = offlineMsg;
        _notifyStatus(reference, offlineMsg);
        continue;
      }

      try {
        final verifyResult = await verifyPayment(reference);

        if (verifyResult.success || verifyResult.alreadyFulfilled) {
          // Success confirmed! Save successful phone number locally and clean up unresolved reference
          if (method == PaystackPaymentMethod.mpesa ||
              method == PaystackPaymentMethod.airtelMoney) {
            await saveLastSuccessfulPhone(method, phoneNumber);
          } else if (method == PaystackPaymentMethod.mastercard && cardNumber != null) {
            final cardNum = cardNumber.replaceAll(' ', '');
            if (cardNum.length >= 4) {
              await saveLastCardMetadata(
                brand: 'Mastercard',
                last4: cardNum.substring(cardNum.length - 4),
              );
            }
          }

          await removeUnresolvedPayment(reference);
          _activeVerifications.remove(reference);
          _activePackageIds.remove(reference);
          _lastStatusMessages.remove(reference);

          _handleVerificationSuccess(reference);
          return;
        } else if (verifyResult.status == 'failed' ||
                   verifyResult.status == 'abandoned' ||
                   verifyResult.status == 'reversed') {
          // Terminal failure: Provider or PIN error
          await removeUnresolvedPayment(reference);
          _activeVerifications.remove(reference);
          _activePackageIds.remove(reference);
          _lastStatusMessages.remove(reference);

          final errorMsg = verifyResult.status == 'abandoned'
              ? 'Payment was not completed or expired. Please try again.'
              : (verifyResult.status == 'reversed'
                  ? 'Payment was reversed.'
                  : verifyResult.message);

          _handleVerificationFailure(reference, errorMsg);
          return;
        } else {
          // Status is still pending, ongoing, or pay_offline
          if (verifyResult.displayText != null) {
            _lastStatusMessages[reference] = verifyResult.displayText!;
            _notifyStatus(reference, verifyResult.displayText!);
          }
        }
      } catch (e) {
        debugPrint('PaystackService: Polling error for $reference: $e');
      }
    }

    // Polling reached 180s without final resolution
    _activeVerifications.remove(reference);
    _activePackageIds.remove(reference);
    _lastStatusMessages.remove(reference);

    const timeoutMsg = 'Payment confirmation timed out. If you already authorized on your phone, your subscription will activate automatically once confirmed.';
    _handleVerificationTimeout(reference, timeoutMsg);
  }
}
