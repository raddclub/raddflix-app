import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';

enum JazzTheme { dark, amoled, light, auto }

class ThemeState {
  final JazzTheme mode;
  final bool isDark;
  const ThemeState({required this.mode, required this.isDark});
}

class ThemeNotifier extends StateNotifier<ThemeState> {
  ThemeNotifier() : super(const ThemeState(mode: JazzTheme.dark, isDark: true)) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(StorageKeys.themeMode) ?? 'dark';
    final mode = JazzTheme.values.firstWhere(
      (e) => e.name == saved, orElse: () => JazzTheme.dark);
    state = ThemeState(mode: mode, isDark: _computeIsDark(mode));
  }

  bool _computeIsDark(JazzTheme mode) {
    if (mode == JazzTheme.light) return false;
    if (mode == JazzTheme.auto) {
      final hour = DateTime.now().hour;
      return hour < 6 || hour >= 19; // Night = dark
    }
    return true;
  }

  Future<void> setTheme(JazzTheme mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.themeMode, mode.name);
    state = ThemeState(mode: mode, isDark: _computeIsDark(mode));
  }

  String get displayName {
    switch (state.mode) {
      case JazzTheme.dark:   return 'Dark';
      case JazzTheme.amoled: return 'AMOLED';
      case JazzTheme.light:  return 'Light';
      case JazzTheme.auto:   return 'Auto';
    }
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>(
  (ref) => ThemeNotifier(),
);
