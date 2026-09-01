import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../models/audio_track.dart';
import '../models/work.dart';
import '../providers/audio_provider.dart';
import '../providers/library_provider.dart';
import '../utils/playback_helpers.dart';
import '../utils/responsive_grid_helper.dart';
import '../utils/ui_tokens.dart';
import '../widgets/enhanced_work_card.dart';
import 'online_works_screen.dart';
import 'work_detail_screen.dart';
import 'folder_picker_screen.dart';

/// Tab1 作品页（M3 封面墙）。
///
/// - 顶部「本地 / 在线」双源切换（默认本地；在线视图 M3 里程碑接入）；
/// - 瀑布流封面墙：大网格 2/3/4 列、小网格 3/5 列，间距 竖屏 8 / 横屏 24；
/// - 悬浮工具栏：视图切换（大网格/小网格/列表）+ 排序 + 重新扫描，
///   48dp 胶囊 r24（PRD §5.4 / UI 规范 §5.1）。
class WorksScreen extends StatefulWidget {
  const WorksScreen({super.key});

  @override
  State<WorksScreen> createState() => _WorksScreenState();
}

enum _GridViewMode { large, small, list }

class _WorksScreenState extends State<WorksScreen> {
  int _sourceIndex = 0; // 0 = 本地（默认），1 = 在线
  _GridViewMode _viewMode = _GridViewMode.large;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final works = library.works;

    return Scaffold(
      appBar: AppBar(
        title: Text('作品', style: UiTextStyles.pageTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: UiSpacing.medium),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('本地')),
                  ButtonSegment(value: 1, label: Text('在线')),
                ],
                selected: {_sourceIndex},
                onSelectionChanged: (selection) =>
                    setState(() => _sourceIndex = selection.first),
              ),
            ),
          ),
        ),
      ),
      body: _sourceIndex == 1 ? _buildOnlineBody() : _buildLocalBody(works),
      floatingActionButton: _sourceIndex == 0 && works.isNotEmpty
          ? FloatingActionButton.small(
              onPressed: () => _playAll(context, works.first),
              tooltip: '随机播放',
              child: const Icon(Icons.shuffle),
            )
          : null,
    );
  }

  Widget _buildLocalBody(List<Work> works) {
    final library = context.watch<LibraryProvider>();

    if (library.scanning) {
      return _buildScanningView(library);
    }
    if (works.isEmpty) {
      return _buildEmptyView();
    }

    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: _buildGrid(works),
        ),
      ],
    );
  }

  /// 扫描进行中视图：进度可见、可取消（PRD 验收：扫描不阻塞 UI）。
  Widget _buildScanningView(LibraryProvider library) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(UiSpacing.xLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: UiSpacing.large),
            Text(
              '正在扫描本地库…',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: UiSpacing.small),
            Text(
              '已发现 ${library.scanningFound} 个作品',
              style: UiTextStyles.supporting
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            if (library.scanningPath != null) ...[
              const SizedBox(height: UiSpacing.xSmall),
              Text(
                library.scanningPath!,
                style: UiTextStyles.supporting
                    .copyWith(color: scheme.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: UiSpacing.large),
            OutlinedButton.icon(
              onPressed: library.cancelScan,
              icon: const Icon(Icons.close),
              label: const Text('取消扫描'),
            ),
          ],
        ),
      ),
    );
  }

  /// 空态：引导到设置添加扫描根目录。
  Widget _buildEmptyView() {
    final scheme = Theme.of(context).colorScheme;
    final library = context.watch<LibraryProvider>();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(UiSpacing.xLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_music_outlined,
                size: 64, color: scheme.onSurfaceVariant),
            const SizedBox(height: UiSpacing.medium),
            Text(
              library.roots.isEmpty ? '尚未指定扫描根目录' : '指定目录中未发现音频作品',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: UiSpacing.xSmall),
            Text(
              '到 设置 → 本地库 添加扫描根目录\n支持任意层级嵌套的 RJ 作品文件夹',
              style: UiTextStyles.supporting
                  .copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: UiSpacing.large),
            FilledButton.icon(
              onPressed: _goToSettings,
              icon: const Icon(Icons.folder_open),
              label: const Text('选择扫描根目录'),
            ),
          ],
        ),
      ),
    );
  }

  /// 悬浮工具栏：48dp 胶囊 r24（视图切换 + 排序 + 重新扫描）。
  Widget _buildToolbar() {
    final scheme = Theme.of(context).colorScheme;
    final library = context.read<LibraryProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        UiSpacing.medium, UiSpacing.xSmall, UiSpacing.medium, UiSpacing.small),
      child: SizedBox(
        height: UiControlSize.standard,
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(UiControlSize.standard / 2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: UiSpacing.xSmall),
            child: Row(
              children: [
                _ToolbarIcon(
                  icon: Icons.grid_view,
                  selected: _viewMode == _GridViewMode.large,
                  tooltip: '大网格',
                  onTap: () =>
                      setState(() => _viewMode = _GridViewMode.large),
                ),
                _ToolbarIcon(
                  icon: Icons.grid_view_outlined,
                  selected: _viewMode == _GridViewMode.small,
                  tooltip: '小网格',
                  onTap: () =>
                      setState(() => _viewMode = _GridViewMode.small),
                ),
                _ToolbarIcon(
                  icon: Icons.view_list_outlined,
                  selected: _viewMode == _GridViewMode.list,
                  tooltip: '列表',
                  onTap: () => setState(() => _viewMode = _GridViewMode.list),
                ),
                const VerticalDivider(
                    width: 1, indent: 10, endIndent: 10),
                PopupMenuButton<WorkSortBy>(
                  icon: Icon(Icons.sort_by_alpha,
                      color: scheme.onSurfaceVariant),
                  tooltip: '排序',
                  initialValue: library.sortBy,
                  onSelected: library.setSortBy,
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: WorkSortBy.title,
                      child: Text('按标题'),
                    ),
                    PopupMenuItem(
                      value: WorkSortBy.addedAt,
                      child: Text('按添加时间'),
                    ),
                    PopupMenuItem(
                      value: WorkSortBy.rjCode,
                      child: Text('按 RJ 号'),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.refresh,
                      color: scheme.onSurfaceVariant),
                  tooltip: '重新扫描',
                  onPressed: () => library.rescan(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 瀑布流网格（flutter_staggered_grid_view，KikoFlu 沿用清单）。
  Widget _buildGrid(List<Work> works) {
    final layout = ResponsiveGridHelper.of(context);
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final spacing =
        isPortrait ? UiSpacing.small : UiSpacing.xLarge; // 8 / 24

    if (_viewMode == _GridViewMode.list) {
      return ListView.builder(
        key: const PageStorageKey('works_list'),
        itemCount: works.length,
        itemBuilder: (context, index) => EnhancedWorkCard(
          work: works[index],
          size: WorkCardSize.list,
          onTap: () => _openDetail(context, works[index]),
        ),
      );
    }

    final crossAxisCount = _viewMode == _GridViewMode.large
        ? layout.largeGridColumns
        : layout.smallGridColumns;
    final cardSize = _viewMode == _GridViewMode.large
        ? WorkCardSize.medium
        : WorkCardSize.compact;

    return MasonryGridView.count(
      key: PageStorageKey('works_grid_$_viewMode'),
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      padding: EdgeInsets.fromLTRB(
        spacing, UiSpacing.xSmall, spacing, UiSpacing.xLarge),
      itemCount: works.length,
      itemBuilder: (context, index) => EnhancedWorkCard(
        work: works[index],
        size: cardSize,
        onTap: () => _openDetail(context, works[index]),
      ),
    );
  }

  Widget _buildOnlineBody() {
    // M12 在线封面墙（游客可浏览；断网错误态不崩溃）。
    return const OnlineWorksScreen();
  }

  void _openDetail(BuildContext context, Work work) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => WorkDetailScreen(work: work),
      ),
    );
  }

  void _goToSettings() {
    // 直接打开扫描根目录选择（免切 Tab，更短路径）。
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const FolderPickerScreen(),
      ),
    );
  }

  /// 随机播放全部作品音轨（M3 简化入口；播放列表管理 M4 引入）。
  Future<void> _playAll(BuildContext context, Work firstWork) async {
    final library = context.read<LibraryProvider>();
    final audio = context.read<AudioPlayerProvider>();

    final tracks = <AudioTrack>[];
    for (final work in library.works) {
      final nodes = await library.nodesOf(work);
      tracks.addAll(tracksOf(work, nodes));
    }
    if (tracks.isEmpty) return;
    tracks.shuffle();
    await audio.playTracks(tracks);
  }
}

class _ToolbarIcon extends StatelessWidget {
  const _ToolbarIcon({
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      color: selected ? scheme.primary : scheme.onSurfaceVariant,
      onPressed: onTap,
    );
  }
}
