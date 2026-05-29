import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'persistence_service.dart';

class UsageSession {
  final DateTime startTime;
  DateTime? endTime;
  final Map<String, int> materialTime; // Title -> seconds

  UsageSession({required this.startTime}) : materialTime = {};

  int get totalSeconds => (endTime ?? DateTime.now()).difference(startTime).inSeconds;
}

class UsageService extends ChangeNotifier with WidgetsBindingObserver {
  static final UsageService _instance = UsageService._internal();
  factory UsageService() => _instance;
  UsageService._internal();

  UsageSession? _currentSession;
  String? _activeMaterial;
  DateTime? _materialStartTime;

  int _totalAppSeconds = 0;
  Map<String, int> _dailyUsage = {}; // ISO Date -> seconds
  Map<String, int> _materialStats = {}; // Title -> seconds
  int _streak = 0;
  DateTime? _lastStreakUpdate;

  bool _isInitialized = false;

  int get streak => _streak;
  int get totalAppSeconds => _totalAppSeconds;
  Map<String, int> get dailyUsage => _dailyUsage;
  Map<String, int> get materialStats => _materialStats;

  Future<void> init() async {
    if (_isInitialized) return;
    
    _totalAppSeconds = PersistenceService().getInt('total_app_seconds') ?? 0;
    _streak = PersistenceService().getInt('app_streak') ?? 0;
    
    final dailyJson = PersistenceService().getString('daily_usage_history') ?? '{}';
    _dailyUsage = Map<String, int>.from(jsonDecode(dailyJson));
    
    final materialJson = PersistenceService().getString('material_usage_stats') ?? '{}';
    _materialStats = Map<String, int>.from(jsonDecode(materialJson));

    final lastStreak = PersistenceService().getString('last_streak_update');
    if (lastStreak != null) _lastStreakUpdate = DateTime.parse(lastStreak);

    _isInitialized = true;
    WidgetsBinding.instance.addObserver(this);
    _startSession();
    _checkStreak();
  }

  void _startSession() {
    _currentSession = UsageSession(startTime: DateTime.now());
  }

  void _endSession() {
    if (_currentSession == null) return;
    
    stopMaterialTracking();
    _currentSession!.endTime = DateTime.now();
    
    final seconds = _currentSession!.totalSeconds;
    _totalAppSeconds += seconds;
    
    final today = _getTodayKey();
    _dailyUsage[today] = (_dailyUsage[today] ?? 0) + seconds;
    
    _saveStats();
    _checkStreak();
    _currentSession = null;
  }

  String _getTodayKey() => DateTime.now().toIso8601String().split('T')[0];

  void _checkStreak() {
    final today = _getTodayKey();
    final yesterday = DateTime.now().subtract(const Duration(days: 1)).toIso8601String().split('T')[0];
    
    // If today's usage > 20 mins (1200 seconds)
    if ((_dailyUsage[today] ?? 0) >= 1200) {
      if (_lastStreakUpdate == null || _lastStreakUpdate!.toIso8601String().split('T')[0] != today) {
        // Increment streak if last update was yesterday or never
        if (_lastStreakUpdate == null || _lastStreakUpdate!.toIso8601String().split('T')[0] == yesterday) {
          _streak++;
        } else if (_lastStreakUpdate!.toIso8601String().split('T')[0] != today) {
          // Reset streak if we missed a day
          _streak = 1;
        }
        _lastStreakUpdate = DateTime.now();
        _saveStreak();
      }
    } else {
      // Check if we lost the streak (last update was before yesterday)
      if (_lastStreakUpdate != null) {
        final lastDate = _lastStreakUpdate!.toIso8601String().split('T')[0];
        if (lastDate != today && lastDate != yesterday) {
          _streak = 0;
          _saveStreak();
        }
      }
    }
    notifyListeners();
  }

  void startMaterialTracking(String title) {
    stopMaterialTracking();
    _activeMaterial = title;
    _materialStartTime = DateTime.now();
  }

  void stopMaterialTracking() {
    if (_activeMaterial != null && _materialStartTime != null) {
      final seconds = DateTime.now().difference(_materialStartTime!).inSeconds;
      _materialStats[_activeMaterial!] = (_materialStats[_activeMaterial!] ?? 0) + seconds;
      _activeMaterial = null;
      _materialStartTime = null;
    }
  }

  Future<void> _saveStats() async {
    await PersistenceService().setInt('total_app_seconds', _totalAppSeconds);
    await PersistenceService().setString('daily_usage_history', jsonEncode(_dailyUsage));
    await PersistenceService().setString('material_usage_stats', jsonEncode(_materialStats));
  }

  Future<void> _saveStreak() async {
    await PersistenceService().setInt('app_streak', _streak);
    if (_lastStreakUpdate != null) {
      await PersistenceService().setString('last_streak_update', _lastStreakUpdate!.toIso8601String());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _endSession();
    } else if (state == AppLifecycleState.resumed) {
      _startSession();
    }
  }

  void disposeService() {
    _endSession();
    WidgetsBinding.instance.removeObserver(this);
  }
}
