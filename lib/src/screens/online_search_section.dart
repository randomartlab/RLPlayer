/// 搜索页的「全网」模式（2026-09-02 用户需求）：
/// - 条件类型对齐 asmr.one：关键词 / RJ 号 / 标签 / 声优 / 社团；
/// - 标签/声优/社团为「选择器」：拉全表（按作品数排序）供点选（kikoflu 同款）；
/// - 在线结果中本地已有的作品显示「本地」徽章。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/online_models.dart';
import '../models/search_advanced.dart';
import '../models/search_query.dart';
import '../providers/library_provider.dart';
import '../providers/mirror_provider.dart';
import '../utils/ui_tokens.dart';
import 'online_work_detail_screen.dart';
import 'work_detail_screen.dart';

class OnlineSearchSection extends StatefulWidget {
  const OnlineSearchSection({
    super.key,
    required this.conditionType,
    required this.query,
  });

  /// 与本地搜索共享的条件类型（2=标签 3=社团 4=声优）。
  final int conditionType;
  final String query;

  @override
  State<OnlineSearchSection> createState() => _OnlineSearchSectionState();
}

class _OnlineSearchSectionState extends State<OnlineSearchSection> {
  List<OnlineWork> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_isPickerMode) {
      _loadPicker();
    } else if (widget.query.isNotEmpty) {
      _search();
    }
  }

  @override
  void didUpdateWidget(OnlineSearchSection old) {
    super.didUpdateWidget(old);
    if (old.conditionType != widget.conditionType) {
      _results = const [];
      _error = null;
      if (_isPickerMode) {
        _loadPicker();
      } else if (widget.query.isNotEmpty) {
        _search();
      }
    } else if (old.query != widget.query && !_isPickerMode) {
      _search();
    }
  }

  /// 标签/声优/社团 → 选择器模式（全表点选，kikoflu 同款交互）。
  bool get _isPickerMode =>
      widget.conditionType == 2 || widget.conditionType == 3 || widget.conditionType == 4;

  List<Map<String, dynamic>> _pickerItems = const [];
  bool _pickerLoading = false;

  Future<void> _loadPicker() async {
    setState(() => _pickerLoading = true);
    try {
      final mirror = context.read<MirrorProvider>();
      final items = switch (widget.conditionType) {
        2 => await mirror.api.getAllTags(),
        3 => await mirror.api.getAllCircles(),
        _ => await mirror.api.getAllVas(),
      };
      if (!mounted) return;
      setState(() {
        _pickerItems = items;
        _pickerLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _pickerLoading = false;
      });
    }
  }

  Future<void> _search() async {
    if (widget.query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final mirror = context.read<MirrorProvider>();
      final q = widget.query;
      List<OnlineWork> works;
      if (widget.conditionType == 1 &&
          RegExp(r'^\d{5,8}$').hasMatch(q)) {
        // 纯数字 → RJ 号搜索。
        works = await mirror.api.searchWorks('RJ$q', pageSize: 40);
      } else {
        works = await mirror.api.searchWorks(q, pageSize: 40);
      }
      if (!mounted) return;
      setState(() {
        _results = works;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 选择器点选 → 按标签/社团/CV 检索作品。
  Future<void> _pickAndSearch(Map<String, dynamic> item) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final mirror = context.read<MirrorProvider>();
      List<OnlineWork> works;
      switch (widget.conditionType) {
        case 2: // 标签：标签名作关键词。
          works = await mirror.api
              .searchWorks(item['name'] as String, pageSize: 40);
        case 3: // 社团：id 检索。
          works = await mirror.api.getCircleWorksPage(
              item['id'] as int, 1,
              pageSize: 40);
        default: // 声优：id 检索。
          works = await mirror.api.getVaWorks(
              item['id'] as String,
              pageSize: 40);
      }
      if (!mounted) return;
      setState(() {
        _results = works;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final library = context.watch<LibraryProvider>();
    // 本地已有 RJ 集合（徽章判定）。
    final localRjs = library.works
        .map((w) => w.rjCode?.toUpperCase())
        .whereType<String>()
        .toSet();

    if (_pickerLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(UiSpacing.large),
        child: Text('加载失败：$_error', style: TextStyle(color: scheme.error)),
      ));
    }

    // 选择器模式：全部标签/声优/社团列表（输入动态过滤 + 按作品数排序）。
    if (_isPickerMode && _results.isEmpty && !_loading) {
      final q = widget.query.toLowerCase();
      final filtered = q.isEmpty
          ? _pickerItems
          : _pickerItems
              .where((item) =>
                  ((item['name'] as String?) ?? '').toLowerCase().contains(q))
              .toList();
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: UiSpacing.small),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final item = filtered[index];
          final name = item['name'] as String? ?? '';
          final count = item['count'] as int? ?? 0;
          return ListTile(
            dense: true,
            title: Text(name, maxLines: 1),
            trailing: Text('$count',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            onTap: () => _pickAndSearch(item),
          );
        },
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(widget.query.isEmpty ? '输入关键词搜索全网' : '未搜到作品',
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(UiSpacing.small),
      itemCount: _results.length,
      itemBuilder: (context, index) =>
          _OnlineResultTile(work: _results[index], localRjs: localRjs),
    );
  }
}

/// 在线搜索结果行（封面 + 标题 + 元信息 + 本地徽章）。
class _OnlineResultTile extends StatelessWidget {
  const _OnlineResultTile({required this.work, required this.localRjs});

  final OnlineWork work;
  final Set<String> localRjs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mirror = context.read<MirrorProvider>();
    final rjCode = 'RJ${work.id}'.toUpperCase();
    final hasLocal = localRjs.contains(rjCode);

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: UiSpacing.medium),
      leading: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(UiRadii.control),
          child: Image.network(
            mirror.api.coverUrl(work.id),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
                color: scheme.surfaceContainerHighest,
                child: Icon(Icons.album, color: scheme.onSurfaceVariant)),
          ),
        ),
      ),
      title: Row(
        children: [
          if (hasLocal) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('本地',
                  style: TextStyle(
                      fontSize: 10,
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: UiSpacing.xSmall),
          ],
          Expanded(
            child: Text(work.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
      subtitle: Text(
        [
          if (work.circleName != null) work.circleName!,
          if (work.release != null)
            '${work.release!.year}-${work.release!.month.toString().padLeft(2, '0')}',
          if (work.dlCount != null) '${work.dlCount} 销量',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      onTap: () {
        // 本地已有 → 进本地详情；否则在线详情。
        if (hasLocal) {
          final library = context.read<LibraryProvider>();
          final local = library.works
              .firstWhere((w) => w.rjCode?.toUpperCase() == rjCode);
          Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => WorkDetailScreen(work: local)));
        } else {
          Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => OnlineWorkDetailScreen(work: work)));
        }
      },
    );
  }
}


/// 全网组合检索（2026-09-03 M2）：多 include 条件。
///
/// 服务端不支持 OR/组合检索，采用「内存合并」策略：
/// - AND：取首条件候选（各 40/条件）→ 其余 include 在 OnlineWork
///   字段内存过滤 → exclude 过滤
/// - OR：各 include 分别拉取（每 40）→ 并集去重 → exclude 过滤
/// 提示首条件不足时结果可能不全，建议收窄条件。
class OnlineCombineSearch extends StatefulWidget {
  const OnlineCombineSearch({
    super.key,
    required this.includes,
    required this.excludes,
    required this.combine,
    this.advanced = const SearchAdvanced(),
  });

  final List<SearchCondition> includes;
  final List<SearchCondition> excludes;
  final SearchCombine combine;
  final SearchAdvanced advanced;

  @override
  State<OnlineCombineSearch> createState() => _OnlineCombineSearchState();
}

class _OnlineCombineSearchState extends State<OnlineCombineSearch> {
  List<OnlineWork> _results = const [];
  bool _loading = false;
  String? _error;
  String _info = '';

  static bool _applyOnlineAdvanced(OnlineWork w, SearchAdvanced adv) {
    if (!adv.isActive) return true;
    if (adv.age == AgeFilter.sfw && w.nsfw == true) return false;
    if (adv.age == AgeFilter.r18 && w.nsfw != true) return false;
    if (adv.minRating > 0 && (w.averageRating ?? 0) < adv.minRating) {
      return false;
    }
    if (adv.minSales > 0 && (w.dlCount ?? 0) < adv.minSales) return false;
    return true;
  }

  static bool _matchOnline(OnlineWork w, SearchCondition c) {
    final v = c.value.trim().toLowerCase();
    if (v.isEmpty) return false;
    final rj = (w.sourceId ?? '').toLowerCase();
    switch (c.type) {
      case SearchConditionType.rj:
        final target = (c.displayValue).toLowerCase();
        return rj == target || rj.contains(v);
      case SearchConditionType.tag:
        return w.tags.any((t) => t.toLowerCase().contains(v));
      case SearchConditionType.circle:
        return (w.circleName?.toLowerCase().contains(v) ?? false);
      case SearchConditionType.va:
        return w.vas.any((n) => n.toLowerCase().contains(v));
      case SearchConditionType.keyword:
        return w.title.toLowerCase().contains(v) ||
            (w.circleName?.toLowerCase().contains(v) ?? false) ||
            w.vas.any((n) => n.toLowerCase().contains(v)) ||
            w.tags.any((t) => t.toLowerCase().contains(v)) ||
            rj.contains(v);
    }
  }

  Future<List<OnlineWork>> _fetchFor(SearchCondition c) async {
    final mirror = context.read<MirrorProvider>();
    final api = mirror.api;
    // tag/circle/va 优先定位 id（更精准）。
    if (c.type == SearchConditionType.tag ||
        c.type == SearchConditionType.circle ||
        c.type == SearchConditionType.va) {
      final tables = switch (c.type) {
        SearchConditionType.tag => await api.getAllTags(),
        SearchConditionType.circle => await api.getAllCircles(),
        _ => await api.getAllVas(),
      };
      final match = tables
          .where((m) =>
              ((m['name'] as String?) ?? '').toLowerCase() ==
              c.value.toLowerCase())
          .toList();
      if (match.isNotEmpty) {
        return switch (c.type) {
          SearchConditionType.tag =>
            await api.searchWorks(match.first['name'] as String, pageSize: 40),
          SearchConditionType.circle =>
            await api.getCircleWorksPage(match.first['id'] as int, 1,
                pageSize: 40),
          _ => await api
              .getVaWorks(match.first['id'] as String, pageSize: 40),
        };
      }
    }
    // 回退：名字关键词全文检索。
    return api.searchWorks(c.value, pageSize: 40);
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final inc = widget.includes;
      if (inc.isEmpty) {
        setState(() {
          _loading = false;
          _results = const [];
        });
        return;
      }
      final List<OnlineWork> base;
      if (widget.combine == SearchCombine.and) {
        // 主集 = 第一个条件候选，其余内存过滤。
        var pool = await _fetchFor(inc.first);
        for (final c in inc.skip(1)) {
          pool = pool.where((w) => _matchOnline(w, c)).toList();
        }
        base = pool;
      } else {
        // OR：分别拉取 → 并集去重。
        final merged = <int, OnlineWork>{};
        for (final c in inc) {
          for (final w in await _fetchFor(c)) {
            merged[w.id] = w;
          }
        }
        base = merged.values.toList();
      }
      final excludes = widget.excludes;
      final result = base
          .where((w) => !excludes.any((c) => _matchOnline(w, c)))
          .where((w) => _applyOnlineAdvanced(w, widget.advanced))
          .toList();
      if (!mounted) return;
      setState(() {
        _results = result;
        _loading = false;
        _info = '基于条件前 40 条/条件${inc.length > 1 ? "（收窄条件更准）" : ""}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(OnlineCombineSearch old) {
    super.didUpdateWidget(old);
    if (old.combine != widget.combine ||
        old.includes.length != widget.includes.length ||
        old.excludes.length != widget.excludes.length) {
      _run();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final library = context.watch<LibraryProvider>();
    final localRjs = library.works
        .map((w) => w.rjCode?.toUpperCase())
        .whereType<String>()
        .toSet();

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(UiSpacing.large),
              child: Text('加载失败：$_error',
                  style: TextStyle(color: scheme.error))));
    }
    if (_results.isEmpty) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(UiSpacing.large),
              child: Text('未找到满足条件的在线作品',
                  style: TextStyle(color: scheme.onSurfaceVariant))));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: UiSpacing.medium),
          child: Row(
            children: [
              Expanded(
                child: Text(_info,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              ),
              Text('${_results.length}',
                  style: TextStyle(
                      fontSize: 13,
                      color: scheme.primary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(UiSpacing.small),
            itemCount: _results.length,
            itemBuilder: (context, index) => _OnlineResultTile(
                work: _results[index], localRjs: localRjs),
          ),
        ),
      ],
    );
  }
}
