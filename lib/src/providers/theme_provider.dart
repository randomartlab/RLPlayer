import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_mode.dart';

/// 主题设置状态（KikoFlu `theme_provider.dart` 移植，provider/ChangeNotifier 版）。
class ThemeSettings {
  final AppThemeMode themeMode;
  final ColorSchemeType colorSchemeType;

  const ThemeSettings({
    this.themeMode = AppThemeMode.system,
    this.colorSchemeType = ColorSchemeType.oceanBlue,
  });

  ThemeSettings copyWith({
    AppThemeMode? themeMode,
    ColorSchemeType? colorSchemeType,
  }) {
    return ThemeSettings(
      themeMode: themeMode ?? this.themeMode,
      colorSchemeType: colorSchemeType ?? this.colorSchemeType,
    );
  }

  ThemeMode toThemeMode() {
    switch (themeMode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }
}

/// 主题设置控制器：持久化至 SharedPreferences。
class ThemeSettingsProvider extends ChangeNotifier {
  static const String _themeModeKey = 'theme_mode';
  static const String _colorSchemeTypeKey = 'color_scheme_type';

  ThemeSettings _settings = const ThemeSettings();
  bool _loaded = false;
  bool _changedLocally = false;

  ThemeSettings get settings => _settings;

  ThemeSettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final themeModeIndex = prefs.getInt(_themeModeKey) ?? 0;
    final colorSchemeTypeIndex = prefs.getInt(_colorSchemeTypeKey) ?? 0;
    if (_loaded && _changedLocally) return;
    _loaded = true;

    _settings = ThemeSettings(
      themeMode: AppThemeMode.values[themeModeIndex],
      colorSchemeType: ColorSchemeType.values[colorSchemeTypeIndex],
    );
    notifyListeners();
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    _changedLocally = true;
    _settings = _settings.copyWith(themeMode: mode);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
  }

  Future<void> setColorSchemeType(ColorSchemeType type) async {
    _changedLocally = true;
    _settings = _settings.copyWith(colorSchemeType: type);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_colorSchemeTypeKey, type.index);
  }

  Future<void> resetToDefault() async {
    _changedLocally = true;
    _settings = const ThemeSettings();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, AppThemeMode.system.index);
    await prefs.setInt(_colorSchemeTypeKey, ColorSchemeType.oceanBlue.index);
  }
}
