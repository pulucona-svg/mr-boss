import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/persistence_service.dart';

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.dark) {
    _restoreTheme();
  }

  void _restoreTheme() {
    final themeStr = PersistenceService().getString('theme_mode');
    if (themeStr != null) {
      if (themeStr == 'light') state = ThemeMode.light;
      if (themeStr == 'dark') state = ThemeMode.dark;
      if (themeStr == 'system') state = ThemeMode.system;
    }
  }

  void setTheme(ThemeMode mode) {
    state = mode;
    PersistenceService().setString('theme_mode', mode.name);
  }

  void toggleTheme() {
    if (state == ThemeMode.dark) {
      setTheme(ThemeMode.light);
    } else {
      setTheme(ThemeMode.dark);
    }
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});
