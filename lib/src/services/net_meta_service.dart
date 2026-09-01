import 'package:flutter/foundation.dart';

import '../models/net_meta.dart';
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

  /// 缓存清理（设置页入口）。
  Future<void> clearCache() async => db?.clearNetMeta();
}
