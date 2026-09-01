import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 偏好设置（PRD §5.10 偏好页分组，M11 元数据源控制）。
class PreferencesProvider extends ChangeNotifier {
  static const _metaEnabledKey = 'pref_meta_enabled';
  static const _wifiOnlyKey = 'pref_wifi_only';
  static const _subtitleDefaultKey = 'pref_subtitle_default';

  bool _metaEnabled = true;
  bool _wifiOnly = false;
  bool _subtitleDefault = false;

  bool get metaEnabled => _metaEnabled;
  bool get wifiOnly => _wifiOnly;
  bool get subtitleDefault => _subtitleDefault;

  PreferencesProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _metaEnabled = prefs.getBool(_metaEnabledKey) ?? true;
    _wifiOnly = prefs.getBool(_wifiOnlyKey) ?? false;
    _subtitleDefault = prefs.getBool(_subtitleDefaultKey) ?? false;
    notifyListeners();
  }

  Future<void> setMetaEnabled(bool v) async {
    _metaEnabled = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_metaEnabledKey, v);
  }

  Future<void> setWifiOnly(bool v) async {
    _wifiOnly = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_wifiOnlyKey, v);
  }

  Future<void> setSubtitleDefault(bool v) async {
    _subtitleDefault = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_subtitleDefaultKey, v);
  }
}
