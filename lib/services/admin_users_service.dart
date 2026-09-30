import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/admin_user_model.dart';

class AdminUsersService extends ChangeNotifier {
  static final AdminUsersService _instance = AdminUsersService._internal();
  factory AdminUsersService() => _instance;
  AdminUsersService._internal();
  @visibleForTesting
  AdminUsersService.internal();

  FirebaseFunctions? _testFunctions;
  FirebaseFunctions get _functions => _testFunctions ?? FirebaseFunctions.instance;

  @visibleForTesting
  void setFunctionsForTesting(FirebaseFunctions? functions) {
    _testFunctions = functions;
  }

  /// Fetches a paginated, filterable list of registered users.
  Future<({List<AdminUserSummary> users, String? nextPageToken})> getUsersList({
    int pageSize = 25,
    String? pageToken,
    String? searchQuery,
    String roleFilter = 'all',
  }) async {
    try {
      final callable = _functions.httpsCallable('getAdminUsersList');
      final result = await callable.call({
        'pageSize': pageSize,
        'pageToken': ?pageToken,
        if (searchQuery != null && searchQuery.isNotEmpty) 'searchQuery': searchQuery,
        'roleFilter': roleFilter,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      final rawUsers = data['users'] as List<dynamic>? ?? [];
      final users = rawUsers
          .whereType<Map>()
          .map((u) => AdminUserSummary.fromJson(Map<String, dynamic>.from(u)))
          .toList();

      final nextPageToken = data['nextPageToken'] as String?;

      return (users: users, nextPageToken: nextPageToken);
    } catch (e) {
      debugPrint('[ADMIN_USERS_SERVICE_ERROR] getUsersList failed: $e');
      rethrow;
    }
  }

  /// Fetches aggregated administrative history and profile for a specific user.
  Future<AdminUserFullProfile> getUserDetail(String targetUid) async {
    try {
      final callable = _functions.httpsCallable('getAdminUserDetail');
      final result = await callable.call({
        'targetUid': targetUid,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      return AdminUserFullProfile.fromJson(data);
    } catch (e) {
      debugPrint('[ADMIN_USERS_SERVICE_ERROR] getUserDetail failed for $targetUid: $e');
      rethrow;
    }
  }

  /// Toggles account disabled state in Firebase Authentication and Firestore.
  Future<Map<String, dynamic>> toggleUserDisabled(
    String targetUid,
    bool disabled, {
    String? reason,
  }) async {
    try {
      final callable = _functions.httpsCallable('toggleAdminUserDisabled');
      final result = await callable.call({
        'targetUid': targetUid,
        'disabled': disabled,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      notifyListeners();
      return data;
    } catch (e) {
      debugPrint('[ADMIN_USERS_SERVICE_ERROR] toggleUserDisabled failed for $targetUid: $e');
      rethrow;
    }
  }
}
