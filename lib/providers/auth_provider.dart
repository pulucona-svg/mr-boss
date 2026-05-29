import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/persistence_service.dart';

class AuthState {
  final String? lastSentEmail;
  final bool otpSent;
  final DateTime? expiryTime;
  final int remainingSeconds;
  final bool canResend;

  AuthState({
    this.lastSentEmail,
    this.otpSent = false,
    this.expiryTime,
    this.remainingSeconds = 0,
    this.canResend = false,
  });

  AuthState copyWith({
    String? lastSentEmail,
    bool? otpSent,
    DateTime? expiryTime,
    int? remainingSeconds,
    bool? canResend,
  }) {
    return AuthState(
      lastSentEmail: lastSentEmail ?? this.lastSentEmail,
      otpSent: otpSent ?? this.otpSent,
      expiryTime: expiryTime ?? this.expiryTime,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      canResend: canResend ?? this.canResend,
    );
  }
}

class AuthStateNotifier extends StateNotifier<AuthState> {
  AuthStateNotifier() : super(AuthState()) {
    _restoreState();
  }
  
  Timer? _timer;

  Future<void> _restoreState() async {
    final email = PersistenceService().getString('auth_last_email');
    final expiryStr = PersistenceService().getString('auth_expiry_time');
    
    if (email != null && expiryStr != null) {
      final expiry = DateTime.parse(expiryStr);
      final now = DateTime.now();
      final remaining = expiry.difference(now).inSeconds;
      
      if (remaining > 0) {
        state = state.copyWith(
          lastSentEmail: email,
          otpSent: true,
          expiryTime: expiry,
          remainingSeconds: remaining,
          canResend: false,
        );
        _ensureTimerIsRunning();
      } else {
        state = state.copyWith(
          lastSentEmail: email,
          otpSent: true,
          remainingSeconds: 0,
          canResend: true,
        );
      }
    }
  }

  Future<void> _saveState() async {
    if (state.lastSentEmail != null) {
      await PersistenceService().setString('auth_last_email', state.lastSentEmail!);
    }
    if (state.expiryTime != null) {
      await PersistenceService().setString('auth_expiry_time', state.expiryTime!.toIso8601String());
    }
  }

  void startTimer(String email, {int seconds = 60}) {
    final now = DateTime.now();
    
    // Check if there's already an active timer for this email
    if (state.lastSentEmail == email && state.otpSent && state.expiryTime != null) {
      final remaining = state.expiryTime!.difference(now).inSeconds;
      if (remaining > 0) {
        // Already running and has time left, don't restart
        _ensureTimerIsRunning();
        return;
      }
    }

    _timer?.cancel();
    final expiry = now.add(Duration(seconds: seconds));
    
    state = state.copyWith(
      lastSentEmail: email,
      otpSent: true,
      expiryTime: expiry,
      remainingSeconds: seconds,
      canResend: false,
    );

    _saveState();
    _ensureTimerIsRunning();
  }

  void _ensureTimerIsRunning() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      if (state.expiryTime == null) {
        timer.cancel();
        return;
      }

      final remaining = state.expiryTime!.difference(now).inSeconds;

      if (remaining <= 0) {
        state = state.copyWith(
          remainingSeconds: 0,
          canResend: true,
        );
        timer.cancel();
      } else {
        state = state.copyWith(
          remainingSeconds: remaining,
        );
      }
    });
  }

  void reset() {
    _timer?.cancel();
    state = AuthState();
    PersistenceService().remove('auth_last_email');
    PersistenceService().remove('auth_expiry_time');
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((ref) {
  final notifier = AuthStateNotifier();
  ref.onDispose(() => notifier.dispose());
  return notifier;
});
