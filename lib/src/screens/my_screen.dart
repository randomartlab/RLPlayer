import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/library_provider.dart';
import '../utils/ui_tokens.dart';
import '../widgets/enhanced_work_card.dart';
import 'work_detail_screen.dart';

/// Tab3 我的页（M2：本地库 Tab；历史/播放列表/字幕库 M4 里程碑补齐）。
///
/// 布局复刻来源 local_downloads_screen（UI 规范 §5.7）：
/// 网格 maxCrossAxisExtent 210dp、aspectRatio 0.72、间距 12dp。
class MyScreen extends StatelessWidget {
  const MyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final works = library.works;
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text('我的', style: UiTextStyles.pageTitle),
          bottom: TabBar(
            tabs: const [
              Tab(text: '本地库'),
              // 历史 / 播放列表 / 字幕库（M4 里程碑）。
            ],
          ),
        ),
        body: works.isEmpty
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
