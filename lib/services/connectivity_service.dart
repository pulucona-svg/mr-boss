import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

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
        backgroundColor: color.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void dispose() {
    _subscription?.cancel();
  }
}
