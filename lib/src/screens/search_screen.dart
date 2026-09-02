import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/work.dart';
import '../models/net_meta.dart';
import '../providers/library_provider.dart';
import '../services/local_library_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/ui_tokens.dart';
import '../widgets/enhanced_work_card.dart';
import 'online_search_section.dart';
import 'work_detail_screen.dart';

/// Tab2 搜索页（M6，PRD §5.7 首版：关键词/RJ 号本地搜索）。
///
/// - 关键词：模糊匹配作品标题 + 音轨名（LIKE，PRD FTS 五条件中的核心两条）；
/// - RJ 号：数字自动补全 RJ 前缀精确匹配；
/// - 搜索完全离线，零网络请求（PRD 验收）；
/// - 搜索历史（SharedPreferences）。
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  String _query = '';
  List<Work> _results = const [];
  bool _searched = false;

  /// 搜索范围：本地 / 全网（2026-09-02 用户需求）。
  bool _onlineMode = false;

  // ---- 实时候选（单字即弹，2026-09-02 用户需求）----
  /// 候选条目：label + 命中类型（跳转对应条件搜索）。
  List<({String label, String type, int conditionType})> _suggestions = const [];
  Timer? _suggestDebounce;

  void _updateSuggestions() {
    final library = context.read<LibraryProvider>();
    final db = library.database;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    final items = <({String label, String type, int conditionType})>[];
    // 聚合本地字段（works + NetMeta——后台回填后元数据齐全）。
    final seen = <String>{};
    for (final work in library.works) {
      for (final vas in work.vasNames) {
        if (vas.toLowerCase().contains(q) && seen.add('V:$vas')) {
          items.add((label: vas, type: 'CV', conditionType: 4));
        }
      }
      if (work.circleName != null &&
          work.circleName!.toLowerCase().contains(q) &&
          seen.add('C:${work.circleName}')) {
        items.add(
            (label: work.circleName!, type: '社团', conditionType: 3));
      }
      for (final tag in work.tags) {
        if (tag.toLowerCase().contains(q) && seen.add('T:$tag')) {
          items.add((label: tag, type: '标签', conditionType: 2));
        }
      }
      if (work.title.toLowerCase().contains(q) && seen.add('W:${work.title}')) {
        items.add((label: work.title, type: '作品', conditionType: 0));
      }
      if (work.rjCode?.toLowerCase().contains(q) == true &&
          seen.add('R:${work.rjCode}')) {
        items.add((label: work.rjCode!, type: 'RJ', conditionType: 1));
      }
    }
    // NetMeta 字段聚合（异步——warmNetMetas 已加载则同步可用）。
    for (final work in library.works) {
      final meta = library.netMetaOf(work);
      if (meta == null) continue;
      for (final vas in meta.netVas) {
        if (vas.toLowerCase().contains(q) && seen.add('V:$vas')) {
          items.add((label: vas, type: 'CV', conditionType: 4));
        }
      }
      if (meta.netCircle != null &&
          meta.netCircle!.toLowerCase().contains(q) &&
          seen.add('C:${meta.netCircle}')) {
        items.add((label: meta.netCircle!, type: '社团', conditionType: 3));
      }
      for (final tag in meta.netTags) {
        if (tag.toLowerCase().contains(q) && seen.add('T:$tag')) {
          items.add((label: tag, type: '标签', conditionType: 2));
        }
      }
    }
    // 排序：短标签优先（更精确），限 12 条。
    items.sort((a, b) => a.label.length.compareTo(b.label.length));
    if (mounted) {
      setState(() => _suggestions = items.take(12).toList());
    }
  }

  /// 搜索条件类型（PRD §5.7：关键词/RJ号/标签/社团/声优）。
  int _conditionType = 0;
  static const _conditions = [
    ('关键词', Icons.text_fields),
    ('RJ 号', Icons.tag),
    ('标签', Icons.label_outline),
    ('社团', Icons.group_outlined),
    ('声优', Icons.mic_outlined),
    // 组合搜索（AND/并集交互组件，2026-09-02 用户需求——替代 $-词$ 指令）。
    ('组合', Icons.manage_search),
  ];

  // ---- 组合搜索状态 ----
  /// 条目：(条件类型索引, 值, 是否排除)。
  final List<(int, String, bool)> _comboConditions = [];
  /// true = 全部满足（AND）；false = 任一满足（OR）。
  bool _comboAnd = true;

  Future<void> _runComboSearch() async {
    if (_comboConditions.isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
      });
      return;
    }
    final library = context.read<LibraryProvider>();
    final db = library.database;
    final result = <Work>[];
    for (final work in library.works) {
      // 每个条件的命中判断。
      Future<bool> match((int, String, bool) cond) async {
        final (type, rawValue, exclude) = cond;
        final value = rawValue.toLowerCase();
        bool hit = switch (type) {
          1 => (work.rjCode?.toLowerCase().contains(value) ?? false),
          2 => work.tags.any((t) => t.toLowerCase().contains(value)),
          3 => (work.circleName?.toLowerCase().contains(value) ?? false),
          4 => work.vasNames.any((v) => v.toLowerCase().contains(value)),
          _ => work.title.toLowerCase().contains(value),
        };
        if (!hit && db != null && work.rjCode != null) {
          final meta = await db.queryNetMeta(work.rjCode!);
          if (meta != null) {
            hit = switch (type) {
              2 => meta.netTags
                  .any((t) => t.toLowerCase().contains(value)),
              3 => (meta.netCircle?.toLowerCase().contains(value) ?? false),
              4 => meta.netVas
                  .any((v) => v.toLowerCase().contains(value)),
              _ => (meta.netTitle?.toLowerCase().contains(value) ?? false),
            };
          }
        }
        // 排除条件：命中即视为不满足。
        return exclude ? !hit : hit;
      }

      final matches =
          await Future.wait(_comboConditions.map(match));
      final ok = _comboAnd
          ? matches.every((m) => m)
          : matches.any((m) => m);
      if (ok) result.add(work);
    }
    if (mounted) {
      setState(() {
        _results = result;
        _searched = true;
      });
    }
  }

  /// 组合条件构建器弹层。
  Future<void> _showComboBuilder() async {
    final library = context.read<LibraryProvider>();
    await library.warmNetMetas();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final scheme = Theme.of(sheetContext).colorScheme;
          // 候选聚合（与实时候选同源）。
          final candidates = <String>{};
          for (final w in library.works) {
            candidates
              ..add(w.title)
              ..addAll(w.vasNames)
              ..addAll(w.tags);
            if (w.circleName != null) candidates.add(w.circleName!);
            final meta = library.netMetaOf(w);
            if (meta != null) {
              candidates
                ..addAll(meta.netVas)
                ..addAll(meta.netTags);
              if (meta.netCircle != null) candidates.add(meta.netCircle!);
            }
          }
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            builder: (_, __) => Padding(
              padding: const EdgeInsets.all(UiSpacing.large),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text('组合搜索',
                          style: Theme.of(sheetContext)
                              .textTheme
                              .titleMedium),
                      const Spacer(),
                      // AND / OR 切换。
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('全部满足')),
                          ButtonSegment(value: false, label: Text('任一满足')),
                        ],
                        selected: {_comboAnd},
                        onSelectionChanged: (v) {
                          setSheetState(() => _comboAnd = v.first);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: UiSpacing.medium),
                  // 已加条件 chips。
                  Wrap(
                    spacing: UiSpacing.small,
                    runSpacing: UiSpacing.xSmall,
                    children: [
                      for (var i = 0; i < _comboConditions.length; i++)
                        InputChip(
                          avatar: Icon(
                            _comboConditions[i].$3
                                ? Icons.block
                                : Icons.check,
                            size: 14,
                            color: _comboConditions[i].$3
                                ? scheme.error
                                : scheme.primary,
                          ),
                          label: Text(
                              '${_conditions[_comboConditions[i].$1].$1}:${_comboConditions[i].$2}'),
                          onDeleted: () {
                            setSheetState(
                                () => _comboConditions.removeAt(i));
                          },
                        ),
                    ],
                  ),
                  const Divider(height: UiSpacing.large),
                  // 快速添加：类型选择 + 候选列表（点选即加条件）。
                  Expanded(
                    child: DefaultTabController(
                      length: 5,
                      child: Column(
                        children: [
                          TabBar(
                            isScrollable: true,
                            tabs: [
                              for (final c in _conditions.take(5))
                                Tab(text: c.$1),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                for (var t = 0; t < 5; t++)
                                  ListView(
                                    children: [
                                      for (final cand in candidates
                                          .where((c) => c.isNotEmpty)
                                          .take(200)
                                          .toList()
                                        ..sort())
                                        ListTile(
                                          dense: true,
                                          title: Text(cand,
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis),
                                          trailing: PopupMenuButton<String>(
                                            onSelected: (mode) {
                                              setSheetState(() =>
                                                  _comboConditions.add((
                                                    t,
                                                    cand,
                                                    mode == 'exclude',
                                                  )));
                                            },
                                            itemBuilder: (_) => const [
                                              PopupMenuItem(
                                                  value: 'include',
                                                  child: Text('添加（满足）')),
                                              PopupMenuItem(
                                                  value: 'exclude',
                                                  child: Text('添加（排除）')),
                                            ],
                                          ),
                                          onTap: () {
                                            setSheetState(() =>
                                                _comboConditions.add(
                                                    (t, cand, false)));
                                          },
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: UiSpacing.medium),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _runComboSearch();
                    },
                    child: const Text('搜索'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 搜索历史（最近 10 条，PRD 验收要求）。
  List<String> _history = const [];
  static const String _historyKey = 'search_history';

  /// 高级筛选（PRD §5.7：有无歌词/字幕、年龄分级）。
  static const _filters = [
    ('有歌词', 1),
    ('有字幕', 2),
    ('全年龄', 3),
    ('R18', 4),
  ];
  final Set<int> _activeFilters = {};

  /// 排除语法 `$-词$`（PRD §5.7）：命中的作品被剔除。
  static final _excludeRegex = RegExp(r'\$-([^$]+)\$');

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _history = prefs.getStringList(_historyKey) ?? []);
    }
  }

  Future<void> _saveHistory(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = [
      query,
      ..._history.where((h) => h != query),
    ].take(10).toList();
    setState(() => _history = updated);
    await prefs.setStringList(_historyKey, updated);
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _history = []);
    await prefs.setStringList(_historyKey, []);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _suggestDebounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _suggestDebounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _query = value.trim());
      _search();
    });
    // 候选即时更新（单字即弹）。
    _suggestDebounce =
        Timer(const Duration(milliseconds: 80), () {
      _query = value.trim();
      _updateSuggestions();
    });
  }

  /// 本地库搜索（作品标题/音轨名 LIKE，RJ 号精确）。
  Future<void> _search() async {
    if (_query.isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
      });
      return;
    }
    final library = context.read<LibraryProvider>();
    final db = library.database;
    final query = _query.toLowerCase();

    // 排除语法：$-词$ 剥离为排除词。
    final excludes = _excludeRegex
        .allMatches(_query)
        .map((m) => m.group(1)!.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
    final keyword = _query
        .replaceAll(_excludeRegex, ' ')
        .trim()
        .toLowerCase();

    final results = <Work>[];
    for (final work in library.works) {
      var hit = false;
      switch (_conditionType) {
        case 1: // RJ 号（纯数字自动补前缀）。
          final rj =
              RegExp(r'^\d{5,8}$').hasMatch(keyword) ? 'rj$keyword' : keyword;
          hit = work.rjCode?.toLowerCase() == rj ||
              work.rjCode?.toLowerCase().contains(keyword) == true;
        case 2: // 标签：works.tags + NetMeta.netTags。
          hit = work.tags.any((t) => t.toLowerCase().contains(keyword));
          hit = hit ||
              await _netMetaMatch(db, work,
                  (m) => m.netTags.any((t) => t.toLowerCase().contains(query)));
        case 3: // 社团。
          hit = work.circleName?.toLowerCase().contains(keyword) ?? false;
          hit = hit ||
              await _netMetaMatch(db, work,
                  (m) => m.netCircle?.toLowerCase().contains(query) ?? false);
        case 4: // 声优。
          hit = work.vasNames
              .any((v) => v.toLowerCase().contains(keyword));
          hit = hit ||
              await _netMetaMatch(db, work,
                  (m) => m.netVas.any((v) => v.toLowerCase().contains(query)));
        default:
          // 关键词全字段（实机需求 2026-09-02：输入 CV/关键词/社团/题目
          // 动态匹配）：标题/社团/CV/标签/RJ 号 + 音轨名 + NetMeta 回填。
          hit = work.title.toLowerCase().contains(keyword) ||
              (work.circleName?.toLowerCase().contains(keyword) ?? false) ||
              (work.rjCode?.toLowerCase().contains(keyword) ?? false) ||
              work.vasNames.any(
                  (v) => v.toLowerCase().contains(keyword)) ||
              work.tags.any((t) => t.toLowerCase().contains(keyword));
          if (!hit && db != null && work.rjCode != null) {
            final meta = await db.queryNetMeta(work.rjCode!);
            if (meta != null) {
              hit = (meta.netTitle?.toLowerCase().contains(keyword) ??
                      false) ||
                  (meta.netCircle?.toLowerCase().contains(keyword) ?? false) ||
                  meta.netVas.any(
                      (v) => v.toLowerCase().contains(keyword)) ||
                  meta.netTags.any(
                      (t) => t.toLowerCase().contains(keyword));
            }
          }
          if (!hit) {
            final nodes = await library.nodesOf(work);
            hit = nodes.any((node) =>
                !node.isDirectory &&
                node.displayName.toLowerCase().contains(keyword));
          }
      }
      // 排除词命中 → 剔除。
      if (hit && excludes.isNotEmpty) {
        final blob = [
          work.title,
          work.circleName ?? '',
          work.rjCode ?? '',
          ...work.vasNames,
          ...work.tags,
        ].join(' ').toLowerCase();
        if (excludes.any((e) => blob.contains(e))) hit = false;
      }
      if (hit) results.add(work);
    }

    // 高级筛选后置（PRD §5.7）。
    var filtered = results;
    for (final f in _activeFilters) {
      filtered = filtered.where((w) {
        switch (f) {
          case 1:
            return w.hasLyric;
          case 2:
            return w.hasSubtitle;
          case 3:
            return w.nsfw != true;
          case 4:
            return w.nsfw == true;
        }
        return true;
      }).toList();
    }
    final results2 = filtered;
    if (mounted) {
      setState(() {
        _results = results2;
        _searched = true;
      });
      _saveHistory(_query);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('搜索', style: UiTextStyles.pageTitle),
      ),
      body: Column(
        children: [
          // 搜索范围 toggle（本地/全网，2026-09-02）。
          Padding(
            padding: const EdgeInsets.fromLTRB(
                UiSpacing.medium, UiSpacing.xSmall, UiSpacing.medium, 0),
            child: Row(
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('本地')),
                    ButtonSegment(value: true, label: Text('全网')),
                  ],
                  selected: {_onlineMode},
                  onSelectionChanged: (v) =>
                      setState(() => _onlineMode = v.first),
                ),
              ],
            ),
          ),
          // 条件类型 chips（PRD §5.7 五条件；全网模式标签/社团/声优
          // 变为全表选择器）。
          Padding(
            padding: const EdgeInsets.fromLTRB(
                UiSpacing.medium, UiSpacing.small, UiSpacing.medium, 0),
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _conditions.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: UiSpacing.small),
                      child: FilterChip(
                        avatar: Icon(_conditions[i].$2, size: 16),
                        label: Text(_conditions[i].$1),
                        selected: _conditionType == i,
                        onSelected: (_) {
                          setState(() => _conditionType = i);
                          if (i == 5) {
                            _showComboBuilder();
                          } else {
                            _search();
                          }
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // 实时候选面板（单字即弹，2026-09-02 用户需求；
          // 本地模式专属——全网模式有自己的选择器）。
          if (!_onlineMode && _suggestions.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              margin:
                  const EdgeInsets.symmetric(horizontal: UiSpacing.medium),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(UiRadii.control),
                border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final sug = _suggestions[index];
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: _suggestionIcon(sug.type),
                    title: Text(sug.label,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text(sug.type,
                        style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant)),
                    onTap: () {
                      // 点候选：切到对应条件类型并搜索。
                      setState(() {
                        _conditionType = sug.conditionType;
                        _query = sug.label;
                        _controller.text = sug.label;
                        _suggestions = const [];
                      });
                      _search();
                    },
                  );
                },
              ),
            ),
          // 高级筛选 chips（PRD §5.7：有无歌词/字幕、年龄分级）。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: UiSpacing.medium),
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final (label, value) in _filters)
                    Padding(
                      padding: const EdgeInsets.only(right: UiSpacing.small),
                      child: FilterChip(
                        label: Text(label),
                        selected: _activeFilters.contains(value),
                        onSelected: (_) {
                          setState(() {
                            _activeFilters.contains(value)
                                ? _activeFilters.remove(value)
                                : _activeFilters.add(value);
                          });
                          _search();
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // 胶囊搜索栏：48dp 高 StadiumBorder（UI 规范 §5.3）。
          Padding(
            padding: const EdgeInsets.fromLTRB(
                UiSpacing.medium, UiSpacing.small, UiSpacing.medium, 0),
            child: SizedBox(
              height: UiControlSize.standard,
              child: SearchBar(
                controller: _controller,
                focusNode: _focusNode,
                hintText: '作品名 / 音轨名 / RJ 号',
                leading: const Icon(Icons.search),
                elevation: const WidgetStatePropertyAll(1),
                onChanged: _onChanged,
                trailing: [
                  if (_query.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        setState(() {
                          _query = '';
                          _results = const [];
                          _searched = false;
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            // 全网模式：在线搜索（标签/社团/声优为全表选择器）。
            child: _onlineMode
                ? OnlineSearchSection(
                    conditionType: _conditionType,
                    query: _query,
                  )
                : _conditionType == 5
                    ? Column(
                        children: [
                          if (_comboConditions.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: UiSpacing.medium,
                                  vertical: UiSpacing.xSmall),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Wrap(
                                      spacing: UiSpacing.xSmall,
                                      runSpacing: UiSpacing.xSmall,
                                      children: [
                                        for (final c in _comboConditions)
                                          Chip(
                                            label: Text(
                                                '${_conditions[c.$1].$1}:${c.$2}',
                                                style:
                                                    const TextStyle(fontSize: 11)),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        _showComboBuilder(),
                                    child: const Text('编辑'),
                                  ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: _results.isNotEmpty
                                ? ListView.builder(
                                    itemCount: _results.length,
                                    itemBuilder: (context, index) =>
                                        EnhancedWorkCard(
                                      work: _results[index],
                                      size: WorkCardSize.list,
                                      onTap: () => _openDetail(
                                          context, _results[index]),
                                    ),
                                  )
                                : Center(
                                    child: Text(
                                      _comboConditions.isEmpty
                                          ? '点「编辑」组合搜索条件'
                                          : '没有满足条件的作品',
                                      style: TextStyle(
                                          color: scheme.onSurfaceVariant),
                                    ),
                                  ),
                          ),
                        ],
                      )
                : _results.isNotEmpty
                    ? ListView.builder(
                        key: const PageStorageKey('search_results'),
                        itemCount: _results.length,
                        itemBuilder: (context, index) => EnhancedWorkCard(
                          work: _results[index],
                          size: WorkCardSize.list,
                          onTap: () => _openDetail(context, _results[index]),
                        ),
                      )
                    : _searched
                        ? Center(
                            child: Text(
                              '没有找到「$_query」相关作品',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          )
                        : Column(
                            children: [
                              _buildHistory(context),
                              Expanded(child: _buildIdle(context)),
                            ],
                          ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionIcon(String type) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (type) {
      'CV' => Icons.mic_outlined,
      '社团' => Icons.group_outlined,
      '标签' => Icons.label_outline,
      'RJ' => Icons.tag,
      _ => Icons.music_note_outlined,
    };
    return Icon(icon, size: 18, color: scheme.primary);
  }

  Widget _buildHistory(BuildContext context) {
    if (_history.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: UiSpacing.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                    child: Text('搜索历史',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500))),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: _clearHistory,
                  tooltip: '清空历史',
                ),
              ],
            ),
            Wrap(
              spacing: UiSpacing.small,
              children: [
                for (final item in _history)
                  ActionChip(
                    label: Text(item),
                    onPressed: () {
                      _controller.text = item;
                      _onChanged(item);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 64, color: scheme.onSurfaceVariant),
          const SizedBox(height: UiSpacing.medium),
          Text(
            '搜索本地作品库',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: UiSpacing.xSmall),
          Text(
            '完全离线 · 五条件 + 筛选 · 排除语法 \$-词\$',
            style: UiTextStyles.supporting
                .copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Future<bool> _netMetaMatch(
      LocalLibraryDatabase? db, Work work, bool Function(NetMeta) test) async {
    if (db == null || work.rjCode == null) return false;
    final meta = await db.queryNetMeta(work.rjCode!);
    return meta != null && !meta.noResult && test(meta);
  }

  void _openDetail(BuildContext context, Work work) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => WorkDetailScreen(work: work),
      ),
    );
  }
}
