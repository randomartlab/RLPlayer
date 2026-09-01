import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/audio_track.dart';
import '../providers/audio_provider.dart';
import '../utils/ui_tokens.dart';

/// Tab1 作品页（M1 骨架：顶部「本地 / 在线」双源切换 + 空态 + 演示播放入口）。
///
/// M2 起本地视图接入本地识别引擎与瀑布流封面墙（M3）；
/// M3 起在线视图接入 asmr.one 在线模块（M12）。
class WorksScreen extends StatefulWidget {
  const WorksScreen({super.key});

  @override
  State<WorksScreen> createState() => _WorksScreenState();
}

class _WorksScreenState extends State<WorksScreen> {
  int _sourceIndex = 0; // 0 = 本地（默认），1 = 在线

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('作品', style: UiTextStyles.pageTitle),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: UiSpacing.large,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('本地')),
                  ButtonSegment(value: 1, label: Text('在线')),
                ],
                selected: {_sourceIndex},
                onSelectionChanged: (selection) {
                  setState(() => _sourceIndex = selection.first);
                },
              ),
            ),
          ),
          Expanded(
            child: _sourceIndex == 0 ? _buildLocalBody(context) : _buildOnlineBody(context),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_music_outlined,
              size: 64, color: scheme.onSurfaceVariant),
          const SizedBox(height: UiSpacing.medium),
          Text(
            '本地作品库为空',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: UiSpacing.xSmall),
          Text(
            'M2 里程碑开放扫描根目录导入本地作品',
            style: UiTextStyles.supporting
                .copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: UiSpacing.large),
          // M1 端到端播放链路演示入口。
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('演示播放（M1 播放链路验证）'),
            onPressed: _playDemoTrack,
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 64, color: scheme.onSurfaceVariant),
          const SizedBox(height: UiSpacing.medium),
          Text(
            '在线模块（M3 里程碑）',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: UiSpacing.xSmall),
          Text(
            'asmr.one 在线浏览 / 流播 / 下载将在此视图接入',
            style: UiTextStyles.supporting
                .copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Future<void> _playDemoTrack() async {
    final audio = context.read<AudioPlayerProvider>();
    await audio.playTracks([
      const AudioTrack(
        id: 'demo_track_01',
        title: '演示音轨 - 歌词 seek 联动验证',
        artist: 'KikoLocal M1',
        source: 'asset:assets/demo/demo_track.m4a',
        lyricPath: 'asset:assets/demo/demo_track.lrc',
      ),
    ]);
  }
}
