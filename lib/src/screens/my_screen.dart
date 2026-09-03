import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../models/work.dart';
import '../providers/library_provider.dart';
import '../providers/ui_settings_provider.dart';
import '../utils/ui_tokens.dart';
import '../widgets/enhanced_work_card.dart';
import 'downloads_screen.dart';
import 'favorites_tab.dart';
import 'liked_tab.dart';
import 'history_tab.dart';
import 'server_playlists_tab.dart';
import 'status_tab.dart';
import 'subtitle_library_tab.dart';
import 'work_detail_screen.dart';

enum _LocalViewMode { all, identified, unident }

/// 「我的」全部可配置 Tab 定义（索引即隐藏键，2026-09-03）。
const List<({String label, IconData icon})> _myTabDefs = [
  (label: '状态', icon: Icons.bookmark_outline),
  (label: '收藏', icon: Icons.cloud_outlined),
  (label: '喜欢', icon: Icons.favorite_outline),
  (label: '本地库', icon: Icons.folder_outlined),
  (label: '历史', icon: Icons.history),
  (label: '播放列表', icon: Icons.queue_music),
  (label: '字幕库', icon: Icons.subtitles_outlined),
  (label: '下载', icon: Icons.download_outlined),
];

/// Tab3 我的页（2026-09-03：可配置 Tab 显示 + 状态/收藏/本地库视角）。
class MyScreen extends StatefulWidget {
  const MyScreen({super.key, this.onOpenSettings});

  /// 跳到主框架「设置」Tab。
  final VoidCallback? onOpenSettings;

  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  _LocalViewMode _viewMode = _LocalViewMode.all;

  void _openTabSheet(BuildContext context) {
    final ui = context.read<UiSettingsProvider>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        // 局部刷新：监听 provider 变化。
        return ListenableBuilder(
          listenable: ui,
          builder: (_, __) {
            final hidden = ui.myTabsHidden;
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(UiSpacing.small),
                    child: Text('显示哪些 Tab',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16)),
                  ),
                  for (var i = 0; i < _myTabDefs.length; i++)
                    SwitchListTile(
                      dense: true,
                      secondary: Icon(_myTabDefs[i].icon, size: 20),
                      title: Text(_myTabDefs[i].label),
                      value: !hidden.contains(i),
                      onChanged: (show) async {
                        // 至少保留一个可见 Tab。
                        if (!show && hidden.length >= _myTabDefs.length - 1) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                  content: Text('至少保留一个 Tab'),
                                  duration: Duration(seconds: 2)),
                            );
                          }
                          return;
                        }
                        await ui.setMyTabHidden(i, !show);
                      },
                    ),
                  const SizedBox(height: UiSpacing.medium),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _setViewMode(_LocalViewMode v) => setState(() => _viewMode = v);

  @override
  Widget build(BuildContext context) {
    final uiSettings = context.watch<UiSettingsProvider>();
    final hidden = uiSettings.myTabsHidden;
    final visibleIndexes = [
      for (var i = 0; i < _myTabDefs.length; i++)
        if (!hidden.contains(i)) i,
    ];
    return DefaultTabController(
      length: visibleIndexes.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text('我的', style: UiTextStyles.pageTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: '显示 Tab',
              onPressed: () => _openTabSheet(context),
            ),
            if (widget.onOpenSettings != null)
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: '设置',
                onPressed: widget.onOpenSettings,
              ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final i in visibleIndexes)
                Tab(
                  text: _myTabDefs[i].label,
                  iconMargin: const EdgeInsets.all(0),
                  height: 42,
                ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final i in visibleIndexes) _pageByIndex(i, hidden),
          ],
        ),
      ),
    );
  }

  Widget _pageByIndex(int i, Set<int> hidden) {
    switch (i) {
      case 0:
        return const StatusTab();
      case 1:
        return const FavoritesTab();
      case 2:
        return const LikedTab();
      case 3:
        return ListenableBuilder(
          listenable: context.watch<LibraryProvider>(),
          builder: (_, __) => _LocalLibraryView(viewMode: _viewMode),
        );
      case 4:
        return const HistoryTab();
      case 5:
        return const ServerPlaylistsTab();
      case 6:
        return const SubtitleLibraryTab();
      default:
        return const DownloadsScreen();
    }
  }
}

/// 本地库页：视角切换（全部/已识别/未识别）。
class _LocalLibraryView extends StatefulWidget {
  const _LocalLibraryView({required this.viewMode});

  final _LocalViewMode viewMode;

  @override
  State<_LocalLibraryView> createState() => _LocalLibraryViewState();
}

class _LocalLibraryViewState extends State<_LocalLibraryView> {
  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final allWorks = library.works;
    final works = allWorks.where((w) {
      switch (widget.viewMode) {
        case _LocalViewMode.all:
          return true;
        case _LocalViewMode.identified:
          return w.rjCode != null;
        case _LocalViewMode.unident:
          return w.rjCode == null;
      }
    }).toList();
    final unident = allWorks.where((w) => w.rjCode == null).toList();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              UiSpacing.medium, UiSpacing.small, UiSpacing.medium, 0),
          child: SegmentedButton<_LocalViewMode>(
            segments: const [
              ButtonSegment(value: _LocalViewMode.all, label: Text('全部')),
              ButtonSegment(
                  value: _LocalViewMode.identified, label: Text('已识别')),
              ButtonSegment(
                  value: _LocalViewMode.unident, label: Text('未识别')),
            ],
            selected: {widget.viewMode},
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (v) {
              final parent =
                  context.findAncestorStateOfType<_MyScreenState>();
              parent?._setViewMode(v.first);
            },
          ),
        ),
        if (widget.viewMode == _LocalViewMode.unident && unident.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(UiSpacing.medium,
                UiSpacing.xSmall, UiSpacing.medium, 0),
            child: Row(
              children: [
                Icon(Icons.help_outline,
                    size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${unident.length} 个作品未识别 RJ',
                      style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant)),
                ),
                TextButton.icon(
                  onPressed: () => _openBulkRjSheet(context, unident),
                  icon: const Icon(Icons.edit_note, size: 16),
                  label: const Text('批量补录'),
                ),
              ],
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
    );
  }

  /// 批量补录 RJ（未识别视角，2026-09-03）。
  void _openBulkRjSheet(BuildContext context, List<Work> unident) {
    final library = context.read<LibraryProvider>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final remaining = [...unident];
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            if (remaining.isEmpty) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(UiSpacing.large),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 40),
                      const SizedBox(height: UiSpacing.medium),
                      const Text('全部补录完成 🎉',
                          style: TextStyle(fontSize: 16)),
                      const SizedBox(height: UiSpacing.small),
                      Text('未识别作品已全部标注 RJ',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    ],
                  ),
                ),
              );
            }
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(UiSpacing.small),
                    child: Text('补录 RJ 号（${remaining.length} 个未识别）',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16)),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: remaining.length,
                      itemBuilder: (context, i) => ListTile(
                        dense: true,
                        title: Text(remaining[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        subtitle: const Text('填写后点 ➜'),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: '补 RJ',
                          onPressed: () async {
                            final norm = await _askRj(context, remaining[i].title);
                            if (norm == null) return;
                            final ok = await library
                                .setWorkRjCode(remaining[i].id, norm);
                            if (!ctx.mounted) return;
                            if (ok) {
                              setSheetState(
                                  () => remaining.removeAt(i));
                            } else {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('保存失败')));
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(UiSpacing.small),
                    child: Text('提示：可直接输数字，如 416816 → RJ416816',
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 询问单个 RJ 号，返回规范化值或 null（取消）。
  Future<String?> _askRj(BuildContext context, String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('补录 RJ 号'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: UiSpacing.small),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'RJ416816 或 416816',
                helperText: 'RJ / BJ / VJ 前缀均可',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return null;
    var norm = result.toUpperCase().replaceAll(RegExp(r'[\s\-—]'), '');
    // 纯数字自动补 RJ 前缀。
    if (RegExp(r'^\d+$').hasMatch(norm)) norm = 'RJ\$norm';
    if (!RegExp(r'^(RJ|BJ|VJ)\d+$').hasMatch(norm)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('格式不对：应为 RJ/BJ/VJ + 数字'),
            duration: Duration(seconds: 3)));
      }
      return null;
    }
    return norm;
  }

  void _openDetail(BuildContext context, dynamic work) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => WorkDetailScreen(work: work),
      ),
    );
  }
}

