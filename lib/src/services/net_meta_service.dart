import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/net_meta.dart';
import '../models/work.dart' show CoverSource;
import 'local_library_database.dart';
import '../providers/mirror_provider.dart';

/// 网络元数据补全服务（M11，PRD §5.11）。
///
/// 级联策略（决策 4）：asmr.one（当前最优镜像）→ 命中即止；
/// 未命中/超时 → DLsite 仅兜底一次 → 不可达则静默不显示（无重试无弹窗）。
/// 串行队列 + 最多 2 并发，避免扫描万级库时请求风暴。
class NetMetaService {
  NetMetaService({required this.mirror, required this.db});

  final MirrorProvider mirror;

  /// 本地库 DB（LibraryProvider 异步初始化；null 时调用直接返回 null）。
  final LocalLibraryDatabase? db;

  /// 并发上限（PRD §5.11）。
  static const int maxConcurrent = 2;

  int _running = 0;

  /// 拉取（带缓存）：详情页打开与扫描后异步触发共用入口。
  /// 仅 Wi-Fi 拉取（PRD §5.11；手动刷新 forceRefresh 不受限）。
  Future<bool> _wifiOnlyAllowed() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('pref_wifi_only') ?? false)) return true;
    final results = await Connectivity().checkConnectivity();
    return results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
  }

  Future<NetMeta?> getMeta(String rjCode, {bool forceRefresh = false}) async {
    final database = db;
    if (database == null) return null;
    final numeric = int.tryParse(
        rjCode.replaceFirst(RegExp('^(RJ|BJ|VJ)', caseSensitive: false), ''));
    if (numeric == null) return null;

    // 仅 Wi-Fi 偏好：非 Wi-Fi 且非强制刷新 → 不拉取（缓存可用）。
    if (!forceRefresh && !await _wifiOnlyAllowed()) return null;

    if (!forceRefresh) {
      final cached = await database.queryNetMeta(rjCode);
      if (cached != null) {
        // 缓存命中也执行显示字段回填 + 封面兜底（历史缓存条目在相应功能
        // 上线前写入，需补齐；PRD §5.11 封面降级链与元数据缓存相互独立）。
        if (!cached.noResult) {
          await _backfillDisplayFields(
            database,
            rjCode,
            vas: cached.netVas,
            title: cached.netTitle,
          );
          await _fetchNetworkCover(database, rjCode, cached.workId ?? numeric);
        }
        // noResult 标记抑制自动重试（手动刷新除外）。
        return cached;
      }
    }

    // 串行队列限流。
    final result = await _enqueue(() => _fetch(rjCode, numeric, forceRefresh));
    return result;
  }

  Future<T> _enqueue<T>(Future<T> Function() task) async {
    while (_running >= maxConcurrent) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _running++;
    try {
      return await task();
    } finally {
      _running--;
    }
  }

  Future<NetMeta?> _fetch(String rjCode, int numeric, bool forceRefresh) async {
    final database = db;
    if (database == null) return null;
    // 1. asmr.one（结构化 API 首选）。
    try {
      final detail = await mirror.api.getWork(numeric);
      mirror.reportRequestSuccess();
      final meta = NetMeta.fromJson(numeric, {
        'title': detail.title,
        'titleTranslation': detail.titleTranslation,
        'circle': {'name': detail.circleName},
        'vas': detail.vas.map((v) => {'name': v}).toList(),
        'tags': detail.tags.map((t) => {'name': t}).toList(),
        'mainCover': null, // 封面走 coverUrl(workId) 组装，不存原值
        'description': detail.description,
        'release': detail.release?.toIso8601String(),
        'averageRating': detail.averageRating,
        'ratingCount': detail.ratingCount,
      });
      await database.upsertNetMeta(meta);
      debugPrint('[NetMeta] asmr.one 命中: $rjCode');
      await _backfillDisplayFields(database, rjCode,
          vas: detail.vas, title: detail.title);
      // 封面降级链第 3 级：本地无封面 → 网络封面下载落盘（断网后仍可用）。
      if (await _wifiOnlyAllowed()) {
        await _fetchNetworkCover(database, rjCode, numeric);
      }
      return meta;
    } catch (e) {
      debugPrint('[NetMeta] asmr.one 未命中: $rjCode ($e)');
      mirror.reportRequestFailure();
    }

    // 2. DLsite 兜底（PRD 决策 4：仅在 asmr.one 未命中时尝试一次；
    //    不可达/未命中则静默，无重试无弹窗）。
    final dlsiteMeta = await _fetchFromDlsite(rjCode, numeric);
    if (dlsiteMeta != null) {
      await database.upsertNetMeta(dlsiteMeta);
      debugPrint('[NetMeta] DLsite 兜底命中: $rjCode');
      // DLsite 元数据也回填显示字段（标题/CV）。
      await _backfillDisplayFields(database, rjCode,
          vas: dlsiteMeta.netVas, title: dlsiteMeta.netTitle);
      return dlsiteMeta;
    }

    // 3. 两源均无 → noResult 标记（不再自动重试；手动刷新除外）。
    final noResult = NetMeta(
      rjCode: rjCode,
      workId: numeric,
      fetchedAt: DateTime.now(),
      noResult: true,
      source: 'none',
    );
    await database.upsertNetMeta(noResult);
    return noResult;
  }

  /// 显示字段回填（用户决策 2026-09-01）：CV 空时由网络补全；
  /// 标题仅当本地标题为纯 RJ 号（无信息量）时用网络标题。
  Future<void> _backfillDisplayFields(
    LocalLibraryDatabase database,
    String rjCode, {
    List<String> vas = const [],
    String? title,
  }) async {
    try {
      final workId = await database.queryWorkIdByRj(rjCode);
      if (workId == null) return;
      final work = await database.queryWork(workId);
      if (work == null) return;

      final netVas = vas;
      final netTitle = title ?? '';
      // 本地标题为纯 RJ 号时才允许网络标题覆盖（本地优先）。
      final titleIsRjOnly = work.title.trim().toLowerCase() == rjCode.toLowerCase();
      await database.updateWorkDisplayFields(
        workId,
        vasNames: work.vasNames.isEmpty && netVas.isNotEmpty ? netVas : null,
        title: titleIsRjOnly && netTitle.isNotEmpty ? netTitle : null,
      );
    } catch (e) {
      debugPrint('[NetMeta] 显示字段回填失败: $e');
    }
  }

  /// DLsite 兜底（产品 AJAX API，结构化 JSON 无需 HTML 解析）。
  /// 单独 Dio 实例（不同域名，10s 超时；不可达静默返回 null）。
  static final Dio _dlsiteDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Mobile Safari/537.36',
      'Accept': 'application/json',
    },
    validateStatus: (status) => status != null && status < 500,
  ));

  Future<NetMeta?> _fetchFromDlsite(String rjCode, int numeric) async {
    try {
      final response = await _dlsiteDio.get(
          'https://www.dlsite.com/maniax/product/info/ajax',
          queryParameters: {'product_id': rjCode});
      final data = response.data;
      if (data is! Map) return null;
      final workJson = (data[rjCode] ?? data['RJ$numeric']) as Map?;
      if (workJson == null) return null;

      final workName = (workJson['work_name'] ?? '') as String;
      if (workName.isEmpty) return null;

      // CV/标签从 dlite 的 genres/authors 结构提取。
      final vas = ((workJson['authors'] ?? const []) as List)
          .whereType<Map>()
          .where((a) => (a['role'] ?? '').toString().contains('声優'))
          .map((a) => (a['name'] ?? '') as String)
          .where((n) => n.isNotEmpty)
          .toList();
      final tags = ((workJson['genres'] ?? const []) as List)
          .whereType<Map>()
          .map((g) => (g['name'] ?? '') as String)
          .where((n) => n.isNotEmpty)
          .toList();

      return NetMeta(
        rjCode: rjCode,
        workId: numeric,
        netTitle: workName,
        netCircle: ((workJson['maker_name'] ?? '') as String),
        netVas: vas,
        netTags: tags,
        netDescription: null,
        netRelease: DateTime.tryParse(
            (workJson['regist_date'] ?? '').toString().split(' ')[0]),
        netRateAverage: (workJson['rate_average_2dp'] as num?)?.toDouble(),
        netRateCount: (workJson['rate_count'] as num?)?.toInt(),
        source: 'dlsite',
        fetchedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[NetMeta] DLsite 兜底不可达（静默）: $e');
      return null;
    }
  }

  /// 网络封面兜底（PRD §5.11）：仅当本地作品封面为占位时下载落盘并回写。
  Future<void> _fetchNetworkCover(
      LocalLibraryDatabase database, String rjCode, int numeric) async {
    try {
      final workId = await database.queryWorkIdByRj(rjCode);
      if (workId == null) return; // 非本地作品（纯在线浏览）不处理。

      final work = await database.queryWork(workId);
      if (work == null) return;
      // 本地有任何可用封面（文件/内嵌）时禁止网络封面请求（PRD 验收）。
      if (work.coverSource != CoverSource.placeholder) return;

      final appDoc = await getApplicationDocumentsDirectory();
      final coversDir = Directory(p.join(appDoc.path, 'covers', 'network'));
      await coversDir.create(recursive: true);
      final file = File(p.join(coversDir.path, '$rjCode.img'));

      if (!await file.exists()) {
        final bytes = await mirror.api.downloadCover(numeric);
        if (bytes == null || bytes.length < 100) return;
        await file.writeAsBytes(bytes);
      }
      await database.updateWorkCover(workId, file.path);
      debugPrint('[NetMeta] 网络封面已落盘: $rjCode');
    } catch (e) {
      // 封面兜底 best-effort：失败不影响元数据。
      debugPrint('[NetMeta] 封面兜底失败: $e');
    }
  }

  /// 缓存清理（设置页入口）。
  Future<void> clearCache() async => db?.clearNetMeta();

  /// 后台批量回填：对本地库缺 NetMeta 的作品逐个拉取。
  ///
  /// 筛选/排序（社团/CV/标签/评分）依赖 NetMeta——仅详情页按需拉取会
  /// 导致大部分作品无数据（实机反馈 2026-09-02：社团/标签筛选空白）。
  /// 串行 + 尊重 Wi-Fi 限制 + 偏好开关；单作品失败不中断。
  Future<void> backfillAll(Iterable<String> rjCodes) async {
    for (final rjCode in rjCodes) {
      // 偏好开关关闭 → 整体退出。
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('pref_meta_enabled') ?? true)) return;
      try {
        await getMeta(rjCode);
      } catch (_) {
        // 单个失败继续下一个。
      }
    }
  }
}
