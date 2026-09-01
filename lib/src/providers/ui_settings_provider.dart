import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 底部导航液态玻璃开关（PRD §3.2/§3.3）。
enum NavStyle {
  classic, // 经典 Material NavigationBar 58dp
  liquidGlass, // 液态玻璃胶囊 78dp（Android BackdropFilter 降级）
}

/// 玻璃模糊模式：清晰 sigma = 6 × intensity；朦胧 sigma = 10 × intensity。
enum GlassBlurMode { clear, hazy }

/// UI 偏好设置（持久化 SharedPreferences）。
class UiSettingsProvider extends ChangeNotifier {
  static const String _navStyleKey = 'nav_style';
  static const String _glassIntensityKey = 'glass_intensity';
  static const String _glassBlurModeKey = 'glass_blur_mode';
  static const String _uiFontScaleKey = 'ui_font_scale';
  static const String _lyricFontScaleKey = 'lyric_font_scale';

  NavStyle _navStyle = NavStyle.classic;
  double _glassIntensity = 0.4; // 原版默认 intensity
  GlassBlurMode _glassBlurMode = GlassBlurMode.clear;

  /// 全局界面字体缩放（0.8–1.4，叠加在系统缩放之上）。
  double _uiFontScale = 1.0;

  /// 歌词视图独立字体缩放（0.8–2.0，不影响其他界面）。
  double _lyricFontScale = 1.0;

  NavStyle get navStyle => _navStyle;
  double get uiFontScale => _uiFontScale;
  double get lyricFontScale => _lyricFontScale;
  double get glassIntensity => _glassIntensity;
  GlassBlurMode get glassBlurMode => _glassBlurMode;

  bool get useLiquidGlass => _navStyle == NavStyle.liquidGlass;

  UiSettingsProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _navStyle =
        NavStyle.values[prefs.getInt(_navStyleKey) ?? NavStyle.classic.index];
    _glassIntensity = prefs.getDouble(_glassIntensityKey) ?? 0.4;
    _glassBlurMode = GlassBlurMode.values[
        prefs.getInt(_glassBlurModeKey) ?? GlassBlurMode.clear.index];
    _uiFontScale = prefs.getDouble(_uiFontScaleKey) ?? 1.0;
    _lyricFontScale = prefs.getDouble(_lyricFontScaleKey) ?? 1.0;
    notifyListeners();
  }

  Future<void> setNavStyle(NavStyle style) async {
    _navStyle = style;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_navStyleKey, style.index);
  }

  Future<void> setGlassIntensity(double value) async {
    _glassIntensity = value.clamp(0.0, 1.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_glassIntensityKey, _glassIntensity);
  }

  Future<void> setUiFontScale(double value) async {
    _uiFontScale = value.clamp(0.8, 1.4);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_uiFontScaleKey, _uiFontScale);
  }

  Future<void> setLyricFontScale(double value) async {
    _lyricFontScale = value.clamp(0.8, 2.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_lyricFontScaleKey, _lyricFontScale);
  }

  Future<void> setGlassBlurMode(GlassBlurMode mode) async {
    _glassBlurMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_glassBlurModeKey, mode.index);
  }
}
