import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/work.dart';
import '../providers/library_provider.dart';
import '../providers/playlist_provider.dart';
import '../utils/ui_tokens.dart';
import 'audio_player_screen.dart';

/// 播放列表管理（M7，PRD §5.8：创建/删除/详情/拖拽排序/整体播放）。
class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlaylistProvider>().refresh();
    });
  }

  /// 创建弹窗：双段「新建 / 链接导入」（PRD §5.8 规格）。
  Future<void> _showCreateDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final playlist = context.read<PlaylistProvider>();
    final library = context.read<LibraryProvider>();

    var mode = 0; // 0 新建 / 1 链接导入。
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final linkController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('新建播放列表'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('新建')),
                  ButtonSegment(value: 1, label: Text('链接导入')),
                ],
                selected: {mode},
                onSelectionChanged: (selection) =>
                    setDialogState(() => mode = selection.first),
              ),
              const SizedBox(height: UiSpacing.medium),
              if (mode == 0) ...[
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                      labelText: '名称', counterText: ''),
                  maxLength: 50,
                  autofocus: true,
                ),
                const SizedBox(height: UiSpacing.medium),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                      labelText: '描述（可选）', counterText: ''),
                  maxLength: 200,
                ),
              ] else
                TextField(
                  controller: linkController,
                  decoration: const InputDecoration(
                    labelText: '粘贴分享文本',
                    hintText: '支持任意含 RJ 号的文本（自动提取）',
                    counterText: '',
                  ),
                  maxLines: 4,
                  maxLength: 2000,
                  autofocus: true,
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                if (mode == 0) {
                  await playlist.create(nameController.text,
                      description: descController.text);
                  return;
                }
                // 链接导入：正则提取 RJ 号 → 匹配本地作品 → 批量加歌。
                final rjCodes = RegExp(r'(RJ|BJ|VJ)(\d{6,8})',
                        caseSensitive: false)
                    .allMatches(linkController.text)
                    .map((m) =>
                        '${m.group(1)!.toUpperCase()}${m.group(2)}')
                    .toSet();
                if (rjCodes.isEmpty) {
                  messenger.showSnackBar(const SnackBar(
                      content: Text('未从文本中识别到 RJ 号'),
                      duration: Duration(seconds: 2)));
                  return;
                }
                final name =
                    nameController.text.trim().isEmpty ? '导入列表' : nameController.text.trim();
                await playlist.create(name);
                final created =
                    playlist.playlists.firstOrNull;
                if (created == null) return;
                var added = 0;
                for (final rj in rjCodes) {
                  final work = library.works
                      .where((w) => w.rjCode == rj)
                      .firstOrNull;
                  if (work == null) continue;
                  final nodes = await library.nodesOf(work);
                  for (final node in nodes.where((n) => !n.isDirectory)) {
                    await playlist.addTrack(created.id, work, node);
                    added++;
                  }
                }
                messenger.showSnackBar(SnackBar(
                  content: Text(
                      '导入完成：识别 ${rjCodes.length} 个 RJ，本地匹配加入 $added 首（未下载的作品自动跳过）'),
                  duration: const Duration(seconds: 4),
                ));
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlists = context.watch<PlaylistProvider>().playlists;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('播放列表'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建播放列表',
            onPressed: _showCreateDialog,
          ),
        ],
      ),
      body: playlists.isEmpty
          ? Center(
              child: Text(
                '暂无播放列表\n在作品详情页长按音轨加入',
                textAlign: TextAlign.center,
                style: UiTextStyles.supporting
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          : ListView.builder(
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return ListTile(
                  leading: Icon(Icons.queue_music, color: scheme.primary),
                  title: Text(playlist.name),
                  subtitle: Text(
                    playlist.description?.isNotEmpty == true
                        ? '${playlist.description} · ${playlist.itemCount} 首'
                        : '${playlist.itemCount} 首',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDelete(playlist),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          PlaylistDetailScreen(playlist: playlist),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _confirmDelete(PlaylistInfo playlist) async {
    final provider = context.read<PlaylistProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除播放列表'),
        content: Text('「${playlist.name}」将被删除（不影响音源文件）。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.remove(playlist.id);
    }
  }
}

/// 播放列表详情：音轨列表 / 拖拽排序 / 左滑移除 / 整体播放。
class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlist});

  final PlaylistInfo playlist;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  List<PlaylistItem> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items =
        await context.read<PlaylistProvider>().itemsOf(widget.playlist.id);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = context.read<PlaylistProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_circle_outline),
            tooltip: '整体播放',
            onPressed: _items.isEmpty
                ? null
                : () async {
                    await provider.playAll(widget.playlist.id);
                    if (!context.mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (context) => const AudioPlayerScreen()),
                    );
                  },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Text('列表为空，在作品详情页长按音轨加入',
                      style: UiTextStyles.supporting
                          .copyWith(color: scheme.onSurfaceVariant)),
                )
              : ReorderableListView.builder(
                  itemCount: _items.length,
                  onReorderItem: (oldIndex, newIndex) async {
                    final items = [..._items];
                    final item = items.removeAt(oldIndex);
                    items.insert(newIndex.clamp(0, items.length), item);
                    setState(() => _items = items);
                    await provider.reorder(widget.playlist.id, items);
                  },
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Dismissible(
                      key: Key('pl_item_${item.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: scheme.errorContainer,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: UiSpacing.large),
                        child: Icon(Icons.delete_outline,
                            color: scheme.onErrorContainer),
                      ),
                      onDismissed: (_) async {
                        await provider.removeItem(item.id);
                        _load();
                      },
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: UiSpacing.medium),
                        leading: _cover(item.coverPath),
                        title: Text(item.trackTitle,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: item.workTitle != null
                            ? Text(item.workTitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: UiTextStyles.supporting)
                            : null,
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: Icon(Icons.drag_handle,
                              color: scheme.onSurfaceVariant),
                        ),
                        onTap: () async {
                          await provider.playAll(widget.playlist.id,
                              startIndex: index);
                          if (!context.mounted) return;
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (context) =>
                                    const AudioPlayerScreen()),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }

  Widget _cover(String? path) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 48,
      height: 48,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(UiRadii.control),
        child: path != null
            ? Image.file(File(path),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.album, color: scheme.onSurfaceVariant))
            : Icon(Icons.album, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// 长按音轨 → 选择播放列表对话框（本地详情页文件树入口）。
Future<void> showAddToPlaylistDialog(
    BuildContext context, Work work, FileNode node) async {
  final provider = context.read<PlaylistProvider>();
  await provider.refresh();
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: UiSpacing.large),
            child: Text('加入播放列表',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: UiSpacing.small),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: provider.playlists.length,
              itemBuilder: (context, index) {
                final playlist = provider.playlists[index];
                return ListTile(
                  leading: const Icon(Icons.queue_music),
                  title: Text(playlist.name),
                  subtitle: Text('${playlist.itemCount} 首'),
                  onTap: () async {
                    await provider.addTrack(playlist.id, work, node);
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: UiSpacing.large),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('新建播放列表'),
                onPressed: () async {
                  Navigator.of(sheetContext).pop();
                  final controller = TextEditingController();
                  final name = await showDialog<String>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('新建播放列表'),
                      content: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                            labelText: '名称', counterText: ''),
                        maxLength: 50,
                        autofocus: true,
                      ),
                      actions: [
                        TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(),
                            child: const Text('取消')),
                        FilledButton(
                            onPressed: () => Navigator.of(dialogContext)
                                .pop(controller.text.trim()),
                            child: const Text('创建并加入')),
                      ],
                    ),
                  );
                  if (name == null || name.isEmpty) return;
                  await provider.create(name);
                  final fresh =
                      provider.playlists.firstOrNull;
                  if (fresh != null) {
                    await provider.addTrack(fresh.id, work, node);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: UiSpacing.medium),
        ],
      ),
    ),
  );
}
