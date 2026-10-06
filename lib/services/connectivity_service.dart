import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ConnectivityService extends ChangeNotifier {
  static ConnectivityService? _instance;
  factory ConnectivityService() => _instance ??= ConnectivityService._internal();
  ConnectivityService._internal();

  /// Evaluates whether an error/exception represents a network or connectivity failure.
  static bool isNetworkError(dynamic error) {
    if (error == null) {
      return _instance != null && _instance!.isOffline;
    }

    // Exclude programming / syntax / type errors
    if (error is FormatException || error is TypeError || error is AssertionError) {
      return false;
    }

    // Explicitly check for FirebaseAuthException first to protect genuine auth errors
    if (error is FirebaseAuthException) {
      return error.code == 'network-request-failed';
    }

    // Firebase general / Firestore network error codes
    if (error is FirebaseException) {
      if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
        return true;
      }
    }

    // Standard Dart I/O and async network exceptions
    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException ||
        error is HandshakeException ||
        error is TlsException ||
        error is http.ClientException) {
      return true;
    }

    // Direct interface check if offline
    if (_instance != null && _instance!.isOffline) {
      return true;
    }

    // Targeted string patterns for known network failures
    final msg = error.toString().toLowerCase();

    // Guard against treating known non-network authentication codes/messages as network errors
    if (msg.contains('wrong-password') ||
        msg.contains('user-not-found') ||
        msg.contains('email-already-in-use') ||
        msg.contains('invalid-email') ||
        msg.contains('weak-password') ||
        msg.contains('user-disabled') ||
        msg.contains('too-many-requests') ||
        msg.contains('invalid-credential') ||
        msg.contains('operation-not-allowed') ||
        msg.contains('requires-recent-login')) {
      return false;
    }

    return msg.contains('network-request-failed') ||
        msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection refused') ||
        msg.contains('connection timed out') ||
        msg.contains('connection reset') ||
        msg.contains('network is unreachable') ||
        msg.contains('clientexception') ||
        msg.contains('timed out') ||
        msg.contains('software caused connection abort') ||
        msg.contains('no address associated with hostname') ||
        msg.contains('os error:');
  }

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool? _wasOffline;
  bool _isInitialized = false;

  // Global key for showing snackbars without requiring BuildContext in async gaps
  final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

  bool _isOffline = false;
  bool get isOffline => _isOffline;

  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;
    _subscription?.cancel();
    _connectivity.checkConnectivity().then((results) {
      _isOffline = results.contains(ConnectivityResult.none);
      notifyListeners();
    });
    _subscription = _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      _handleConnectivityChange(results);
    });
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    _isOffline = results.contains(ConnectivityResult.none);
    notifyListeners();
    
    if (_isOffline) {
      _wasOffline = true;
      _showSnackBar(
        'Check internet connection to get latest material',
        Colors.redAccent,
        Icons.cloud_off_rounded,
      );
    } else {
      if (_wasOffline == true) {
        _showSnackBar(
          'You are back online, get latest materials',
          const Color(0xFF00A85A),
          Icons.cloud_done_rounded,
        );
        _wasOffline = false;
      }
    }
  }

  void _showSnackBar(String message, Color color, IconData icon) {
    final state = messengerKey.currentState;
    if (state == null) return;

    state.hideCurrentSnackBar();
    state.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: color.withAlpha(230),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _isInitialized = false;
    _instance = null;
    try {
      super.dispose();
    } catch (_) {}
  }

  void resetForTesting() {
    _subscription?.cancel();
    _subscription = null;
    _isInitialized = false;
    _isOffline = false;
    _wasOffline = null;
    _instance = null;
  }

  void setOfflineForTesting(bool offline) {
    _isOffline = offline;
    notifyListeners();
  }
}
