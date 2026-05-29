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

  // Generic Helpers
  Future<bool> setString(String key, String value) => _prefs.setString(key, value);
  String? getString(String key) => _prefs.getString(key);

  Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);
  bool? getBool(String key) => _prefs.getBool(key);

  Future<bool> setInt(String key, int value) => _prefs.setInt(key, value);
  int? getInt(String key) => _prefs.getInt(key);

  Future<bool> setDouble(String key, double value) => _prefs.setDouble(key, value);
  double? getDouble(String key) => _prefs.getDouble(key);

  Future<bool> setStringList(String key, List<String> value) => _prefs.setStringList(key, value);
  List<String>? getStringList(String key) => _prefs.getStringList(key);

  Future<bool> remove(String key) => _prefs.remove(key);

  // Complex Objects
  Future<bool> setJson(String key, dynamic value) {
    return _prefs.setString(key, jsonEncode(value));
  }

  dynamic getJson(String key) {
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
    await _prefs.clear();
  }
}
