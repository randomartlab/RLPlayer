import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';

import '../models/audio_track.dart';
import '../models/lyric.dart';
import '../providers/audio_provider.dart';
import '../services/scan_rules.dart';
import '../services/subtitle_parser.dart';
import '../utils/ui_tokens.dart';
import '../widgets/player/lyric_view.dart';
import '../widgets/player/playlist_dialog.dart';

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
  // 全局歌词控制器（provider 持有，悬浮歌词共用）。
  LyricController get _lyricController => audioProvider.lyricController;
  AudioPlayerProvider get audioProvider =>
      context.read<AudioPlayerProvider>();
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
    super.dispose();
  }

  Future<void> _loadLyricsForCurrentTrack() async {
    final track = context.read<AudioPlayerProvider>().currentTrack;
    final lyricPath = track?.lyricPath;

    // 字幕/歌词三级降级：本地 lrc → 本地 vtt/srt → 在线字幕 URL。
    if (lyricPath == null) {
      final subtitlePath = track?.subtitlePath;
      if (subtitlePath != null) {
        try {
          final text = await File(subtitlePath).readAsString();
          if (mounted) {
            setState(() => _lyricController.lyrics = parseVttOrSrt(text));
          }
        } catch (_) {
          _lyricController.lyrics = null;
        }
        return;
      }
      final subtitleUrl = track?.subtitleUrl;
      if (subtitleUrl != null) {
        try {
          final response = await Dio().get<String>(subtitleUrl);
          final text = response.data;
          final parsed = text == null ? null : parseVttOrSrt(text);
          if (mounted) setState(() => _lyricController.lyrics = parsed);
        } catch (_) {
          if (mounted) setState(() => _lyricController.lyrics = null);
        }
      } else {
        _lyricController.lyrics = null;
      }
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
          // 循环模式（PRD §5.6.3 三态）。
          IconButton(
            icon: _loopModeIcon(audio.loopMode),
            tooltip: _loopModeLabel(audio.loopMode),
            onPressed: () {
              audio.cycleLoopMode();
              setState(() {});
            },
          ),
          // 倍速。
          TextButton(
            onPressed: () => showSpeedSheet(context),
            child: Text('${audio.speed.toStringAsFixed(2)}×',
                style: const TextStyle(fontSize: 14)),
          ),
          // 播放队列（PRD §5.6.5）。
          IconButton(
            icon: const Icon(Icons.queue_music),
            tooltip: '播放队列',
            onPressed: () => showPlaylistDialog(context),
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
                      onSeekTo: (position) =>
                          unawaited(audio.seek(position)),
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
            : track?.artworkUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(UiRadii.card),
                    child: CachedNetworkImage(
                      imageUrl: track!.artworkUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const SizedBox.shrink(),
                      errorWidget: (context, url, error) => Center(
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
              icon: const Icon(Icons.lyrics_outlined),
              iconSize: UiIconSize.standard,
              tooltip: '悬浮桌面歌词',
              onPressed: () => _toggleFloatingLyric(context, audio),
            ),
            IconButton(
              icon: Icon(
                audio.sleepAt != null
                    ? Icons.bedtime
                    : Icons.bedtime_outlined,
                color: audio.sleepAt != null
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              iconSize: UiIconSize.standard,
              tooltip: '睡眠定时',
              onPressed: () => showSleepTimerSheet(context),
            ),
          ],
        ),
      ],
    );
  }

  Widget _loopModeIcon(LoopMode mode) {
    return switch (mode) {
      LoopMode.all => const Icon(Icons.repeat),
      LoopMode.one => const Icon(Icons.repeat_one),
      LoopMode.off => Icon(Icons.repeat,
          color: Theme.of(context).disabledColor),
    };
  }

  String _loopModeLabel(LoopMode mode) => switch (mode) {
        LoopMode.all => '列表循环',
        LoopMode.one => '单曲循环',
        LoopMode.off => '循环关闭',
      };

  /// 悬浮桌面歌词开关（PRD §5.6.7：默认关，首次开启引导授权）。
  Future<void> _toggleFloatingLyric(
      BuildContext context, AudioPlayerProvider audio) async {
    final messenger = ScaffoldMessenger.of(context);
    if (audio.floatingLyric.showing) {
      await audio.floatingLyric.hide();
      messenger.showSnackBar(const SnackBar(
          content: Text('悬浮歌词已关闭'),
          duration: Duration(seconds: 2)));
      return;
    }
    final ok = await audio.floatingLyric.show();
    if (!mounted) return;
    if (ok) {
      // 立即推送当前行。
      unawaited(audio.floatingLyric
          .pushLyric(audio.lyricController.activeText));
      messenger.showSnackBar(const SnackBar(
          content: Text('悬浮歌词已开启（可拖动，点击穿透）'),
          duration: Duration(seconds: 2)));
    } else {
      messenger.showSnackBar(const SnackBar(
          content: Text('需要「显示在其他应用上层」权限，请在系统设置中授予后重试'),
          duration: Duration(seconds: 4)));
    }
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

