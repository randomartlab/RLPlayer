/// 网络参考元数据（PRD §6.1 NetMeta 缓存表）。
///
/// 与 Work 本地字段完全隔离：只写入 NetMeta 缓存，永不写回 Work；
/// 可整体清空再生，不影响本地识别数据（PRD §5.11 数据边界）。
class NetMeta {
  const NetMeta({
    required this.rjCode,
    this.netTitle,
    this.netTitleTrans,
    this.netCircle,
    this.netVas = const [],
    this.netTags = const [],
    this.netCoverUrl,
    this.netDescription,
    this.netRelease,
    this.netRateAverage,
    this.netRateCount,
    this.netDlCount,
    this.netReviewCount,
    this.source = 'asmr_one',
    required this.fetchedAt,
    this.noResult = false,
    this.workId,
  });

  final String rjCode;

  /// 服务端作品 id（RJ 号数字部分）。
  final int? workId;
  final String? netTitle;
  final String? netTitleTrans;
  final String? netCircle;
  final List<String> netVas;
  final List<String> netTags;
  final String? netCoverUrl;
  final String? netDescription;
  final DateTime? netRelease;
  final double? netRateAverage;
  final int? netRateCount;

  /// 销量（dl_count）与评论数（review_count），本地排序用（2026-09-02）。
  final int? netDlCount;
  final int? netReviewCount;

  /// asmr_one | dlsite（PRD 决策 4：DLsite 仅兜底）。
  final String source;
  final DateTime fetchedAt;

  /// 两源均失败标记；true 时不再自动重试（手动刷新除外）。
  final bool noResult;

  factory NetMeta.fromJson(int workId, Map<String, dynamic> json) {
    return NetMeta(
      rjCode: 'RJ${workId.toString().padLeft(6, '0')}',
      workId: workId,
      netTitle: json['title'] as String?,
      netTitleTrans: json['titleTranslation'] as String?,
      netCircle:
          (json['circle'] as Map<String, dynamic>?)?['name'] as String?,
      netVas: ((json['vas'] as List?) ?? const [])
          .map((va) => ((va as Map)['name'] ?? '') as String)
          .where((name) => name.isNotEmpty)
          .toList(),
      netTags: ((json['tags'] as List?) ?? const [])
          .map((tag) => ((tag as Map)['name'] ?? '') as String)
          .where((name) => name.isNotEmpty)
          .toList(),
      netCoverUrl: json['mainCover'] as String?,
      netDescription: json['description'] as String?,
      netRelease: DateTime.tryParse((json['release'] ?? '') as String),
      // asmr.one 实际返回 snake_case（2026-09-02 实测）。
      netRateAverage: ((json['rate_average_2dp'] ?? json['averageRating'])
              as num?)
          ?.toDouble(),
      netRateCount:
          ((json['rate_count'] ?? json['ratingCount']) as num?)?.toInt(),
      netDlCount: (json['dl_count'] ?? json['dlCount']) as int?,
      netReviewCount:
          ((json['review_count'] ?? json['reviewCount']) as num?)?.toInt(),
      fetchedAt: DateTime.now(),
    );
  }

  /// 缓存有效期外的自动重拉判断（PRD：无 TTL；这里只按 noResult 抑制）。
  bool get shouldRetry => !noResult;
}
