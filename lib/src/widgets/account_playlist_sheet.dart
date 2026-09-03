/// 账号播放列表操作（kikoeru/kikoflu 同款，2026-09-03）。
/// 作品详情 → 「添加到播放列表」：列出账号（服务器）播放列表并添加；
/// 可新建；未登录引导；失败可重试不转圈。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/mirror_provider.dart';
import '../utils/ui_tokens.dart';

/// 展示账号播放列表底部弹层。返回 true 表示完成一次成功添加。
Future<bool> showAccountPlaylistSheet(
  BuildContext context, {
  required String workId,
  required String workTitle,
}) async {
  final mirror = context.read<MirrorProvider>();
  if (!mirror.hasAnyLogin) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('账号播放列表需先登录（设置 → 服务器与账号）'),
          duration: Duration(seconds: 3)));
    }
    return false;
  }

  List<Map<String, dynamic>> playlists = const [];
  var loading = true;
  var error = false;

  Future<void> load() async {
    loading = true;
    error = false;
    try {
      playlists = await mirror.fetchAccountPlaylists();
    } catch (_) {
      error = true;
      playlists = const [];
    } finally {
      loading = false;
    }
  }

  await load();
  if (!context.mounted) return false;

  var added = false;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      return StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: UiSpacing.large, vertical: UiSpacing.xSmall),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('添加到账号播放列表',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 16)),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final nameController = TextEditingController();
                        final name = await showDialog<String>(
                          context: ctx,
                          builder: (dctx) => AlertDialog(
                            title: const Text('新建播放列表'),
                            content: TextField(
                              controller: nameController,
                              autofocus: true,
                              decoration: const InputDecoration(
                                  labelText: '名称',
                                  hintText: '如：ASMR 合集',
                                  border: OutlineInputBorder()),
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.of(dctx).pop(),
                                  child: const Text('取消')),
                              FilledButton(
                                  onPressed: () =>
                                      Navigator.of(dctx)
                                          .pop(nameController.text.trim()),
                                  child: const Text('创建')),
                            ],
                          ),
                        );
                        if (name == null || name.isEmpty) return;
                        setSheet(() => loading = true);
                        var ok = false;
                        try {
                          ok = await mirror.createAccountPlaylist(name);
                        } catch (_) {
                          ok = false;
                        }
                        if (ok) {
                          await load();
                          // 新建后自动添加该作品。
                          try {
                            final pls = playlists;
                            if (pls.isNotEmpty) {
                              final id = _plId(pls.first);
                              if (id != null) {
                                await mirror.addWorkToAccountPlaylist(id, workId);
                                added = true;
                              }
                            }
                          } catch (_) {}
                        }
                        if (ctx.mounted) {
                          setSheet(() {});
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              content: Text(ok ? '已新建并添加' : '创建失败'),
                              duration: const Duration(seconds: 3)));
                        }
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('新建'),
                    ),
                  ],
                ),
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (error)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('拉取播放列表失败',
                            style:
                                TextStyle(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                            onPressed: () async {
                              setSheet(() => loading = true);
                              await load();
                              if (ctx.mounted) setSheet(() {});
                            },
                            child: const Text('重试')),
                      ],
                    ),
                  ),
                )
              else if (playlists.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text('账号暂无播放列表，点右上「新建」创建一个',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, i) {
                      final pl = playlists[i];
                      final id = _plId(pl);
                      final name =
                          (pl['name'] ?? pl['title'] ?? '未命名') as String;
                      final count = _plCount(pl);
                      return ListTile(
                        dense: true,
                        leading: Icon(Icons.queue_music,
                            size: 20, color: scheme.primary),
                        title: Text(name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: count != null
                            ? Text('$count 个作品',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant))
                            : null,
                        trailing: IconButton(
                          icon: Icon(Icons.playlist_add,
                              size: 20, color: scheme.primary),
                          tooltip: '添加 $workTitle',
                          onPressed: id == null
                              ? null
                              : () async {
                                  var ok = false;
                                  try {
                                    ok = await mirror.addWorkToAccountPlaylist(
                                        id, workId);
                                  } catch (_) {
                                    ok = false;
                                  }
                                  if (!ctx.mounted) return;
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                          content: Text(ok
                                              ? '已添加到「$name」'
                                              : '添加失败'),
                                          duration: const Duration(seconds: 2)));
                                  if (ok) {
                                    added = true;
                                    setSheet(() {});
                                  }
                                },
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                        },
                      );
                    },
                  ),
                ),
              if (playlists.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(UiSpacing.small),
                  child: Text('点右侧图标把「$workTitle」加入所选列表',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                ),
            ],
          ),
        ),
      );
    },
  );
  return added;
}

String? _plId(Map<String, dynamic> pl) {
  final raw = pl['id'] ?? pl['playlist_id'] ?? pl['playlistId'];
  return raw == null ? null : raw.toString();
}

int? _plCount(Map<String, dynamic> pl) {
  final raw = pl['work_count'] ??
      pl['workCount'] ??
      pl['count'] ??
      (pl['works'] is List ? (pl['works'] as List).length : null);
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}
