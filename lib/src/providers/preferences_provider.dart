import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 偏好设置（PRD §5.10 偏好页分组，M11 元数据源控制）。
class PreferencesProvider extends ChangeNotifier {
  static const _metaEnabledKey = 'pref_meta_enabled';
  static const _wifiOnlyKey = 'pref_wifi_only';
  static const _subtitleDefaultKey = 'pref_subtitle_default';
  static const _dlsiteProxyKey = 'pref_dlsite_proxy';

  bool _metaEnabled = true;
  bool _wifiOnly = false;
  bool _subtitleDefault = false;

  /// DLsite 专用代理（host:port；空 = 不走代理）。
  /// 2026-09-02：规则 VPN 用户 dlsite.com 可能未命中代理规则而直连
  /// 失败——此设置只对 DLsite 元数据请求生效，不影响系统网络。
  String _dlsiteProxy = '';

  bool get metaEnabled => _metaEnabled;
  bool get wifiOnly => _wifiOnly;
  bool get subtitleDefault => _subtitleDefault;
  String get dlsiteProxy => _dlsiteProxy;

  PreferencesProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _metaEnabled = prefs.getBool(_metaEnabledKey) ?? true;
    _wifiOnly = prefs.getBool(_wifiOnlyKey) ?? false;
    _subtitleDefault = prefs.getBool(_subtitleDefaultKey) ?? false;
    _dlsiteProxy = prefs.getString(_dlsiteProxyKey) ?? '';
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

  Future<void> setDlsiteProxy(String v) async {
    final trimmed = v.trim().replaceAll(RegExp(r'^https?://'), '');
    _dlsiteProxy = trimmed;
    notifyListeners();
    (await SharedPreferences.getInstance())
        .setString(_dlsiteProxyKey, trimmed);
  }
}
