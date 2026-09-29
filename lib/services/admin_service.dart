import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/manual_ad.dart';

/// Representation of an administrative module returned by the backend.
class AdminMenuItem {
  final String id;
  final String title;
  final String subtitle;
  final String icon;
  final bool enabled;
  final String? badge;

  const AdminMenuItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.enabled,
    this.badge,
  });

  factory AdminMenuItem.fromJson(Map<String, dynamic> json) {
    return AdminMenuItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      icon: json['icon'] as String? ?? 'admin_panel_settings_outlined',
      enabled: json['enabled'] as bool? ?? false,
      badge: json['badge'] as String?,
    );
  }
}

/// Dynamic capabilities payload returned by the authoritative backend endpoint.
class AdminCapabilities {
  final bool authorized;
  final String role;
  final String adminUid;
  final List<AdminMenuItem> menu;

  const AdminCapabilities({
    required this.authorized,
    required this.role,
    required this.adminUid,
    required this.menu,
  });

  factory AdminCapabilities.fromJson(Map<String, dynamic> json) {
    final rawMenu = json['menu'] as List<dynamic>? ?? [];
    return AdminCapabilities(
      authorized: json['authorized'] as bool? ?? false,
      role: json['role'] as String? ?? '',
      adminUid: json['adminUid'] as String? ?? '',
      menu: rawMenu
          .whereType<Map>()
          .map((item) => AdminMenuItem.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }

}

/// Service managing administrative authentication status and backend capabilities.
/// 
/// The Flutter client does NOT decide who is an admin using hardcoded emails.
/// Authorization is strictly enforced server-side via Firebase Auth Custom Claims (`admin: true`).
class AdminService extends ChangeNotifier {
  static AdminService _instance = AdminService._internal();
  factory AdminService() => _instance;

  @visibleForTesting
  static void resetInstance() {
    _instance = AdminService._internal();
  }

  @override
  // ignore: must_call_super
  void dispose() {
    // Prevent singleton disposal from destroying persistent instance
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  bool _isAdmin = false;
  bool get isAdmin => _isAdmin;

  AdminCapabilities? _cachedCapabilities;
  AdminCapabilities? get cachedCapabilities => _cachedCapabilities;

  List<AdminMenuItem> get menu => _cachedCapabilities?.menu ?? const [];

  bool _isChecking = false;
  bool get isChecking => _isChecking;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  AdminService._internal() {
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        isCurrentUserAdmin();
      } else {
        clear();
      }
    });
  }

  /// Inspects the Firebase Auth ID token claims for `admin: true`.
  /// Forces a token refresh if claims are not yet cached locally.
  Future<bool> isCurrentUserAdmin({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) {
      _isAdmin = false;
      _cachedCapabilities = null;
      notifyListeners();
      return false;
    }

    try {
      // 1. Inspect existing token claims
      IdTokenResult tokenResult = await user.getIdTokenResult(forceRefresh);
      bool adminClaim = tokenResult.claims?['admin'] == true;

      // 2. If claim is not present in cached token, force token refresh from Firebase Auth
      if (!adminClaim) {
        tokenResult = await user.getIdTokenResult(true);
        adminClaim = tokenResult.claims?['admin'] == true;
      }

      // 3. If still not admin, attempt silent backend claim sync for allowlisted accounts
      if (!adminClaim) {
        try {
          debugPrint('AdminService: [AUTH] Requesting server-side claim sync for caller...');
          await _functions.httpsCallable('syncAdminClaim').call();
          tokenResult = await user.getIdTokenResult(true);
          adminClaim = tokenResult.claims?['admin'] == true;
          debugPrint('AdminService: [AUTH] Post-sync admin claim result: $adminClaim');
        } catch (e) {
          debugPrint('AdminService: [AUTH] syncAdminClaim skipped or rejected: $e');
        }
      }

      if (_isAdmin != adminClaim) {
        _isAdmin = adminClaim;
        notifyListeners();
      }

      return _isAdmin;
    } catch (e) {
      debugPrint('AdminService: [ERROR] isCurrentUserAdmin check failed: $e');
      _isAdmin = false;
      notifyListeners();
      return false;
    }
  }

  /// Calls the backend `getAdminCapabilities` Cloud Function.
  /// 
  /// The backend verifies `request.auth.token.admin === true` and returns the
  /// authoritative menu definition.
  Future<AdminCapabilities?> getAdminCapabilities({bool forceRefresh = false}) async {
    _isChecking = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = _auth.currentUser;
      if (user == null) {
        _cachedCapabilities = null;
        _isChecking = false;
        notifyListeners();
        return null;
      }

      // Cryptographic check: Only proceed if ID token verifies admin: true
      final adminVerified = await isCurrentUserAdmin(forceRefresh: forceRefresh);
      if (!adminVerified) {
        _cachedCapabilities = null;
        _isChecking = false;
        notifyListeners();
        return null;
      }

      try {
        debugPrint('AdminService: [CAPABILITIES] Requesting getAdminCapabilities from backend...');
        final result = await _functions.httpsCallable('getAdminCapabilities').call();

        if (result.data is Map) {
          final data = Map<String, dynamic>.from(result.data as Map);
          _cachedCapabilities = AdminCapabilities.fromJson(data);
          debugPrint('AdminService: [CAPABILITIES] Received ${_cachedCapabilities?.menu.length} modules from backend.');
          _isChecking = false;
          notifyListeners();
          return _cachedCapabilities;
        }
      } on FirebaseFunctionsException catch (e) {
        debugPrint('AdminService: [CAPABILITIES] FirebaseFunctionsException: ${e.code} - ${e.message}');
        _errorMessage = e.message ?? e.code;
        _cachedCapabilities = null;
        _isChecking = false;
        notifyListeners();
        return null;
      } catch (e) {
        debugPrint('AdminService: [CAPABILITIES] Remote function error: $e');
        _errorMessage = e.toString();
        _cachedCapabilities = null;
        _isChecking = false;
        notifyListeners();
        return null;
      }

      _isChecking = false;
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('AdminService: [ERROR] Failed to fetch admin capabilities: $e');
      _errorMessage = e.toString();
      _cachedCapabilities = null;
      _isChecking = false;
      notifyListeners();
      return null;
    }
  }

  /// Clears cached capabilities on logout.
  void clear() {
    _isAdmin = false;
    _cachedCapabilities = null;
    _isChecking = false;
    notifyListeners();
  }

  // =========================================================================
  // MODULE 1: MANUAL ADS MANAGEMENT
  // =========================================================================

  /// Retrieves manual ads using the authoritative backend callable function.
  Future<List<ManualAd>> getManualAds({bool forceRefresh = false}) async {
    final bool admin = await isCurrentUserAdmin(forceRefresh: forceRefresh);
    if (!admin) {
      throw Exception('Permission denied: User does not possess administrator privileges.');
    }

    debugPrint('AdminService: [ADS] Attempting to fetch manual ads via callable function getAdminManualAds...');
    final result = await _functions.httpsCallable('getAdminManualAds').call();
    if (result.data is Map && result.data['ads'] is List) {
      final list = (result.data['ads'] as List).whereType<Map>().map((m) {
        final map = Map<String, dynamic>.from(m);
        final id = map['id']?.toString() ?? '';
        return ManualAd.fromMap(id, map);
      }).toList();
      debugPrint('AdminService: [ADS] Fetched ${list.length} ads via backend callable.');
      return list;
    }
    return [];
  }

  /// Saves (creates or updates) a manual ad via backend callable function.
  Future<ManualAd> saveManualAd(ManualAd ad) async {
    final bool admin = await isCurrentUserAdmin();
    if (!admin) {
      throw Exception('Permission denied: User does not possess administrator privileges.');
    }

    debugPrint('AdminService: [ADS] Attempting to save manual ad via callable function saveAdminManualAd...');
    final result = await _functions.httpsCallable('saveAdminManualAd').call({
      if (ad.id.isNotEmpty && !ad.id.startsWith('default_')) 'id': ad.id,
      'title': ad.title,
      'subtitle': ad.subtitle,
      'imageUrl': ad.imageUrl,
      'contactUrl': ad.contactUrl,
      'colorValue': ad.colorValue,
      'isActive': ad.isActive,
      'isAsset': ad.isAsset,
      'type': ad.type,
      'placement': ad.placement,
      if (ad.mediaFileId != null && ad.mediaFileId!.isNotEmpty) 'mediaFileId': ad.mediaFileId,
    });

    if (result.data is Map && result.data['id'] != null) {
      final targetId = result.data['id'].toString();
      debugPrint('AdminService: [ADS] Successfully saved ad $targetId via callable function.');
      if (result.data['ad'] is Map) {
        final adMap = Map<String, dynamic>.from(result.data['ad'] as Map);
        return ManualAd.fromMap(targetId, adMap);
      }
      return ad.copyWith(id: targetId);
    }
    throw Exception('Failed to save ad: Invalid response from backend.');
  }

  /// Toggles the active status of a manual ad via backend callable function.
  Future<bool> toggleManualAdStatus(String adId, bool isActive) async {
    final bool admin = await isCurrentUserAdmin();
    if (!admin) {
      throw Exception('Permission denied: User does not possess administrator privileges.');
    }

    debugPrint('AdminService: [ADS] Attempting toggleManualAdStatus via callable function...');
    await _functions.httpsCallable('toggleAdminManualAdStatus').call({
      'id': adId,
      'isActive': isActive,
    });
    return true;
  }

  /// Deletes a manual ad with explicit admin confirmation via backend callable function.
  Future<bool> deleteManualAd(String adId) async {
    final bool admin = await isCurrentUserAdmin();
    if (!admin) {
      throw Exception('Permission denied: User does not possess administrator privileges.');
    }

    debugPrint('AdminService: [ADS] Attempting deleteManualAd via callable function...');
    await _functions.httpsCallable('deleteAdminManualAd').call({
      'id': adId,
    });
    return true;
  }

  /// Seeds default offline ads into the database if empty via backend callable function.
  Future<bool> seedDefaultAds({bool force = false}) async {
    final bool admin = await isCurrentUserAdmin();
    if (!admin) {
      throw Exception('Permission denied: User does not possess administrator privileges.');
    }

    debugPrint('AdminService: [ADS] Attempting seedDefaultAds via callable function...');
    final res = await _functions.httpsCallable('seedDefaultManualAds').call({
      'force': force,
    });
    if (res.data is Map && res.data['success'] == true) {
      return true;
    }
    return false;
  }

  // ==========================================
  // NEWS ARTICLES MODULE 2 ADMIN OPERATIONS
  // ==========================================

  /// Creates a new news article manually via backend callable function.
  Future<Map<String, dynamic>> createAdminArticle({
    required String categoryId,
    required String categoryName,
    required String source,
    required String title,
    required String sourceUrl,
    required List<Map<String, dynamic>> subtopics,
  }) async {
    final bool admin = await isCurrentUserAdmin();
    if (!admin) {
      throw Exception('Permission denied: User does not possess administrator privileges.');
    }

    debugPrint('AdminService: [NEWS] Creating article "$title" via callable function...');
    final res = await _functions.httpsCallable('createAdminArticle').call({
      'categoryId': categoryId,
      'categoryName': categoryName,
      'source': source,
      'title': title,
      'sourceUrl': sourceUrl,
      'subtopics': subtopics,
    });

    if (res.data is Map) {
      return Map<String, dynamic>.from(res.data as Map);
    }
    return {'success': true};
  }

  /// Deactivates one or more active articles.
  Future<bool> deactivateArticles(List<String> articleIds) async {
    final bool admin = await isCurrentUserAdmin();
    if (!admin) {
      throw Exception('Permission denied: User does not possess administrator privileges.');
    }

    debugPrint('AdminService: [NEWS] Deactivating ${articleIds.length} articles via callable function...');
    final res = await _functions.httpsCallable('deactivateAdminArticles').call({
      'articleIds': articleIds,
    });

    return res.data is Map && res.data['success'] == true;
  }

  /// Restores one or more deactivated articles back to "published".
  Future<bool> restoreArticles(List<String> articleIds) async {
    final bool admin = await isCurrentUserAdmin();
    if (!admin) {
      throw Exception('Permission denied: User does not possess administrator privileges.');
    }

    debugPrint('AdminService: [NEWS] Restoring ${articleIds.length} articles via callable function...');
    final res = await _functions.httpsCallable('restoreAdminArticles').call({
      'articleIds': articleIds,
    });

    return res.data is Map && res.data['success'] == true;
  }

  /// Permanently deletes one or more articles and their ImageKit assets.
  Future<bool> deleteArticles(List<String> articleIds) async {
    final bool admin = await isCurrentUserAdmin();
    if (!admin) {
      throw Exception('Permission denied: User does not possess administrator privileges.');
    }

    debugPrint('AdminService: [NEWS] Permanently deleting ${articleIds.length} articles via callable function...');
    final res = await _functions.httpsCallable('deleteAdminArticles').call({
      'articleIds': articleIds,
    });

    return res.data is Map && res.data['success'] == true;
  }

  /// Fetches deactivated articles for the Admin Activate/Recovery screen.
  Future<List<Map<String, dynamic>>> getDeactivatedArticles() async {
    final bool admin = await isCurrentUserAdmin();
    if (!admin) {
      throw Exception('Permission denied: User does not possess administrator privileges.');
    }

    debugPrint('AdminService: [NEWS] Fetching deactivated articles via callable function...');
    final res = await _functions.httpsCallable('getDeactivatedArticles').call();

    if (res.data is Map && res.data['articles'] is List) {
      final list = res.data['articles'] as List;
      return list
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return [];
  }
}
