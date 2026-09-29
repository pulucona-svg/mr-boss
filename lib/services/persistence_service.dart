import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PersistenceService {
  static final PersistenceService _instance = PersistenceService._internal();
  factory PersistenceService() => _instance;
  PersistenceService._internal();

  late SharedPreferences _prefs;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    _prefs = await SharedPreferences.getInstance();
    _isInitialized = true;
  }

  bool get isInitialized => _isInitialized;

  // Generic Helpers
  Future<bool> setString(String key, String value) async => _isInitialized ? _prefs.setString(key, value) : false;
  String? getString(String key) => _isInitialized ? _prefs.getString(key) : null;

  Future<bool> setBool(String key, bool value) async => _isInitialized ? _prefs.setBool(key, value) : false;
  bool? getBool(String key) => _isInitialized ? _prefs.getBool(key) : null;

  Future<bool> setInt(String key, int value) async => _isInitialized ? _prefs.setInt(key, value) : false;
  int? getInt(String key) => _isInitialized ? _prefs.getInt(key) : null;

  Future<bool> setDouble(String key, double value) async => _isInitialized ? _prefs.setDouble(key, value) : false;
  double? getDouble(String key) => _isInitialized ? _prefs.getDouble(key) : null;

  Future<bool> setStringList(String key, List<String> value) async => _isInitialized ? _prefs.setStringList(key, value) : false;
  List<String>? getStringList(String key) => _isInitialized ? _prefs.getStringList(key) : null;

  Future<bool> remove(String key) async => _isInitialized ? _prefs.remove(key) : false;

  // Complex Objects
  Future<bool> setJson(String key, dynamic value) async {
    if (!_isInitialized) return false;
    return _prefs.setString(key, jsonEncode(value));
  }

  dynamic getJson(String key) {
    if (!_isInitialized) return null;
    final str = _prefs.getString(key);
    if (str == null) return null;
    return jsonDecode(str);
  }

  // Session Management
  Future<void> saveSession(String userId) async {
    await setString('session_user_id', userId);
  }

  String? getSessionUserId() => getString('session_user_id');

  Future<void> clearSession() async {
    await remove('session_user_id');
  }

  // Reset all data (except session if needed, but usually all)
  Future<void> clearAll() async {
    if (_isInitialized) {
      await _prefs.clear();
    }
  }
}
