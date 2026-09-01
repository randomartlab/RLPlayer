import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/work.dart';
import '../providers/library_provider.dart';
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
    final query = _query.toLowerCase();

    // RJ 号：输入纯数字时补全前缀。
    final rjQuery = RegExp(r'^\d{5,8}$').hasMatch(query)
        ? 'rj$query'
        : query.toLowerCase();

    final results = <Work>[];
    for (final work in library.works) {
      if (work.title.toLowerCase().contains(query) ||
          work.rjCode?.toLowerCase() == rjQuery ||
          work.rjCode?.toLowerCase().contains(query) == true ||
          (work.circleName?.toLowerCase().contains(query) ?? false)) {
        results.add(work);
        continue;
      }
      // 音轨名匹配（命中则该作品入结果）。
      final nodes = await library.nodesOf(work);
      if (nodes.any((node) =>
          !node.isDirectory && node.displayName.toLowerCase().contains(query))) {
        results.add(work);
      }
    }
    if (mounted) {
      setState(() {
        _results = results;
        _searched = true;
      });
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
                    : _buildIdle(context),
          ),
        ],
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

  void _openDetail(BuildContext context, Work work) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => WorkDetailScreen(work: work),
      ),
    );
  }
}
