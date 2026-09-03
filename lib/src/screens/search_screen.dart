/// Tab2 搜索页（2026-09-03 迭代：统一条件对象模型）。
///
/// - 本地：条件 chips（类型+值+排除可切换），组合 AND/OR + 排除
///   后置硬过滤，完整命中本地库（含 NetMeta 回填字段）
/// - 全网：条件对象为源；单 include 条件转发给选择器/搜索组件
///   （多 include 的全网组合后续里程碑）
/// - 保留历史（条件序列化）、单字候选建议
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/net_meta.dart';
import '../models/search_query.dart';
import '../models/work.dart';
import '../providers/library_provider.dart';
import '../utils/ui_tokens.dart';
import '../widgets/enhanced_work_card.dart';
import 'online_search_section.dart';
import 'work_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  bool _onlineMode = false;
  SearchCombine _combine = SearchCombine.and;
  final List<SearchCondition> _conditions = [];
  int _editingIndex = -1;

  List<Work> _results = const [];
  bool _searched = false;

  List<String> _history = const [];
  static const _historyKey = 'search_history_v2';

  static const _typeLabels = <SearchConditionType, String>{
    SearchConditionType.keyword: '关键词',
    SearchConditionType.rj: 'RJ 号',
    SearchConditionType.tag: '标签',
    SearchConditionType.circle: '社团',
    SearchConditionType.va: '声优',
  };

  static const _typeIcons = <SearchConditionType, IconData>{
    SearchConditionType.keyword: Icons.text_fields,
    SearchConditionType.rj: Icons.tag,
    SearchConditionType.tag: Icons.label_outline,
    SearchConditionType.circle: Icons.group_outlined,
    SearchConditionType.va: Icons.mic_outlined,
  };

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---- 历史 ----

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _history = prefs.getStringList(_historyKey) ?? []);
    }
  }

  Future<void> _saveHistory() async {
    if (_conditions.isEmpty) return;
    final serialized = _serializeConditions();
    final prefs = await SharedPreferences.getInstance();
    final updated = [serialized, ..._history.where((h) => h != serialized)]
        .take(10)
        .toList();
    if (mounted) setState(() => _history = updated);
    await prefs.setStringList(_historyKey, updated);
  }

  String _serializeConditions() {
    final buf = StringBuffer();
    for (final c in _conditions) {
      if (buf.isNotEmpty) buf.write(' && ');
      if (c.exclude) buf.write('排除 ');
      buf.write('${_typeLabels[c.type]}:${c.displayValue}');
    }
    return buf.toString();
  }

  // ---- 条件操作 ----

  void _addCondition(SearchCondition c) {
    setState(() => _conditions.add(c));
    _controller.clear();
    _run();
  }

  void _removeCondition(int index) {
    setState(() => _conditions.removeAt(index));
    _run();
  }

  void _toggleExclude(int index) {
    final c = _conditions[index];
    setState(() => _conditions[index] = c.copyWith(exclude: !c.exclude));
    _run();
  }

  void _editCondition(int index) {
    _editingIndex = index;
    _openAddSheet(initial: _conditions[index]);
  }

  // ---- 执行 ----

  Future<void> _run() async {
    if (_onlineMode) {
      // 全网：交给 OnlineSearchSection（用第一个 include 条件检索）。
      setState(() {});
      return;
    }
    final library = context.read<LibraryProvider>();
    final db = library.database;
    final query = SearchQuery(conditions: _conditions, combine: _combine);
    final result = <Work>[];
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
      });
      return;
    }
    for (final work in library.works) {
      NetMeta? meta;
      if (db != null && work.rjCode != null) {
        meta = library.netMetaOf(work) ?? await db.queryNetMeta(work.rjCode!);
      }
      if (query.matches(work, meta: meta)) result.add(work);
    }
    if (!mounted) return;
    setState(() {
      _results = result;
      _searched = true;
    });
    _saveHistory();
  }

  void _clearConditions() {
    setState(() {
      _conditions.clear();
      _results = const [];
      _searched = false;
      _controller.clear();
    });
  }

  // ---- 添加条件弹层 ----

  Future<void> _openAddSheet({SearchCondition? initial}) async {
    final library = context.read<LibraryProvider>();
    await library.warmNetMetas();
    if (!mounted) return;
    var type = initial?.type ?? SearchConditionType.keyword;
    final controller =
        TextEditingController(text: initial != null ? initial.displayValue : '');
    var exclude = initial?.exclude ?? false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return StatefulBuilder(
          builder: (sheetContext, setSheet) {
            // 候选（按类型聚合本地字段）。
            List<String> candidatesFor() {
              final s = <String>{};
              for (final w in library.works) {
                final meta = library.netMetaOf(w);
                switch (type) {
                  case SearchConditionType.tag:
                    s.addAll(w.tags);
                    s.addAll(meta?.netTags ?? const []);
                  case SearchConditionType.circle:
                    if (w.circleName != null) s.add(w.circleName!);
                    if (meta?.netCircle != null) s.add(meta!.netCircle!);
                  case SearchConditionType.va:
                    s.addAll(w.vasNames);
                    s.addAll(meta?.netVas ?? const []);
                  default:
                    s.add(w.title);
                    if (w.rjCode != null) s.add(w.rjCode!);
                }
              }
              final list = s.where((e) => e.isNotEmpty).toList()..sort();
              final q = controller.text.trim().toLowerCase();
              return q.isEmpty
                  ? list.take(200).toList()
                  : list.where((e) => e.toLowerCase().contains(q)).take(50).toList();
            }

            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(UiSpacing.large),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(initial == null ? '添加条件' : '编辑条件',
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .titleMedium),
                          const Spacer(),
                          if (initial != null)
                            TextButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                child: const Text('取消')),
                        ],
                      ),
                      // 类型 chips
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final t in SearchConditionType.values)
                            ChoiceChip(
                              label: Text(_typeLabels[t]!,
                                  style: const TextStyle(fontSize: 12)),
                              selected: type == t,
                              visualDensity: VisualDensity.compact,
                              onSelected: (_) => setSheet(() => type = t),
                            ),
                        ],
                      ),
                      const SizedBox(height: UiSpacing.medium),
                      // 值输入
                      TextField(
                        controller: controller,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: type == SearchConditionType.rj
                              ? '输入数字自动补 RJ（如 416816）'
                              : _typeLabels[type],
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setSheet(() {}),
                      ),
                      // 候选快捷点选
                      if (type != SearchConditionType.keyword &&
                          type != SearchConditionType.rj) ...[
                        const SizedBox(height: 6),
                        Text('候选（点选即填入）',
                            style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant)),
                        SizedBox(
                          height: 130,
                          child: ListView(
                            children: [
                              for (final cand in candidatesFor())
                                ListTile(
                                  dense: true,
                                  title: Text(cand,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  onTap: () {
                                    controller.text = cand;
                                    setSheet(() {});
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
                      // 排除开关 + 确定
                      Row(
                        children: [
                          const Text('排除',
                              style: TextStyle(fontSize: 14)),
                          Switch(
                            value: exclude,
                            onChanged: (v) => setSheet(() => exclude = v),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () {
                              var raw = controller.text.trim();
                              if (raw.isEmpty) {
                                Navigator.of(sheetContext).pop();
                                return;
                              }
                              if (type == SearchConditionType.rj &&
                                  RegExp(r'^\d{4,}$').hasMatch(raw)) {
                                raw = 'RJ$raw';
                              }
                              final cond = SearchCondition(
                                  type: type,
                                  value: raw.toUpperCase().startsWith('RJ') &&
                                          type == SearchConditionType.rj
                                      ? raw
                                      : raw,
                                  exclude: exclude);
                              if (_editingIndex >= 0) {
                                setState(() =>
                                    _conditions[_editingIndex] = cond);
                                _editingIndex = -1;
                              } else {
                                _addCondition(cond);
                              }
                              Navigator.of(sheetContext).pop();
                            },
                            child: Text(initial == null ? '添加' : '保存'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    _editingIndex = -1;
  }

  // ---- 历史还原 ----

  void _restoreHistory(String serialized) {
    // 简化：解析「关键词:值 / 排除 标签:值」——完整还原复杂，先尝试
    // 解析为 keyword 条件文本（保留可追溯性）。
    _clearConditions();
    _controller.text = serialized;
    _addCondition(SearchCondition(
        type: SearchConditionType.keyword, value: serialized));
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('搜索', style: UiTextStyles.pageTitle),
        actions: [
          if (_conditions.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空条件',
              onPressed: _clearConditions,
            ),
        ],
      ),
      body: Column(
        children: [
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
                const Spacer(),
                if (!_onlineMode && _conditions.isNotEmpty)
                  SegmentedButton<SearchCombine>(
                    segments: const [
                      ButtonSegment(value: SearchCombine.and, label: Text('全部满足')),
                      ButtonSegment(value: SearchCombine.or, label: Text('任一满足')),
                    ],
                    selected: {_combine},
                    onSelectionChanged: (v) =>
                        setState(() => _combine = v.first),
                  ),
              ],
            ),
          ),
          // 条件 chips 区
          if (_conditions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: UiSpacing.medium, vertical: UiSpacing.xSmall),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < _conditions.length; i++)
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _editCondition(i),
                      onLongPress: () => _toggleExclude(i),
                      child: InputChip(
                        avatar: Icon(
                          _conditions[i].exclude
                              ? Icons.block
                              : _typeIcons[_conditions[i].type],
                          size: 15,
                          color: _conditions[i].exclude
                              ? scheme.error
                              : scheme.primary,
                        ),
                        label: Text(
                          _conditions[i].exclude
                              ? '排除 ${_conditions[i].displayValue}'
                              : _conditions[i].displayValue,
                          style: const TextStyle(fontSize: 13),
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {},
                        onDeleted: () => _removeCondition(i),
                      ),
                    ),
                ],
              ),
            ),
          // 添加条件
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: UiSpacing.medium, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      hintText: _conditions.isEmpty
                          ? '搜索：关键词 / RJ / 标签 / 社团 / 声优'
                          : '添加条件值…',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24)),
                    ),
                    onSubmitted: (text) {
                      if (text.trim().isEmpty) return;
                      _addCondition(SearchCondition(
                          type: SearchConditionType.keyword,
                          value: text.trim()));
                    },
                  ),
                ),
                const SizedBox(width: UiSpacing.xSmall),
                IconButton.filledTonal(
                  onPressed: () => _openAddSheet(),
                  icon: const Icon(Icons.add),
                  tooltip: '添加条件（支持排除与组合）',
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(context, scheme)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme scheme) {
    if (_onlineMode) {
      // 全网单条件：取第一个 include（keyword 常用）；OnlineSearchSection
      // 的 conditionType 与 query 映射。
      final inc = _conditions.where((c) => !c.exclude).toList();
      final keyword = inc.isNotEmpty && inc.first.type == SearchConditionType.keyword
          ? inc.first.value
          : '';
      final type = inc.isNotEmpty && inc.first.type != SearchConditionType.keyword
          ? inc.first.type
          : SearchConditionType.keyword;
      return OnlineSearchSection(
        conditionType: switch (type) {
          SearchConditionType.rj => 1,
          SearchConditionType.tag => 2,
          SearchConditionType.circle => 3,
          SearchConditionType.va => 4,
          SearchConditionType.keyword => 0,
        },
        query: keyword,
      );
    }

    if (_results.isNotEmpty) {
      return ListView.builder(
        key: const PageStorageKey('search_results'),
        itemCount: _results.length,
        itemBuilder: (context, index) => EnhancedWorkCard(
          work: _results[index],
          size: WorkCardSize.list,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (context) => WorkDetailScreen(work: _results[index]))),
        ),
      );
    }
    if (_searched) {
      return Center(
        child: Text('没有满足条件的作品',
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    // 空态：历史 + 引导。
    if (_history.isNotEmpty) {
      return ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(UiSpacing.medium),
            child: Text('最近搜索',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          for (final h in _history)
            ListTile(
              dense: true,
              leading: const Icon(Icons.history, size: 18),
              title: Text(h, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _restoreHistory(h),
            ),
        ],
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(UiSpacing.large),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.manage_search, size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: UiSpacing.medium),
            Text('输入关键词，或用「+」组合多个条件',
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: UiSpacing.xSmall),
            Text('支持：全部满足(AND) / 任一满足(OR) / 排除；长按条件切换排除',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
