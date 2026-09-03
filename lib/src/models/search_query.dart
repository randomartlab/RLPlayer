/// 统一搜索条件对象模型（2026-09-03 迭代 M1）。
///
/// 对齐 kikoflu 思路：搜索 = 条件对象集合；本次扩展支持
/// include 条件组以 AND/OR 组合 + exclude 条件作为后置硬过滤。
library;

import '../models/net_meta.dart';
import '../models/work.dart';

enum SearchConditionType { keyword, rj, tag, circle, va }

enum SearchCombine { and, or }

class SearchCondition {
  const SearchCondition({
    required this.type,
    required this.value,
    this.exclude = false,
  });

  final SearchConditionType type;
  final String value;
  final bool exclude;

  String get displayValue => type == SearchConditionType.rj && !value.startsWith('RJ')
      ? 'RJ$value'
      : value;

  SearchCondition copyWith({SearchConditionType? type, String? value, bool? exclude}) =>
      SearchCondition(
          type: type ?? this.type,
          value: value ?? this.value,
          exclude: exclude ?? this.exclude);
}

/// 条件组：include 按 [combine] 组合；exclude 单独取出做后置过滤。
class SearchQuery {
  SearchQuery({
    List<SearchCondition> conditions = const [],
    this.combine = SearchCombine.and,
  }) : conditions = List.unmodifiable(conditions);

  final List<SearchCondition> conditions;
  final SearchCombine combine;

  bool get isEmpty => conditions.isEmpty;

  List<SearchCondition> get includes =>
      conditions.where((c) => !c.exclude).toList();

  List<SearchCondition> get excludes =>
      conditions.where((c) => c.exclude).toList();

  bool matches(Work work, {NetMeta? meta}) {
    if (isEmpty) return true;
    final inc = includes;
    if (inc.isNotEmpty) {
      final results = inc.map((c) => _matchOne(work, meta, c));
      final ok = switch (combine) {
        SearchCombine.and => results.every((m) => m),
        SearchCombine.or => results.any((m) => m),
      };
      if (!ok) return false;
    }
    // 后置硬过滤：任一排除条件命中即剔除。
    for (final ex in excludes) {
      if (_matchOne(work, meta, ex)) return false;
    }
    return true;
  }

  bool _matchOne(Work work, NetMeta? meta, SearchCondition c) {
    final v = c.value.trim().toLowerCase();
    if (v.isEmpty) return false;
    switch (c.type) {
      case SearchConditionType.rj:
        final target = c.displayValue.toUpperCase();
        return (work.rjCode?.toUpperCase() == target) ||
            (work.rjCode?.toUpperCase().contains(v.toUpperCase()) ?? false);
      case SearchConditionType.tag:
        return work.tags.any((t) => t.toLowerCase().contains(v)) ||
            (meta?.netTags.any((t) => t.toLowerCase().contains(v)) ?? false);
      case SearchConditionType.circle:
        return (work.circleName?.toLowerCase().contains(v) ?? false) ||
            (meta?.netCircle?.toLowerCase().contains(v) ?? false);
      case SearchConditionType.va:
        return work.vasNames.any((n) => n.toLowerCase().contains(v)) ||
            (meta?.netVas.any((n) => n.toLowerCase().contains(v)) ?? false);
      case SearchConditionType.keyword:
        final hitTitle = work.title.toLowerCase().contains(v) ||
            (work.circleName?.toLowerCase().contains(v) ?? false) ||
            (work.rjCode?.toLowerCase().contains(v) ?? false) ||
            work.vasNames.any((n) => n.toLowerCase().contains(v)) ||
            work.tags.any((t) => t.toLowerCase().contains(v)) ||
            (meta?.netTitle?.toLowerCase().contains(v) ?? false) ||
            (meta?.netCircle?.toLowerCase().contains(v) ?? false) ||
            (meta?.netVas.any((n) => n.toLowerCase().contains(v)) ?? false) ||
            (meta?.netTags.any((t) => t.toLowerCase().contains(v)) ?? false);
        return hitTitle;
    }
  }
}
