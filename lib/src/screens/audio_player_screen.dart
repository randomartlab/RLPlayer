import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/audio_track.dart';
import '../models/lyric.dart';
import '../providers/audio_provider.dart';
import '../services/scan_rules.dart';
import '../utils/ui_tokens.dart';
import '../widgets/player/lyric_view.dart';

/// 全屏播放器（KikoFlu `audio_player_screen.dart` Android 版骨架，PRD §5.6）。
///
/// M1 范围：大封面（0.4 屏高）、进度条（带时间气泡）、基础控制、
/// 歌词视图与 **seek 联动**、沉浸锁定模式。
/// 倍速 / 循环 / 睡眠定时 / 播放队列 / 悬浮字幕随 M5 补齐。
class AudioPlayerScreen extends StatefulWidget {
  const AudioPlayerScreen({super.key});

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  final LyricController _lyricController = LyricController();
  final LyricPreviewThrottle _previewThrottle = LyricPreviewThrottle();
  final List<StreamSubscription<Duration?>> _durationSubs = [];
  StreamSubscription<Duration>? _positionSub;

  bool _showLyrics = false;
  bool _immersive = false;
  bool _isDragging = false;
  double _dragValue = 0.0;
  Duration _position = Duration.zero;
  Duration? _duration;
  String? _lyricsTrackId;

  @override
  void initState() {
    super.initState();
    _loadLyricsForCurrentTrack();
    final audio = context.read<AudioPlayerProvider>();
    _positionSub = audio.positionStream.listen((position) {
      if (mounted && !_isDragging) {
        setState(() => _position = position);
      }
    });
    _durationSubs.add(audio.durationStream.listen((duration) {
      if (mounted && duration != null) {
        setState(() => _duration = duration);
      }
    }));
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    for (final sub in _durationSubs) {
      sub.cancel();
    }
    _lyricController.dispose();
    super.dispose();
  }

  Future<void> _loadLyricsForCurrentTrack() async {
    final track = context.read<AudioPlayerProvider>().currentTrack;
    final lyricPath = track?.lyricPath;
    if (lyricPath == null) {
      _lyricController.lyrics = null;
      return;
    }
    try {
      // 编码嗅探：UTF-8 → Shift-JIS → GBK（PRD §5.9.2）。
      final bytes = lyricPath.startsWith('asset:')
          ? (await rootBundle.load(lyricPath.substring('asset:'.length)))
              .buffer
              .asInt8List()
          : await File(lyricPath).readAsBytes();
      final content = decodeTextWithFallback(bytes);
      _lyricController.lyrics =
          content == null ? null : Lyrics.parse(content);
    } catch (_) {
      _lyricController.lyrics = null;
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _seekToFraction(double fraction) {
    final audio = context.read<AudioPlayerProvider>();
    final dur = _duration;
    if (dur == null || dur.inMilliseconds <= 0) return;
    unawaited(
      audio.seek(Duration(milliseconds: (fraction * dur.inMilliseconds).round())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioPlayerProvider>();
    final track = audio.currentTrack;
    final scheme = Theme.of(context).colorScheme;

    // 换曲时重新加载歌词（本地同名 lrc 关联，M2 起由识别引擎提供）。
    if (track?.id != _lyricsTrackId) {
      _lyricsTrackId = track?.id;
      _loadLyricsForCurrentTrack();
    }

    // 沉浸模式：隐藏全部控件，只留封面；再点按恢复（PRD §4.6）。
    if (_immersive) {
      return Scaffold(
        backgroundColor: scheme.surface,
        body: GestureDetector(
          onTap: () => setState(() => _immersive = false),
          child: Center(child: _buildCover(context, track)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music),
            tooltip: '播放队列',
            onPressed: () {}, // M5：播放队列弹窗
          ),
        ],
      ),
      body: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
            final isLandscape = orientation == Orientation.landscape;
            if (isLandscape) {
              // 横屏：左右分栏 flex 2:3（左封面 / 右歌词区，PRD §5.6.1）。
              return Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: _buildCover(context, track, constrained: false),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: _buildContentColumn(
                      context,
                      audio,
                      track,
                      compactControls: true,
                    ),
                  ),
                ],
              );
            }
            return _buildContentColumn(context, audio, track);
          },
        ),
      ),
    );
  }

  Widget _buildContentColumn(
    BuildContext context,
    AudioPlayerProvider audio,
    AudioTrack? track, {
    bool compactControls = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: UiSpacing.xLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: UiMotion.primary,
              child: _showLyrics
                  ? LyricView(
                      key: const ValueKey('lyrics'),
                      controller: _lyricController,
                      positionStream: audio.positionStream,
                      seekEventStream: audio.seekEvents,
                    )
                  : KeyedSubtree(
                      key: const ValueKey('cover'),
                      child: Center(
                        child: _buildCover(
                          context,
                          track,
                          maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                        ),
                      ),
                    ),
            ),
          ),
          // 标题区：本地音轨名自适应换行完整显示（PRD §4.7：无 ellipsis）。
          Text(
            track?.title ?? '未在播放',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
            maxLines: null,
            overflow: TextOverflow.visible,
          ),
          if (track?.artist != null) ...[
            const SizedBox(height: UiSpacing.xSmall),
            Text(
              track!.artist!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: UiSpacing.medium),
          _buildProgressBar(context, audio),
          const SizedBox(height: UiSpacing.medium),
          _buildControls(context, audio, compact: compactControls),
          SizedBox(
              height: MediaQuery.paddingOf(context).bottom + UiSpacing.large),
        ],
      ),
    );
  }

  /// 大封面：maxWidth = 屏宽 − 48dp；maxHeight = 屏高 × 0.4；圆角 16dp。
  /// 点按切换歌词视图；长按进入沉浸锁定模式（PRD §4.6）。
  Widget _buildCover(
    BuildContext context,
    AudioTrack? track, {
    double? maxHeight,
    bool constrained = true,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;

    Widget cover = AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(UiRadii.card),
          color: scheme.primaryContainer,
        ),
        child: track?.artworkPath != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(UiRadii.card),
                child: Image.file(
                  File(track!.artworkPath!),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Text(
                      track.id,
                      style: TextStyle(color: scheme.onPrimaryContainer),
                    ),
                  ),
                ),
              )
            : Center(
                // 占位封面：主题色 primaryContainer 渐变 + 作品号文字（PRD §5.5）。
                child: Text(
                  track?.id ?? '',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: scheme.onPrimaryContainer),
                ),
              ),
      ),
    );

    var constraints = BoxConstraints(
      maxWidth: constrained ? mediaQuery.size.width - 48 : double.infinity,
    );
    if (maxHeight != null) {
      constraints = constraints.copyWith(maxHeight: maxHeight);
    }

    return GestureDetector(
      onTap: () => setState(() => _showLyrics = !_showLyrics),
      onLongPress: () => setState(() => _immersive = true),
      child: Hero(
        tag: 'audio_player_artwork_${track?.id ?? 'none'}',
        child: ConstrainedBox(constraints: constraints, child: cover),
      ),
    );
  }

  /// 进度条：可拖拽 seek，带时间气泡；拖动中歌词实时预览（节流 50ms）。
  Widget _buildProgressBar(BuildContext context, AudioPlayerProvider audio) {
    final scheme = Theme.of(context).colorScheme;
    final displayPosition = _dragPosition();

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: scheme.primary,
            inactiveTrackColor: scheme.onSurfaceVariant.withValues(alpha: 0.24),
            thumbColor: scheme.primary,
            overlayColor: scheme.primary.withValues(alpha: 0.1),
          ),
          child: Slider(
            value: displayPosition.inMilliseconds.toDouble().clamp(
                  0,
                  (_duration ?? const Duration(seconds: 1))
                      .inMilliseconds
                      .toDouble(),
                ),
            max: (_duration ?? const Duration(seconds: 1))
                .inMilliseconds
                .toDouble(),
            onChanged: (value) {
              setState(() {
                _isDragging = true;
                _dragValue = value;
              });
              // 拖动中歌词实时预览（≤ 50ms/次，PRD §5.6.4）。
              if (_previewThrottle.shouldUpdate()) {
                _lyricController
                    .locateTo(Duration(milliseconds: value.round()));
              }
            },
            onChangeEnd: (value) {
              _seekToFraction(
                value / (_duration?.inMilliseconds ?? 1),
              );
              setState(() => _isDragging = false);
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(displayPosition),
              style: UiTextStyles.supporting
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            Text(
              _formatDuration(_duration ?? Duration.zero),
              style: UiTextStyles.supporting
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }

  Duration _dragPosition() {
    final dur = _duration;
    if (!_isDragging || dur == null || dur.inMilliseconds <= 0) {
      return _position;
    }
    return Duration(milliseconds: _dragValue.round());
  }

  Widget _buildControls(
    BuildContext context,
    AudioPlayerProvider audio, {
    bool compact = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final iconSize = compact ? UiIconSize.large : 48.0;
    final playButtonSize = compact ? 64.0 : 72.0;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: iconSize,
              icon: const Icon(Icons.replay_10),
              onPressed: () => _skipBy(audio, const Duration(seconds: -10)),
            ),
            SizedBox(width: UiSpacing.large),
            IconButton(
              iconSize: iconSize,
              icon: const Icon(Icons.skip_previous),
              onPressed: audio.skipToPrevious,
            ),
            SizedBox(width: UiSpacing.large),
            // 播放主按钮：竖屏 72dp 圆形 primary 背景（横屏 64dp）。
            SizedBox(
              width: playButtonSize,
              height: playButtonSize,
              child: FloatingActionButton(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                elevation: 0,
                onPressed: () =>
                    audio.isPlaying ? audio.pause() : audio.play(),
                child: Icon(
                  audio.isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 32,
                ),
              ),
            ),
            SizedBox(width: UiSpacing.large),
            IconButton(
              iconSize: iconSize,
              icon: const Icon(Icons.skip_next),
              onPressed: audio.skipToNext,
            ),
            SizedBox(width: UiSpacing.large),
            IconButton(
              iconSize: iconSize,
              icon: const Icon(Icons.forward_10),
              onPressed: () => _skipBy(audio, const Duration(seconds: 10)),
            ),
          ],
        ),
        // 悬浮字幕开关 / 睡眠定时占位（M5 完整实现）。
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.subtitles_outlined),
              iconSize: UiIconSize.standard,
              tooltip: '悬浮字幕',
              onPressed: () {}, // M5：悬浮字幕
            ),
            IconButton(
              icon: const Icon(Icons.bedtime_outlined),
              iconSize: UiIconSize.standard,
              tooltip: '睡眠定时',
              onPressed: () {}, // M5：睡眠定时
            ),
          ],
        ),
      ],
    );
  }

  /// 快退 / 快进固定 10 秒（PRD §5.6.3）；走 seek 统一入口联动歌词。
  void _skipBy(AudioPlayerProvider audio, Duration delta) {
    var targetMs = _position.inMilliseconds + delta.inMilliseconds;
    final maxMs = _duration?.inMilliseconds ?? 0;
    if (targetMs < 0) targetMs = 0;
    if (targetMs > maxMs) targetMs = maxMs;
    unawaited(audio.seek(Duration(milliseconds: targetMs)));
  }
}

