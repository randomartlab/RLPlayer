import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../providers/library_provider.dart';
import '../utils/ui_tokens.dart';
import '../widgets/enhanced_work_card.dart';
import 'downloads_screen.dart';
import 'history_tab.dart';
import 'playlists_screen.dart';
import 'status_tab.dart';
import 'subtitle_library_tab.dart';
import 'work_detail_screen.dart';

enum _LocalViewMode { all, identified, unident }

/// Tab3 我的页（2026-09-03 M1：状态清单 tab + 本地库视角切换）。
class MyScreen extends StatefulWidget {
  const MyScreen({super.key});

  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  _LocalViewMode _viewMode = _LocalViewMode.all;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final allWorks = library.works;
    final works = allWorks.where((w) {
      switch (_viewMode) {
        case _LocalViewMode.all:
          return true;
        case _LocalViewMode.identified:
          return w.rjCode != null;
        case _LocalViewMode.unident:
          return w.rjCode == null;
      }
    }).toList();
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text('我的', style: UiTextStyles.pageTitle),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: '状态'),
              Tab(text: '本地库'),
              Tab(text: '历史'),
              Tab(text: '播放列表'),
              Tab(text: '字幕库'),
              Tab(text: '下载'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const StatusTab(),
            // 本地库：视角切换（全部/已识别/未识别）。
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      UiSpacing.medium, UiSpacing.small, UiSpacing.medium, 0),
                  child: SegmentedButton<_LocalViewMode>(
                    segments: const [
                      ButtonSegment(value: _LocalViewMode.all, label: Text('全部')),
                      ButtonSegment(
                          value: _LocalViewMode.identified,
                          label: Text('已识别')),
                      ButtonSegment(
                          value: _LocalViewMode.unident, label: Text('未识别')),
                    ],
                    selected: {_viewMode},
                    style:
                        const ButtonStyle(visualDensity: VisualDensity.compact),
                    onSelectionChanged: (v) => setState(() => _viewMode = v.first),
                  ),
                ),
                Expanded(
                  child: works.isEmpty
                      ? Center(
                          child: Text(
                            allWorks.isEmpty
                                ? (library.scanning ? '正在扫描…' : '本地库为空')
                                : '该视角下暂无作品',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        )
                      : MasonryGridView.count(
                          key: const PageStorageKey('my_library_grid'),
                          crossAxisCount: 3,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          padding: const EdgeInsets.all(UiSpacing.medium),
                          itemCount: works.length,
                          itemBuilder: (context, index) => EnhancedWorkCard(
                            work: works[index],
                            size: WorkCardSize.compact,
                            onTap: () => _openDetail(context, works[index]),
                          ),
                        ),
                ),
              ],
            ),
            const HistoryTab(),
            const PlaylistsScreen(),
            const SubtitleLibraryTab(),
            const DownloadsScreen(),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, dynamic work) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => WorkDetailScreen(work: work),
      ),
    );
  }
}
