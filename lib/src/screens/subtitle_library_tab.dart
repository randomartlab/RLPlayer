import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/work.dart';
import '../providers/audio_provider.dart';
import '../providers/library_provider.dart';
import '../utils/playback_helpers.dart';
import '../utils/ui_tokens.dart';
import 'audio_player_screen.dart';

/// 字幕库（M7 SubtitleLibrary，PRD §5.8 / 原版 subtitle_library 布局）：
/// 全库已关联歌词（lrc）/字幕（vtt·srt）的音轨清单，点击定位播放。
class SubtitleLibraryTab extends StatefulWidget {
  const SubtitleLibraryTab({super.key});

  @override
  State<SubtitleLibraryTab> createState() => _SubtitleLibraryTabState();
}

class _SubtitleLibraryTabState extends State<SubtitleLibraryTab> {
  bool _loading = true;

  /// 作品 → 该作品中带歌词/字幕的音轨节点。
  final List<(Work, List<FileNode>)> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final library = context.read<LibraryProvider>();
    final entries = <(Work, List<FileNode>)>[];
    for (final work in library.works) {
      final nodes = await library.nodesOf(work);
      final withSub = nodes
          .where((n) =>
              !n.isDirectory &&
              (n.lyricPath != null || n.subtitlePath != null))
          .toList();
      if (withSub.isNotEmpty) entries.add((work, withSub));
    }
    if (mounted) {
      setState(() {
        _entries
          ..clear()
          ..addAll(entries);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_entries.isEmpty) {
      return Center(
        child: Text(
          '本地库暂无已关联的歌词/字幕文件',
          style: UiTextStyles.supporting
              .copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final (work, tracks) = _entries[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              dense: true,
              leading: Icon(Icons.library_music, color: scheme.primary),
              title: Text(work.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${work.rjCode ?? '本地'} · ${tracks.length} 条字幕'),
            ),
            for (final track in tracks)
              ListTile(
                dense: true,
                contentPadding:
                    const EdgeInsets.only(left: UiSpacing.xLarge),
                leading: Icon(
                  track.lyricPath != null
                      ? Icons.lyrics_outlined
                      : Icons.subtitles_outlined,
                  size: 18,
                  color: scheme.tertiary,
                ),
                title: Text(track.displayName,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _playTrack(work, track),
              ),
            const Divider(height: 1),
          ],
        );
      },
    );
  }

  /// 定位播放：该作品队列中跳到此音轨。
  Future<void> _playTrack(Work work, FileNode target) async {
    final library = context.read<LibraryProvider>();
    final audio = context.read<AudioPlayerProvider>();
    final nodes = await library.nodesOf(work);
    final tracks = tracksOf(work, nodes);
    final index = tracks.indexWhere((t) => t.id == 'node_${target.id}');
    if (index < 0) return;
    await audio.playTracks(tracks, initialIndex: index);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'AudioPlayer'),
          builder: (context) => const AudioPlayerScreen()),
    );
  }
}
