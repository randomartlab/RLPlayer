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
import '../models/search_advanced.dart';
import '../models/search_query.dart';
import '../models/work.dart';
import '../providers/library_provider.dart';
import '../providers/mirror_provider.dart';
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
  /// 全站建议缓存（tag/circle/va 首次拉取后复用）。
  static final Map<SearchConditionType, List<Map<String, dynamic>>> _cloudCache =
      {};

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  bool _onlineMode = false;
  SearchCombine _combine = SearchCombine.and;
  final List<SearchCondition> _conditions = [];
  SearchAdvanced _advanced = const SearchAdvanced();
  bool _showAdvanced = false;
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
    return _conditions
        .map((c) =>
            '${c.type.name}:${c.exclude ? '!' : '+'}:${Uri.encodeComponent(c.value)}')
        .join('|');
  }

  // ---- 条件操作 ----

  /// 是否为「CV 合作」检索：>=2 个非排除 va include 条件。
  bool get _isVaCollab {
    final vas = _conditions
        .where((c) => c.type == SearchConditionType.va && !c.exclude)
        .toList();
    return vas.length >= 2 && _combine == SearchCombine.and;
  }

  /// va 条件按合作分隔符拆分（×、x、顿号、逗号），自动多条件。
  static List<String> _splitVa(String raw) {
    return raw
        .split(RegExp(r'[×xX、，,；;]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

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
      if (query.matches(work, meta: meta) &&
          applyLocalAdvanced(work, meta, _advanced)) {
        result.add(work);
      }
    }
    if (!mounted) return;
    setState(() {
      _results = result;
      _searched = true;
    });
    _saveHistory();
  }

  /// 输入框提交：有文字先加 keyword 条件，再执行搜索。
  void _startSearchFromInput() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      _addCondition(SearchCondition(
          type: SearchConditionType.keyword, value: text));
      return; // _addCondition 内部已 _run
    }
    if (_onlineMode || _conditions.isNotEmpty) {
      _run();
    }
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
    final mirror = context.read<MirrorProvider>();
    if (!mounted) return;
    var type = initial?.type ?? SearchConditionType.keyword;
    final controller =
        TextEditingController(text: initial != null ? initial.displayValue : '');
    var exclude = initial?.exclude ?? false;
    var cloudLoading = false;

    // 懒加载全站建议（tag/circle/va 首次拉取缓存）。
    Future<void> ensureCloud() async {
      if (type != SearchConditionType.tag &&
          type != SearchConditionType.circle &&
          type != SearchConditionType.va) {
        return;
      }
      if (_cloudCache.containsKey(type)) return;
      cloudLoading = true;
      try {
        final list = switch (type) {
          SearchConditionType.tag => await mirror.api.getAllTags(),
          SearchConditionType.circle => await mirror.api.getAllCircles(),
          _ => await mirror.api.getAllVas(),
        };
        _cloudCache[type] = list;
      } catch (_) {
        // 全站不可用 → 仅本地候选。
      } finally {
        cloudLoading = false;
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return StatefulBuilder(
          builder: (sheetContext, setSheet) {
            // 类型切换时懒拉全站建议。
            Future<void> onType(SearchConditionType t) async {
              setSheet(() => type = t);
              await ensureCloud();
              if (sheetContext.mounted) setSheet(() {});
            }



            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(UiSpacing.large,
                      UiSpacing.small, UiSpacing.large, UiSpacing.large),
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
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      if (!_onlineMode)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '添加后将按「${_combine == SearchCombine.and ? '全部满足 AND' : '任一满足 OR'}」组合'
                            '${_combine == SearchCombine.and ? '（可在搜索页切换）' : '（可在搜索页切换）'}',
                            style: TextStyle(
                                fontSize: 11,
                                color: scheme.primary),
                          ),
                        ),
                      // 类型 chips（Wrap 防大字体溢出）。
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in SearchConditionType.values)
                            ChoiceChip(
                              label: Text(_typeLabels[t]!,
                                  style: const TextStyle(fontSize: 12)),
                              selected: type == t,
                              visualDensity: VisualDensity.compact,
                              onSelected: (_) => onType(t),
                            ),
                        ],
                      ),
                      const SizedBox(height: UiSpacing.medium),
                      // 值输入框（kikoflu 式 RawAutocomplete：输入实时下拉补全）。
                      RawAutocomplete<Map<String, dynamic>>(
                        optionsBuilder: (val) {
                          if (type == SearchConditionType.rj) {
                            return const Iterable<Map<String, dynamic>>.empty();
                          }
                          final q = val.text.trim().toLowerCase();
                          return _autocompleteOptions(type, q);
                        },
                        displayStringForOption: (o) => o['name'] as String,
                        onSelected: (o) {
                          // 同步外层 controller（底部「添加」按钮读取它）。
                          controller.text = o['name'] as String? ?? '';
                          setSheet(() {});
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              borderRadius:
                                  BorderRadius.circular(UiRadii.control),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                    maxHeight: 220, maxWidth: 320),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (context, index) {
                                    final o = options.elementAt(index);
                                    return ListTile(
                                      dense: true,
                                      visualDensity:
                                          VisualDensity.compact,
                                      leading: (o['local'] == true)
                                          ? Icon(Icons.folder_outlined,
                                              size: 16,
                                              color: scheme.primary)
                                          : Icon(Icons.cloud_outlined,
                                              size: 16,
                                              color: scheme
                                                  .onSurfaceVariant),
                                      title: Text(o['name'] as String,
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow.ellipsis),
                                      trailing: o['count'] != null
                                          ? Text('${o['count']}',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: scheme
                                                      .onSurfaceVariant))
                                          : null,
                                      onTap: () => onSelected(o),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                        fieldViewBuilder: (context, textController,
                            focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: textController,
                            focusNode: focusNode,
                            autofocus: true,
                            onChanged: (_) {
                              controller.text = textController.text;
                            },
                            decoration: InputDecoration(
                              hintText: type == SearchConditionType.rj
                                  ? '输入数字自动补 RJ（如 416816）'
                                  : '输入${_typeLabels[type]}，实时弹推荐',
                              isDense: true,
                              border: const OutlineInputBorder(),
                              suffixIcon: type != SearchConditionType.rj
                                  ? IconButton(
                                      icon: const Icon(Icons.arrow_drop_down),
                                      onPressed: () =>
                                          textController.selection =
                                              TextSelection.collapsed(
                                                  offset: textController
                                                      .text.length),
                                    )
                                  : null,
                            ),
                            onSubmitted: (text) {
                              controller.text = textController.text;
                              var raw = controller.text.trim();
                              if (raw.isEmpty) return;
                              if (type == SearchConditionType.rj &&
                                  RegExp(r'^\d{4,}$').hasMatch(raw)) {
                                raw = 'RJ$raw';
                              }
                              final cond = SearchCondition(
                                  type: type, value: raw, exclude: exclude);
                              _commitCondition(sheetContext, cond);
                            },
                          );
                        },
                      ),
                      if (cloudLoading)
                        const Padding(
                          padding: EdgeInsets.all(4),
                          child: Center(
                              child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))),
                        ),
                      const SizedBox(height: UiSpacing.small),
                      // 排除 + 添加。
                      Row(
                        children: [
                          const Text('排除', style: TextStyle(fontSize: 14)),
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
                                  value: raw,
                                  exclude: exclude);
                              if (_editingIndex >= 0) {
                                setState(() => _conditions[_editingIndex] = cond);
                                _editingIndex = -1;
                              } else {
                                // CV 合作：va 输入可一次性多位（×/顿号/逗号）。
                                if (type == SearchConditionType.va &&
                                    !exclude) {
                                  final parts = _splitVa(raw);
                                  for (final part in parts) {
                                    _conditions.add(SearchCondition(
                                        type: type,
                                        value: part,
                                        exclude: exclude));
                                  }
                                  if (parts.length >= 2 &&
                                      _combine == SearchCombine.or) {
                                    _combine = SearchCombine.and;
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (sheetContext.mounted) {
                                        ScaffoldMessenger.of(sheetContext)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    '多位声优已按合作（全部满足 AND）添加；单人名去掉 ✓ 可回到 OR'),
                                                duration: Duration(seconds: 4)));
                                      }
                                    });
                                  }
                                } else {
                                  _conditions.add(cond);
                                }
                              }
                              Navigator.of(sheetContext).pop();
                              _run();
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


  // ---- 条件添加辅助（RawAutocomplete options / commit）----

  List<Map<String, dynamic>> _autocompleteOptions(
      SearchConditionType type, String q) {
    final library = context.read<LibraryProvider>();
    final local = <String>{};
    for (final w in library.works) {
      final meta = library.netMetaOf(w);
      switch (type) {
        case SearchConditionType.tag:
          local.addAll(w.tags);
          local.addAll(meta?.netTags ?? const []);
        case SearchConditionType.circle:
          if (w.circleName != null) local.add(w.circleName!);
          if (meta?.netCircle != null) local.add(meta!.netCircle!);
        case SearchConditionType.va:
          local.addAll(w.vasNames);
          local.addAll(meta?.netVas ?? const []);
        default:
          if (w.rjCode != null) local.add(w.rjCode!);
          local.add(w.title);
          if (w.circleName != null) local.add(w.circleName!);
          if (meta?.netCircle != null) local.add(meta!.netCircle!);
          local.addAll(w.vasNames);
          local.addAll(meta?.netVas ?? const []);
      }
    }
    final out = <Map<String, dynamic>>[];
    final localList = local.where((e) => e.isNotEmpty).toList()..sort();
    for (final e in localList) {
      if (q.isEmpty || e.toLowerCase().contains(q)) {
        out.add({'name': e, 'count': null, 'local': true});
      }
    }
    final cloud = _cloudCache[type];
    if (cloud != null) {
      final seen = localList.toSet();
      for (final item in cloud) {
        final name = (item['name'] as String?) ?? '';
        if (name.isEmpty || seen.contains(name)) continue;
        if (q.isEmpty || name.toLowerCase().contains(q)) {
          out.add({'name': name, 'count': item['count'] ?? 0, 'local': false});
        }
      }
    }
    return out.take(50).toList();
  }

  void _commitCondition(BuildContext sheetContext, SearchCondition cond) {
    if (_editingIndex >= 0) {
      setState(() => _conditions[_editingIndex] = cond);
      _editingIndex = -1;
    } else {
      setState(() => _conditions.add(cond));
    }
    Navigator.of(sheetContext).pop();
    _run();
  }

  // ---- 历史还原 ----

  void _restoreHistory(String serialized) {
    _clearConditions();
    final parts = serialized.split('|');
    for (final p in parts) {
      final seg = p.split(':');
      if (seg.length != 3) continue;
      final type = SearchConditionType.values
          .where((t) => t.name == seg[0])
          .firstOrNull;
      if (type == null) continue;
      _conditions.add(SearchCondition(
        type: type,
        exclude: seg[1] == '!',
        value: Uri.decodeComponent(seg[2]),
      ));
    }
    setState(() {});
    _run();
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
            child: Wrap(
              spacing: UiSpacing.medium,
              runSpacing: UiSpacing.xSmall,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('本地')),
                    ButtonSegment(value: true, label: Text('全网')),
                  ],
                  selected: {_onlineMode},
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact),
                  onSelectionChanged: (v) =>
                      setState(() => _onlineMode = v.first),
                ),
                // AND/OR 常显（本地与全网一致，2026-09-03 真机反馈 #1）。
                Tooltip(
                  message: _combine == SearchCombine.and
                      ? '全部条件同时满足'
                      : '任一条件满足即命中（OR）',
                  child: SegmentedButton<SearchCombine>(
                      segments: const [
                        ButtonSegment(
                            value: SearchCombine.and, label: Text('全部满足 AND')),
                        ButtonSegment(
                            value: SearchCombine.or, label: Text('任一满足 OR')),
                      ],
                      selected: {_combine},
                      style: const ButtonStyle(
                          visualDensity: VisualDensity.compact),
                      onSelectionChanged: (v) =>
                          setState(() => _combine = v.first),
                    ),
                  ),
              ],
            ),
          ),
          // 条件 chips 区
          if (_conditions.isNotEmpty) ...[
            if (_isVaCollab)
              Padding(
                padding: const EdgeInsets.fromLTRB(UiSpacing.medium,
                    UiSpacing.xSmall, UiSpacing.medium, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.groups_2_outlined,
                        size: 15, color: scheme.primary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text('CV 合作检索：作品需同时含这些声优（全部满足 AND）',
                          style: TextStyle(
                              fontSize: 11, color: scheme.primary)),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: UiSpacing.medium, vertical: UiSpacing.xSmall),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < _conditions.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(_combine == SearchCombine.and ? '且' : '或',
                            style: TextStyle(
                                fontSize: 12,
                                color: scheme.primary,
                                fontWeight: FontWeight.w600)),
                      ),
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
                ],
              ),
            ),
          ],
          // 高级筛选（搜索 M3：评分/年龄/销量）。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: UiSpacing.medium),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _showAdvanced = !_showAdvanced),
                  icon: Icon(Icons.tune,
                      size: 16,
                      color: _advanced.isActive
                          ? scheme.primary
                          : scheme.onSurfaceVariant),
                  label: Text(_advanced.isActive ? '筛选已启用' : '筛选',
                      style: TextStyle(
                          fontSize: 13,
                          color: _advanced.isActive
                              ? scheme.primary
                              : scheme.onSurfaceVariant)),
                ),
              ],
            ),
          ),
          if (_showAdvanced)
            Padding(
              padding: const EdgeInsets.fromLTRB(UiSpacing.medium, 0,
                  UiSpacing.medium, UiSpacing.xSmall),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('评分≥',
                      style: TextStyle(fontSize: 12)),
                  for (final r in const <double>[0, 1, 2, 3, 4, 4.5])
                    ChoiceChip(
                      label: Text(r == 0 ? '不限' : '$r',
                          style: const TextStyle(fontSize: 11)),
                      selected:
                          (_advanced.minRating == r && r != 0) ||
                              (r == 0 && _advanced.minRating == 0),
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) {
                        setState(() {
                          _advanced = SearchAdvanced(
                            minRating: r,
                            age: _advanced.age,
                            minSales: _advanced.minSales,
                          );
                        });
                        _run();
                      },
                    ),
                  const SizedBox(width: 4),
                  SegmentedButton<AgeFilter>(
                    segments: const [
                      ButtonSegment(value: AgeFilter.all, label: Text('全年龄')),
                      ButtonSegment(value: AgeFilter.sfw, label: Text('仅全年龄')),
                      ButtonSegment(value: AgeFilter.r18, label: Text('仅R18')),
                    ],
                    selected: {_advanced.age},
                    style: const ButtonStyle(
                        visualDensity: VisualDensity.compact),
                    onSelectionChanged: (v) {
                      setState(() {
                        _advanced = SearchAdvanced(
                          minRating: _advanced.minRating,
                          age: v.first,
                          minSales: _advanced.minSales,
                        );
                      });
                      _run();
                    },
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
                          : '输入后点「搜索」添加关键词条件',
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24)),
                    ),
                    onSubmitted: (text) => _startSearchFromInput(),
                  ),
                ),
                const SizedBox(width: UiSpacing.xSmall),
                // 明确「搜索」按钮：提交输入并执行。
                FilledButton(
                  onPressed: _startSearchFromInput,
                  child: const Text('搜索'),
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
      final inc = _conditions.where((c) => !c.exclude).toList();
      final exc = _conditions.where((c) => c.exclude).toList();
      // 统一走组合检索：>=1 include 均可用（单条件也可收窄 + 高级筛选）。
      if (inc.isNotEmpty) {
        return OnlineCombineSearch(
          includes: inc,
          excludes: exc,
          combine: _combine,
          advanced: _advanced,
        );
      }
      // 全网无 include 条件：提示先添加条件。
      return Center(
        child: Text('全网搜索请先添加条件（「+」或输入框回车）',
            style: TextStyle(color: scheme.onSurfaceVariant)),
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
              title: Text(h, maxLines: 2, overflow: TextOverflow.ellipsis),
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
