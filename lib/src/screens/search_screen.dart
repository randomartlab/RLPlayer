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

  /// 搜索条件类型（PRD §5.7：关键词/RJ号/标签/社团/声优）。
  int _conditionType = 0;
  static const _conditions = [
    ('关键词', Icons.text_fields),
    ('RJ 号', Icons.tag),
    ('标签', Icons.label_outline),
    ('社团', Icons.group_outlined),
    ('声优', Icons.mic_outlined),
  ];

  /// 搜索历史（最近 10 条，PRD 验收要求）。
  List<String> _history = const [];
  static const String _historyKey = 'search_history';

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
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _query = value.trim());
      _search();
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

    final results = <Work>[];
    for (final work in library.works) {
      var hit = false;
      switch (_conditionType) {
        case 1: // RJ 号（纯数字自动补前缀）。
          final rj =
              RegExp(r'^\d{5,8}$').hasMatch(query) ? 'rj$query' : query;
          hit = work.rjCode?.toLowerCase() == rj ||
              work.rjCode?.toLowerCase().contains(query) == true;
        case 2: // 标签：works.tags + NetMeta.netTags。
          hit = work.tags.any((t) => t.toLowerCase().contains(query));
          hit = hit ||
              await _netMetaMatch(db, work,
                  (m) => m.netTags.any((t) => t.toLowerCase().contains(query)));
        case 3: // 社团。
          hit = work.circleName?.toLowerCase().contains(query) ?? false;
          hit = hit ||
              await _netMetaMatch(db, work,
                  (m) => m.netCircle?.toLowerCase().contains(query) ?? false);
        case 4: // 声优。
          hit = work.vasNames
              .any((v) => v.toLowerCase().contains(query));
          hit = hit ||
              await _netMetaMatch(db, work,
                  (m) => m.netVas.any((v) => v.toLowerCase().contains(query)));
        default: // 关键词：标题/社团 + 音轨名。
          hit = work.title.toLowerCase().contains(query) ||
              (work.circleName?.toLowerCase().contains(query) ?? false);
          if (!hit) {
            final nodes = await library.nodesOf(work);
            hit = nodes.any((node) =>
                !node.isDirectory &&
                node.displayName.toLowerCase().contains(query));
          }
      }
      if (hit) results.add(work);
    }
    if (mounted) {
      setState(() {
        _results = results;
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
          // 条件类型 chips（PRD §5.7 五条件）。
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
            child: _results.isNotEmpty
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
            '完全离线 · 支持作品名 / 音轨名 / RJ 号',
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
