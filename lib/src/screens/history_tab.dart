import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/audio_provider.dart';
import '../providers/library_provider.dart';
import '../services/history_service.dart';
import '../utils/playback_helpers.dart';
import '../utils/ui_tokens.dart';
import 'audio_player_screen.dart';

/// 播放历史（M7 首版，PRD §5.8）：断点续播 + 左滑删除 + 一键清空。
class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  List<HistoryEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<LibraryProvider>().database;
    if (db == null) return;
    final entries = await db.queryHistory();
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  /// 断点续播：重建作品队列 → 定位音轨 → seek 到断点（PRD 验收：精度 ≤ 1s）。
  Future<void> _resume(HistoryEntry entry) async {
    final workId = entry.workId;
    if (workId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('该记录来自在线播放，暂不支持续播'),
            duration: Duration(seconds: 2)),
      );
      return;
    }
    final library = context.read<LibraryProvider>();
    final audio = context.read<AudioPlayerProvider>();
    final work = library.works.where((w) => w.id == workId).firstOrNull;
    if (work == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('作品已不在本地库中'), duration: Duration(seconds: 2)),
      );
      return;
    }
    final nodes = await library.nodesOf(work);
    final tracks = tracksOf(work, nodes);
    final index =
        tracks.indexWhere((t) => t.id == entry.trackKey).clamp(0, tracks.length - 1);
    await audio.playTracks(tracks, initialIndex: index);
    if (entry.positionMs > 1000) {
      unawaited(audio.seek(Duration(milliseconds: entry.positionMs)));
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const AudioPlayerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_entries.isEmpty) {
      return Center(
        child: Text(
          '暂无播放记录',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }

    return Stack(
      children: [
        ListView.builder(
          itemCount: _entries.length,
          itemBuilder: (context, index) {
            final entry = _entries[index];
            return Dismissible(
              key: Key(entry.trackKey),
              direction: DismissDirection.endToStart,
              background: Container(
                color: scheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: UiSpacing.large),
                child: Icon(Icons.delete_outline,
                    color: scheme.onErrorContainer),
              ),
              onDismissed: (_) async {
                await context
                    .read<LibraryProvider>()
                    .database
                    ?.deleteHistory(entry.trackKey);
                setState(() => _entries.removeAt(index));
              },
              child: ListTile(
                leading: _cover(entry),
                title: Text(entry.trackTitle,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.workTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: UiTextStyles.supporting),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                        value: entry.progress, minHeight: 3),
                  ],
                ),
                trailing: Text(
                  _timeAgo(entry.updatedAt),
                  style: UiTextStyles.supporting
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
                onTap: () => unawaited(_resume(entry)),
              ),
            );
          },
        ),
        // 一键清空（右下角）。
        Positioned(
          right: UiSpacing.medium,
          bottom: UiSpacing.medium,
          child: FloatingActionButton.small(
            onPressed: () async {
              await context
                  .read<LibraryProvider>()
                  .database
                  ?.clearHistory();
              _load();
            },
            tooltip: '清空历史',
            child: const Icon(Icons.delete_sweep_outlined),
          ),
        ),
      ],
    );
  }

  Widget _cover(HistoryEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    Widget child;
    if (entry.coverPath != null) {
      child = Image.file(File(entry.coverPath!),
          width: 48, height: 48, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Icon(Icons.album,
              color: scheme.onSurfaceVariant));
    } else if (entry.artworkUrl != null) {
      child = CachedNetworkImage(
          imageUrl: entry.artworkUrl!,
          width: 48, height: 48, fit: BoxFit.cover,
          errorWidget: (_, _, _) => Icon(Icons.album,
              color: scheme.onSurfaceVariant));
    } else {
      child = Icon(Icons.album, color: scheme.onSurfaceVariant);
    }
    return SizedBox(
      width: 48,
      height: 48,
      child: ClipRRect(
          borderRadius: BorderRadius.circular(UiRadii.control),
          child: child),
    );
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}
