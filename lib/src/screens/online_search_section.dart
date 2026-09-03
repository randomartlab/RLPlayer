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

  /// 每个 include 条件一个分页游标（OR 轮转 / AND 主源驱动）。
  late List<_SourceCursor> _sources;
  bool _exhausted = false;

  bool get _isAnd => widget.combine == SearchCombine.and;

  static bool _matchOnline(OnlineWork w, SearchCondition c) {
    final v = c.value.trim().toLowerCase();
    if (v.isEmpty) return false;
    final rj = (w.sourceId ?? '').toLowerCase();
    switch (c.type) {
      case SearchConditionType.rj:
        return rj == c.displayValue.toLowerCase() || rj.contains(v);
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

  /// 拉某源下一页（返回是否还有更多）。keyword/tag→searchWorks(page)；
  /// circle/va → id works(page)；命中后过滤其他条件与 exclude/advanced。
  Future<bool> _fetchMoreSource(_SourceCursor src) async {
    final mirror = context.read<MirrorProvider>();
    final api = mirror.api;
    final next = src.page + 1;
    List<OnlineWork> page;
    try {
      if (src.circleId != null) {
        page = await api.getCircleWorksPage(src.circleId!, next,
            pageSize: 20);
      } else if (src.vaId != null) {
        page = await api.getVaWorks(src.vaId!, page: next, pageSize: 20);
      } else {
        page = await api.searchWorks(src.cond.value,
            page: next, pageSize: 20);
      }
    } catch (_) {
      return false;
    }
    src.page = next;
    src.hasMore = page.length >= 20;

    // AND：主源页需满足其它 include；OR：自身源条件已满足。
    for (final w in page) {
      if (_seen.contains(w.id)) continue;
      var keep = true;
      if (_isAnd) {
        for (final c in widget.includes) {
          if (c != src.cond && !_matchOnline(w, c)) {
            keep = false;
            break;
          }
        }
      } else {
        // OR：其它 include 可命中即可（本页来自 src 已命中 cond）。
        keep = widget.includes.any((c) => _matchOnline(w, c));
      }
      if (!keep) continue;
      if (widget.excludes.any((c) => _matchOnline(w, c))) continue;
      if (!_applyOnlineAdvanced(w, widget.advanced)) continue;
      _seen.add(w.id);
      _pending.add(w);
    }
    return true;
  }

  final Set<int> _seen = {};
  final List<OnlineWork> _pending = [];

  Future<void> _run() async {
    _seen.clear();
    _pending.clear();
    _results = const [];
    _exhausted = false;
    _sources = [];
    final inc = widget.includes;
    for (final c in inc) {
      final src = await _resolveSource(c);
      _sources.add(src);
    }
    if (_sources.isEmpty) return;
    await _loadRound();
  }

  /// 解析 include 条件的源（tag/circle/va 尝试定位 id）。
  Future<_SourceCursor> _resolveSource(SearchCondition c) async {
    final mirror = context.read<MirrorProvider>();
    final api = mirror.api;
    if (c.type == SearchConditionType.circle ||
        c.type == SearchConditionType.va ||
        c.type == SearchConditionType.tag) {
      try {
        final tables = switch (c.type) {
          SearchConditionType.tag => await api.getAllTags(),
          SearchConditionType.circle => await api.getAllCircles(),
          _ => await api.getAllVas(),
        };
        final hit = tables
            .where((m) =>
                ((m['name'] as String?) ?? '').toLowerCase() ==
                c.value.toLowerCase())
            .toList();
        if (hit.isNotEmpty) {
          if (c.type == SearchConditionType.circle) {
            return _SourceCursor(cond: c, circleId: hit.first['id'] as int);
          }
          if (c.type == SearchConditionType.va) {
            return _SourceCursor(cond: c, vaId: hit.first['id'] as String);
          }
          // tag：无专用 tag-works API，回退 search 名字。
        }
      } catch (_) {}
    }
    return _SourceCursor(cond: c);
  }

  /// 加载一轮：AND 只主源取下一页；OR 各源轮转各取一页。
  Future<void> _loadRound() async {
    if (_loading) return;
    setState(() => _loading = true);
    // AND 主源 = 第一个非空（尽量窄）；全 keyword 用第一个。
    if (_isAnd) {
      final src = _sources.first;
      if (src.hasMore) {
        await _fetchMoreSource(src);
      } else {
        _exhausted = true;
      }
    } else {
      for (final src in _sources) {
        if (src.hasMore) await _fetchMoreSource(src);
      }
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _results = [..._results, ..._pending];
      _pending.clear();
      if (_results.isEmpty && _sources.every((s) => !s.hasMore)) {
        _exhausted = true;
      }
    });
  }

  bool get _hasMoreNow =>
      _sources.any((s) => s.hasMore) && !_loading && !_exhausted;

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

    if (_error != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(UiSpacing.large),
              child: Text('加载失败：$_error',
                  style: TextStyle(color: scheme.error))));
    }
    if (_results.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: UiSpacing.medium),
          child: Row(
            children: [
              Expanded(
                child: Text('在线结果 ${_results.length}'
                    '${_loading ? '（加载中…）' : _hasMoreNow ? '（继续下滑加载）' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(UiSpacing.large),
                      child: Text(_exhausted ? '未找到满足条件的在线作品' : '加载中…',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant))))
              : ListView.builder(
                  padding: const EdgeInsets.all(UiSpacing.small),
                  itemCount:
                      _results.length + (_hasMoreNow || _loading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _results.length) {
                      return _LoadMoreFooter(
                        loading: _loading,
                        hasMore: _hasMoreNow,
                        onLoad: () => _loadRound(),
                      );
                    }
                    return _OnlineResultTile(
                        work: _results[index], localRjs: localRjs);
                  },
                ),
        ),
      ],
    );
  }
}

class _SourceCursor {
  _SourceCursor({required this.cond, this.circleId, this.vaId});

  final SearchCondition cond;
  final int? circleId;
  final String? vaId;
  int page = 0;
  bool hasMore = true;
}

/// 组合结果底部加载态。
class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.loading,
    required this.hasMore,
    required this.onLoad,
  });

  final bool loading;
  final bool hasMore;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text('已加载全部',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: onLoad,
          icon: const Icon(Icons.expand_more, size: 18),
          label: const Text('加载更多'),
          style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact),
        ),
      ),
    );
  }
}
