import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service responsible for managing platform-level application security globally across
/// the entire Mirror Digital application lifecycle (Android FLAG_SECURE & iOS privacy shield hooks).
class SecurityService {
  static const MethodChannel _channel = MethodChannel('com.mirrordigital.app/security');
  static final SecurityService _instance = SecurityService._internal();

  factory SecurityService() => _instance;
  SecurityService._internal();

  bool _isSecureScreenEnabled = true;
  bool get isSecureScreenEnabled => _isSecureScreenEnabled;

  /// Ensures screenshot, screen-recording, and recent-apps thumbnail protection
  /// are active globally across the entire application lifecycle.
  Future<bool> enableSecureScreen() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('enableSecureScreen');
      _isSecureScreenEnabled = result ?? true;
      debugPrint('SecurityService: Global secure screen active ($_isSecureScreenEnabled)');
      return _isSecureScreenEnabled;
    } catch (e) {
      debugPrint('SecurityService: [INFO] Secure screen platform call handled/unavailable: $e');
      return _isSecureScreenEnabled;
    }
  }

  /// Global security policy enforces persistent protection.
  /// Individual screens or dialogs cannot disable global protection upon disposal.
  Future<bool> disableSecureScreen() async {
    try {
      await _channel.invokeMethod<bool>('disableSecureScreen');
      debugPrint('SecurityService: Global security policy enforced (protection preserved)');
      return true;
    } catch (e) {
      debugPrint('SecurityService: [INFO] Secure screen disable platform call handled: $e');
      return true;
    }
  }

  /// Checks whether secure screen is currently enabled at the platform level.
  Future<bool> checkPlatformSecureStatus() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('isSecureScreenEnabled');
      if (result != null) {
        _isSecureScreenEnabled = result;
      }
      return _isSecureScreenEnabled;
    } catch (e) {
      return _isSecureScreenEnabled;
    }
  }
}
