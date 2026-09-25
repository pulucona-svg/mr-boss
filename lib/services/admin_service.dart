import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

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
  static final AdminService _instance = AdminService._internal();
  factory AdminService() => _instance;

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
}
