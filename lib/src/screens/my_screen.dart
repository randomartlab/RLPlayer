import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/library_provider.dart';
import '../utils/ui_tokens.dart';
import '../widgets/enhanced_work_card.dart';
import 'downloads_screen.dart';
import 'history_tab.dart';
import 'playlists_screen.dart';
import 'subtitle_library_tab.dart';
import 'work_detail_screen.dart';

/// Tab3 我的页（M2：本地库 + 下载管理；历史/播放列表/字幕库 M4 补齐）。
class MyScreen extends StatelessWidget {
  const MyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final works = library.works;
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text('我的', style: UiTextStyles.pageTitle),
          bottom: const TabBar(
            tabs: [
              Tab(text: '本地库'),
              Tab(text: '历史'),
              Tab(text: '播放列表'),
              Tab(text: '字幕库'),
              Tab(text: '下载管理'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            works.isEmpty
                ? Center(
                    child: Text(
                      library.scanning ? '正在扫描…' : '本地库为空',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  )
                : GridView.builder(
                    key: const PageStorageKey('my_library_grid'),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 210,
                      childAspectRatio: 0.72,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                    ),
                    padding: const EdgeInsets.all(UiSpacing.medium),
                    itemCount: works.length,
                    itemBuilder: (context, index) => EnhancedWorkCard(
                      work: works[index],
                      size: WorkCardSize.compact,
                      onTap: () => _openDetail(context, works[index]),
                    ),
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

  void _openDetail(BuildContext context, work) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => WorkDetailScreen(work: work),
      ),
    );
  }
}
