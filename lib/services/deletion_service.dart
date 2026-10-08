import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class AccountDeletionResult {
  final bool success;
  final String status;
  final DateTime? deletionRequestedAt;
  final DateTime? deletionScheduledAt;
  final int gracePeriodDays;
  final String? errorMessage;

  const AccountDeletionResult({
    required this.success,
    this.status = 'none',
    this.deletionRequestedAt,
    this.deletionScheduledAt,
    this.gracePeriodDays = 30,
    this.errorMessage,
  });
}

class AccountRestoreResult {
  final bool success;
  final String status;
  final String message;
  final String? errorMessage;

  const AccountRestoreResult({
    required this.success,
    this.status = 'none',
    this.message = '',
    this.errorMessage,
  });
}

class DeletionService {
  static final DeletionService _instance = DeletionService._internal();
  factory DeletionService() => _instance;
  DeletionService._internal();

  FirebaseFunctions? _testFunctions;
  FirebaseFunctions get _functions => _testFunctions ?? FirebaseFunctions.instance;

  @visibleForTesting
  void setFunctionsForTesting(FirebaseFunctions? functions) {
    _testFunctions = functions;
  }

  static DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    if (val is String) return DateTime.tryParse(val);
    try {
      return (val as dynamic).toDate();
    } catch (_) {
      return null;
    }
  }

  /// Initiates account deletion and sets the 30-day grace period.
  /// Accepts optional questionnaire responses via [feedback].
  Future<AccountDeletionResult> requestAccountDeletion({
    Map<String, dynamic>? feedback,
  }) async {
    try {
      final callable = _functions.httpsCallable('requestAccountDeletion');
      final response = await callable.call<Map<String, dynamic>>({
        if (feedback != null && feedback.isNotEmpty) ...{
          'survey': feedback,
          'feedback': feedback,
        },
      });

      final data = Map<String, dynamic>.from(response.data);
      final isSuccess = data['success'] == true;
      final status = data['status'] as String? ?? 'pending';
      final requestedAt = _parseDate(data['deletionRequestedAt']);
      final scheduledAt = _parseDate(data['deletionScheduledAt']);
      final graceDays = (data['gracePeriodDays'] as num?)?.toInt() ?? 30;

      return AccountDeletionResult(
        success: isSuccess,
        status: status,
        deletionRequestedAt: requestedAt,
        deletionScheduledAt: scheduledAt,
        gracePeriodDays: graceDays,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('DeletionService: FirebaseFunctionsException [${e.code}]: ${e.message}');
      return AccountDeletionResult(
        success: false,
        errorMessage: e.message ?? 'An error occurred while requesting account deletion.',
      );
    } catch (e) {
      debugPrint('DeletionService: Error requesting account deletion: $e');
      final isOffline = e.toString().toLowerCase().contains('network') ||
          e.toString().toLowerCase().contains('socket') ||
          e.toString().toLowerCase().contains('offline');
      return AccountDeletionResult(
        success: false,
        errorMessage: isOffline
            ? 'You appear to be offline. Please check your internet connection and try again.'
            : 'Unable to request deletion. Please try again later.',
      );
    }
  }

  /// Restores a pending deletion account during the 30-day grace period.
  Future<AccountRestoreResult> restoreUserAccount() async {
    try {
      final callable = _functions.httpsCallable('restoreUserAccount');
      final response = await callable.call<Map<String, dynamic>>({});

      final data = Map<String, dynamic>.from(response.data);
      final isSuccess = data['success'] == true;
      final status = data['status'] as String? ?? 'none';
      final message = data['message'] as String? ?? 'Account restored successfully.';

      return AccountRestoreResult(
        success: isSuccess,
        status: status,
        message: message,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('DeletionService: FirebaseFunctionsException [${e.code}]: ${e.message}');
      return AccountRestoreResult(
        success: false,
        errorMessage: e.message ?? 'An error occurred while restoring your account.',
      );
    } catch (e) {
      debugPrint('DeletionService: Error restoring account: $e');
      final isOffline = e.toString().toLowerCase().contains('network') ||
          e.toString().toLowerCase().contains('socket') ||
          e.toString().toLowerCase().contains('offline');
      return AccountRestoreResult(
        success: false,
        errorMessage: isOffline
            ? 'You appear to be offline. Please check your internet connection and try again.'
            : 'Unable to restore account. Please try again later.',
      );
    }
  }
}
