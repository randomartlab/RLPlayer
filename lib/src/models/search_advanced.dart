/// 高级筛选（搜索 M3，2026-09-03）：评分下限 / 年龄分级 / 销量下限。
///
/// 应用于搜索结果集（本地 Work + NetMeta 或在线 OnlineWork）。
library;

import '../models/net_meta.dart';
import '../models/work.dart';

enum AgeFilter { all, sfw, r18 }

class SearchAdvanced {
  const SearchAdvanced({
    this.minRating = 0,
    this.age = AgeFilter.all,
    this.minSales = 0,
  });

  final double minRating;
  final AgeFilter age;
  final int minSales;

  bool get isActive =>
      minRating > 0 || age != AgeFilter.all || minSales > 0;
}

/// 本地作品过滤（用 NetMeta 网络元数据评分/销量）。
bool applyLocalAdvanced(Work work, NetMeta? meta, SearchAdvanced adv) {
  if (!adv.isActive) return true;
  if (adv.age == AgeFilter.sfw && work.nsfw == true) return false;
  if (adv.age == AgeFilter.r18 && work.nsfw != true) return false;
  if (adv.minRating > 0) {
    final rating = meta?.netRateAverage ?? 0;
    if (rating < adv.minRating) return false;
  }
  if (adv.minSales > 0) {
    final dl = meta?.netDlCount ?? 0;
    if (dl < adv.minSales) return false;
  }
  return true;
}
