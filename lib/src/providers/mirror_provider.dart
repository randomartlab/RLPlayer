import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/online_models.dart';
import '../services/kikoeru_api_service.dart';

/// 镜像实例（PRD 决策 1：多镜像 + 自动测速选优）。
class MirrorInstance {
  const MirrorInstance({
    required this.host,
    required this.label,
    this.enabled = true,
    this.latencyMs,
  });

  /// 域名或完整 URL。
  final String host;
  final String label;
  final bool enabled;

  /// 最近一次测速延迟；null = 未测/不可达。
  final int? latencyMs;

  MirrorInstance copyWith({bool? enabled, int? latencyMs, bool clearLatency = false}) {
    return MirrorInstance(
      host: host,
      label: label,
      enabled: enabled ?? this.enabled,
      latencyMs: clearLatency ? null : (latencyMs ?? this.latencyMs),
    );
  }
}

/// 镜像管理与选优提供者（PRD §5.12 / 决策 1）。
///
/// - 内置 asmr.one 默认实例 + 用户自定义镜像；
/// - 自动测速选优（可关闭 → 手动固定）；
/// - 当前镜像连续失败 ≥3 次自动触发重测切换；
/// - Token 按实例独立加密存储（flutter_secure_storage / Android Keystore）。
class MirrorProvider extends ChangeNotifier {
  static const String _mirrorsKey = 'mirror_instances';
  static const String _autoSelectKey = 'mirror_auto_select';
  static const String _pinnedHostKey = 'mirror_pinned_host';
  static const String _activeHostKey = 'mirror_active_host';
  static const String _userKeyPrefix = 'mirror_user_';

  /// 内置默认实例（PRD：asmr.one）。
  static const String defaultHost = 'api.asmr.one';

  /// 内置镜像全集（用户需求 2026-09-01：预置 asmr-100/200/300）。
  static const List<MirrorInstance> builtinMirrors = [
    MirrorInstance(host: 'api.asmr.one', label: 'asmr.one（官方）'),
    MirrorInstance(host: 'api.asmr-100.com', label: 'asmr-100 镜像'),
    MirrorInstance(host: 'api.asmr-200.com', label: 'asmr-200 镜像'),
    MirrorInstance(host: 'api.asmr-300.com', label: 'asmr-300 镜像'),
  ];

  /// v1.0.x 遗留的虚构镜像域名（NXDOMAIN，测速/登录全挂）。
  /// 实机反馈 2026-09-02：预置列表曾写 asmr-100.one 等不存在域名。
  static const Map<String, String> _legacyHostFix = {
    'asmr-100.one': 'api.asmr-100.com',
    'asmr-200.one': 'api.asmr-200.com',
    'asmr-300.one': 'api.asmr-300.com',
  };

  final KikoeruApiService api = KikoeruApiService();

  List<MirrorInstance> _mirrors = [];
  bool _autoSelect = true;
  String? _pinnedHost;

  /// 当前生效镜像 host（自动模式下 = 延迟最低的可用实例）。
  String _activeHost = defaultHost;

  /// 各实例登录状态（host → 用户）；Token 在 secure storage。
  final Map<String, OnlineUser> _users = {};

  /// 连续失败计数（触发自动重测切换，PRD 决策 1）。
  int _consecutiveFailures = 0;

  bool _initializing = true;

  List<MirrorInstance> get mirrors => List.unmodifiable(_mirrors);
  bool get autoSelect => _autoSelect;
  String? get pinnedHost => _pinnedHost;
  String get activeHost => _activeHost;
  bool get initializing => _initializing;

  MirrorInstance? get activeMirror => _mirrors
      .where((m) => m.host == _activeHost)
      .cast<MirrorInstance?>()
      .firstOrNull;

  OnlineUser? get currentUser =>
      _users[_activeHost] ?? _users[defaultHost];

  /// 任一镜像有登录会话（评论等需要登录的功能判断，2026-09-02）。
  bool get hasAnyLogin =>
      _defaultToken != null ||
      _customTokens.values.any((t) => t.isNotEmpty);

  MirrorProvider() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getStringList(_mirrorsKey) ?? [];
    _mirrors = encoded
        .map((json) {
          try {
            final map = jsonDecode(json) as Map<String, dynamic>;
            var host = map['host'] as String;
            // 历史坏域名迁移 → 官方真实镜像。
            host = _legacyHostFix[host] ?? host;
            return MirrorInstance(
              host: host,
              label: map['label'] as String,
              enabled: map['enabled'] != false,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<MirrorInstance>()
        .toList();
    // 去重（迁移后可能与内置镜像重复）。
    final seen = <String>{};
    _mirrors = _mirrors
        .where((m) => seen.add(m.host))
        .toList();
    if (_mirrors.isEmpty) {
      _mirrors = builtinMirrors;
    } else {
      // 旧数据补齐内置镜像（去重）。
      for (final builtin in builtinMirrors) {
        if (!_mirrors.any((m) => m.host == builtin.host)) {
          _mirrors.add(builtin);
        }
      }
    }

    _autoSelect = prefs.getBool(_autoSelectKey) ?? true;
    _pinnedHost = prefs.getString(_pinnedHostKey);
    if (_pinnedHost != null) {
      _pinnedHost = _legacyHostFix[_pinnedHost] ?? _pinnedHost;
    }
    _activeHost = prefs.getString(_activeHostKey) ?? _pinnedHost ?? defaultHost;
    _activeHost = _legacyHostFix[_activeHost] ?? _activeHost;
    if (!_mirrors.any((m) => m.host == _activeHost)) {
      _activeHost = defaultHost;
    }
    _initializing = false;
    notifyListeners();

    // 恢复各实例登录态（Token 加密存储）。
    await _restoreSessions();

    // 冷启动后台自动测速选优（PRD 决策 1）。
    if (_autoSelect) {
      unawaited(speedTest());
    } else {
      _applyActiveMirror();
    }
  }

  Future<void> _restoreSessions() async {
    const storage = FlutterSecureStorage();
    for (final mirror in _mirrors) {
      try {
        final token = await storage.read(key: _tokenKey(mirror.host));
        if (token != null && token.isNotEmpty) {
          // 写回内存（关键：_applyActiveMirror 依赖 _defaultToken/
          // _customTokens，此前恢复只填 _users → 启动后/切镜像即掉登录）。
          if (mirror.host == defaultHost) {
            _defaultToken = token;
          } else {
            _customTokens[mirror.host] = token;
          }
          // 验证 token 有效性（拉一次用户名）；失败则清除。
          api.switchHost(mirror.host, token);
          await api.getFavorites(page: 1);
          // 无异常即 token 有效；用户名从收藏接口不可得，存本地。
          final prefs = await SharedPreferences.getInstance();
          final name = prefs.getString(_userKeyPrefix + mirror.host) ?? '';
          if (name.isNotEmpty) {
            _users[mirror.host] = OnlineUser(id: 0, name: name);
          }
          debugPrint('[Mirror] 恢复登录: ${mirror.host}');
        }
      } catch (e) {
        // 仅 401/403（凭证无效）清除；网络抖动等保留 token，
        // 否则冷启动网络不佳会误删登录（实机反馈 2026-09-03 登录态掉）。
        final status = e is DioException ? e.response?.statusCode : null;
        final invalid = status == 401 || status == 403;
        if (invalid) {
          if (mirror.host == defaultHost) {
            _defaultToken = null;
          } else {
            _customTokens.remove(mirror.host);
          }
          unawaited(storage.delete(key: _tokenKey(mirror.host)));
          debugPrint('[Mirror] 登录失效清除: ${mirror.host}');
        } else {
          debugPrint('[Mirror] 恢复校验暂不可达（保留登录）: ${mirror.host}');
        }
      }
    }
    _applyActiveMirror();
    notifyListeners();
  }

  static String _tokenKey(String host) => 'kikoeru_token_$host';

  // ---- 镜像管理 ----

  Future<bool> addMirror(String host, {String? label}) async {
    final normalized = host.trim();
    if (normalized.isEmpty) return false;
    if (_mirrors.any((m) => m.host == normalized)) return false;
    _mirrors.add(MirrorInstance(
      host: normalized,
      label: label?.isNotEmpty == true ? label! : normalized,
    ));
    await _persistMirrors();
    notifyListeners();
    return true;
  }

  Future<void> removeMirror(String host) async {
    if (host == defaultHost) return; // 默认实例不可删。
    _mirrors.removeWhere((m) => m.host == host);
    if (_pinnedHost == host) _pinnedHost = null;
    if (_activeHost == host) {
      _activeHost = defaultHost;
      _applyActiveMirror();
    }
    await _persistMirrors();
    notifyListeners();
  }

  Future<void> setMirrorEnabled(String host, bool enabled) async {
    _mirrors = _mirrors
        .map((m) => m.host == host ? m.copyWith(enabled: enabled) : m)
        .toList();
    await _persistMirrors();
    notifyListeners();
  }

  Future<void> _persistMirrors() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_mirrorsKey, _mirrors
        .map((m) => jsonEncode(
            {'host': m.host, 'label': m.label, 'enabled': m.enabled}))
        .toList());
  }

  // ---- 测速选优（PRD 决策 1 / 验收 #18） ----

  /// 并发测速全部启用镜像，自动切换到延迟最低的可用实例。
  /// 返回按延迟排序的结果（手动测速入口展示用）。
  Future<List<MirrorInstance>> speedTest() async {
    final enabled = _mirrors.where((m) => m.enabled).toList();
    final results = await Future.wait(enabled.map((m) async {
      final latency = await KikoeruApiService.healthCheck(m.host);
      return m.copyWith(latencyMs: latency, clearLatency: latency == null);
    }));

    _mirrors = _mirrors.map((m) {
      final tested = results.where((r) => r.host == m.host).firstOrNull;
      return tested ?? m;
    }).toList();
    notifyListeners();

    // 选优：延迟最低的可达实例。
    final reachable =
        results.where((m) => m.latencyMs != null).toList()
          ..sort((a, b) => a.latencyMs!.compareTo(b.latencyMs!));

    if (reachable.isNotEmpty) {
      final best = reachable.first;
      if (_autoSelect && best.host != _activeHost) {
        debugPrint('[Mirror] 自动切换到最优镜像: ${best.host} (${best.latencyMs}ms)');
        _activeHost = best.host;
        _consecutiveFailures = 0;
        _applyActiveMirror();
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeHostKey, _activeHost);
    notifyListeners();
    return results..sort((a, b) => (a.latencyMs ?? 99999).compareTo(b.latencyMs ?? 99999));
  }

  /// 手动固定镜像（关闭自动选优），或传 null 恢复自动。
  Future<void> pinMirror(String? host) async {
    final prefs = await SharedPreferences.getInstance();
    if (host == null) {
      _autoSelect = true;
      _pinnedHost = null;
      await prefs.setBool(_autoSelectKey, true);
      await prefs.remove(_pinnedHostKey);
      unawaited(speedTest());
    } else {
      _autoSelect = false;
      _pinnedHost = host;
      _activeHost = host;
      await prefs.setBool(_autoSelectKey, false);
      await prefs.setString(_pinnedHostKey, host);
      await prefs.setString(_activeHostKey, host);
      _applyActiveMirror();
    }
    notifyListeners();
  }

  void _applyActiveMirror() {
    final token = _activeToken;
    api.switchHost(_activeHost, token);
  }

  String? get _activeToken => _activeHost == defaultHost
      ? _defaultToken
      : _customTokens[_activeHost];

  // Token 缓存（启动时从 secure storage 恢复；写穿）。
  final Map<String, String> _customTokens = {};
  String? _defaultToken;

  // ---- 登录 / 登出（Token 加密存储，PRD 决策 2） ----

  /// 在任一已登录镜像上执行需登录的请求（收藏等，2026-09-03）。
  /// 返回任务结果；无登录会话返回 null。
  Future<T?> withLoginHost<T>(
      Future<T> Function(KikoeruApiService api) task) async {
    String? target;
    if (_defaultToken != null && _defaultToken!.isNotEmpty) {
      target = defaultHost;
    } else {
      for (final e in _customTokens.entries) {
        if (e.value.isNotEmpty) {
          target = e.key;
          break;
        }
      }
    }
    if (target == null) return null;
    final prev = api.host;
    try {
      api.switchHost(target,
          target == defaultHost ? _defaultToken : _customTokens[target]);
      return await task(api);
    } finally {
      api.switchHost(prev);
    }
  }

  /// 登录态标记/评分写入（/api/review）。返回是否成功（未登录返回 false）。
  Future<bool> saveReviewProgress(
    int workId, {
    String? progress,
    int? rating,
    String? reviewText,
  }) async {
    final ok = await withLoginHost((api) async {
      await api.saveReviewProgress(
        workId,
        progress: progress,
        rating: rating,
        reviewText: reviewText,
      );
      return true;
    });
    return ok ?? false;
  }

  /// 登录态移除标记。返回是否成功。
  Future<bool> deleteReview(int workId) async {
    final ok = await withLoginHost((api) async {
      await api.deleteReview(workId);
      return true;
    });
    return ok ?? false;
  }

  /// 拉取当前用户全部标记（分页合并）；未登录返回空表。
  Future<List<Map<String, dynamic>>> fetchMyReviewsAll({
    int pageSize = 50,
    String? filter,
  }) async {
    final list = await withLoginHost((api) async {
      final out = <Map<String, dynamic>>[];
      var page = 1;
      while (page <= 50) {
        final items = await api.fetchMyReviews(
            page: page, pageSize: pageSize, filter: filter);
        if (items.isEmpty) break;
        out.addAll(items);
        if (items.length < pageSize) break;
        page++;
      }
      return out;
    });
    return list ?? const [];
  }

  Future<List<Map<String, dynamic>>> fetchAccountPlaylists() async {
    return await withLoginHost((api) => api.getAccountPlaylists()) ??
        const [];
  }

  Future<bool> createAccountPlaylist(String name) async {
    final ok = await withLoginHost((api) async {
      await api.createPlaylist(name);
      return true;
    });
    return ok ?? false;
  }

  Future<bool> addWorkToAccountPlaylist(
      String playlistId, String workId) async {
    final ok = await withLoginHost((api) async {
      await api.addWorksToPlaylist(playlistId, [workId]);
      return true;
    });
    return ok ?? false;
  }

  Future<List<Map<String, dynamic>>> fetchPlaylistWorks(String id) async {
    return await withLoginHost((api) => api.getPlaylistWorks(id)) ??
        const [];
  }

  /// 作品评论拉取：优先走「当前镜像已登录」的会话；若当前镜像未登录
  /// 但其他镜像登录过（自动测速切换场景），临时用登录过的镜像请求并
  /// 恢复（实机反馈 2026-09-02：one 登录后激活镜像切走 → 评论 404）。
  Future<List<Map<String, dynamic>>?> fetchWorkReviews(int workId,
      {int page = 1, int pageSize = 20}) async {
    // 找已登录的镜像（当前激活优先，其次默认，最后任意）。
    String? target;
    // 只要有任何 token 即视为已登录宿主。
    if (_defaultToken != null) target = defaultHost;
    if (target == null) {
      for (final e in _customTokens.entries) {
        if (e.value.isNotEmpty) {
          target = e.key;
          break;
        }
      }
    }
    if (target == null) return null; // 游客。

    final prevHost = api.host;
    try {
      final token = target == defaultHost
          ? _defaultToken
          : _customTokens[target];
      api.switchHost(target, token);
      return await api.getWorkReviews(workId,
          page: page, pageSize: pageSize);
    } finally {
      // 恢复原 host（token 由 host 记忆）。
      api.switchHost(prevHost);
    }
  }

  Future<OnlineUser> login(String name, String password) async {
    api.switchHost(_activeHost);
    final user = await api.login(name, password);
    _users[_activeHost] = user;

    const storage = FlutterSecureStorage();
    await storage.write(key: _tokenKey(_activeHost), value: api.token ?? '');
    if (_activeHost == defaultHost) {
      _defaultToken = api.token;
    } else {
      _customTokens[_activeHost] = api.token ?? '';
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKeyPrefix + _activeHost, user.name);
    notifyListeners();
    return user;
  }

  Future<void> logout() async {
    final host = _activeHost;
    _users.remove(host);
    api.logout();
    const storage = FlutterSecureStorage();
    await storage.delete(key: _tokenKey(host));
    if (host == defaultHost) {
      _defaultToken = null;
    } else {
      _customTokens.remove(host);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKeyPrefix + host);
    notifyListeners();
  }

  // ---- 失败自动切换（连续失败 ≥3 次，PRD 决策 1） ----

  void reportRequestFailure() {
    _consecutiveFailures++;
    debugPrint('[Mirror] 请求失败 ($_consecutiveFailures/3): $_activeHost');
    if (_autoSelect && _consecutiveFailures >= 3) {
      _consecutiveFailures = 0;
      unawaited(speedTest());
    }
  }

  void reportRequestSuccess() => _consecutiveFailures = 0;
}
