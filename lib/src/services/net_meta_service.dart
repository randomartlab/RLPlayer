import 'dart:io';

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
  Future<NetMeta?> getMeta(String rjCode, {bool forceRefresh = false}) async {
    final database = db;
    if (database == null) return null;
    final numeric = int.tryParse(
        rjCode.replaceFirst(RegExp('^(RJ|BJ|VJ)', caseSensitive: false), ''));
    if (numeric == null) return null;

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
      await _fetchNetworkCover(database, rjCode, numeric);
      return meta;
    } catch (e) {
      debugPrint('[NetMeta] asmr.one 未命中: $rjCode ($e)');
      mirror.reportRequestFailure();
    }

    // 2. DLsite 仅兜底（不可达则静默不显示，无重试，PRD 决策 4）。
    // M4 阶段：asmr.one 未命中即标记 noResult；DLsite 页面解析后续里程碑补齐。
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
}
