import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:provider/provider.dart';

import '../providers/audio_provider.dart';
import '../screens/audio_player_screen.dart';
import '../utils/ui_tokens.dart';

/// 迷你播放条（KikoFlu `mini_player.dart` Android 版移植，PRD §5.3）。
///
/// - 高度 72dp（无歌词行）/ 88dp（带歌词行），AnimatedSize 180ms easeOutCubic；
/// - 封面 48×48dp r8，Hero tag 与全屏播放器大封面一致；
/// - 进度条 trackHeight 4dp、thumb 隐藏；
/// - 下滑 Dismissible 关闭（停止播放）；
/// - 进入全屏：400ms 自定义路由 _PlayerPageRoute。
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  bool _isDragging = false;
  double _dragValue = 0.0;
  Duration _position = Duration.zero;
  Duration? _duration;

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioPlayerProvider>();
    final track = audio.currentTrack;
    if (track == null || !audio.miniPlayerVisible) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;

    final playerContent = Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(
            color: scheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: StreamBuilder<Duration>(
        stream: audio.positionStream,
        builder: (context, positionSnapshot) {
          _position = positionSnapshot.data ?? _position;
          return StreamBuilder<Duration?>(
            stream: audio.durationStream,
            builder: (context, durationSnapshot) {
              _duration = durationSnapshot.data ?? _duration;
              final progress = _progressValue();

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 顶部 4dp 进度条：可拖拽 seek（联动歌词的统一入口）。
                  SizedBox(
                    height: 4,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 0,
                          disabledThumbRadius: 0,
                        ),
                        overlayShape: SliderComponentShape.noOverlay,
                        activeTrackColor: scheme.primary,
                        inactiveTrackColor:
                            scheme.outline.withValues(alpha: 0.2),
                      ),
                      child: Slider(
                        value: progress.clamp(0.0, 1.0),
                        onChanged: (value) {
                          setState(() {
                            _isDragging = true;
                            _dragValue = value;
                          });
                        },
                        onChangeEnd: (value) {
                          final dur = _duration;
                          if (dur != null && dur.inMilliseconds > 0) {
                            unawaited(audio.seek(Duration(
                              milliseconds:
                                  (value * dur.inMilliseconds).round(),
                            )));
                          }
                          setState(() => _isDragging = false);
                        },
                      ),
                    ),
                  ),
                  // 主行：封面 + 信息 + 三控制按钮，高度 68dp（72 − 4）。
                  SizedBox(
                    height: 68,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: UiSpacing.large,
                        vertical: UiSpacing.small,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _openFullScreenPlayer(context),
                              child: Row(
                                children: [
                                  _buildArtwork(context, track.artworkPath),
                                  const SizedBox(width: UiSpacing.medium),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          track.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (track.artist != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            track.artist!,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _ControlButton(
                            icon: Icons.skip_previous,
                            iconSize: UiIconSize.large,
                            onTap: audio.skipToPrevious,
                          ),
                          StreamBuilder<PlayerStateData>(
                            stream: audio.playerStateStream.map(
                              (state) => PlayerStateData(
                                playing: state.playing,
                                loading: state.processingState ==
                                    ProcessingState.loading ||
                                    state.processingState ==
                                        ProcessingState.buffering,
                              ),
                            ),
                            initialData: const PlayerStateData(
                              playing: false,
                              loading: false,
                            ),
                            builder: (context, snapshot) {
                              final state = snapshot.data!;
                              if (state.loading) {
                                return const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: Padding(
                                    padding: EdgeInsets.all(2),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  ),
                                );
                              }
                              return _ControlButton(
                                icon: state.playing
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                iconSize: 28,
                                onTap: state.playing
                                    ? audio.pause
                                    : audio.play,
                              );
                            },
                          ),
                          _ControlButton(
                            icon: Icons.skip_next,
                            iconSize: UiIconSize.large,
                            onTap: audio.skipToNext,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );

    return Dismissible(
      key: Key('miniplayer_${track.id}'),
      direction: DismissDirection.down,
      background: Container(color: Colors.transparent),
      onDismissed: (direction) {
        unawaited(audio.dismissMiniPlayer());
      },
      child: playerContent,
    );
  }

  double _progressValue() {
    if (_isDragging) return _dragValue;
    final dur = _duration;
    if (dur == null || dur.inMilliseconds <= 0) return 0.0;
    return _position.inMilliseconds / dur.inMilliseconds;
  }

  Widget _buildArtwork(BuildContext context, String? artworkPath) {
    final scheme = Theme.of(context).colorScheme;
    Widget image = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(UiRadii.control),
        color: scheme.surfaceContainerHighest,
      ),
      child: artworkPath != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(UiRadii.control),
              child: Image.file(
                File(artworkPath),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.album, size: 32),
              ),
            )
          : const Icon(Icons.album, size: 32),
    );

    final track = context.read<AudioPlayerProvider>().currentTrack;
    return Hero(
      tag: 'audio_player_artwork_${track?.id ?? 'none'}',
      child: image,
    );
  }

  void _openFullScreenPlayer(BuildContext context) {
    Navigator.of(context).push(
      _PlayerPageRoute(builder: (context) => const AudioPlayerScreen()),
    );
  }
}

class PlayerStateData {
  final bool playing;
  final bool loading;

  const PlayerStateData({required this.playing, required this.loading});
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.iconSize,
    this.onTap,
  });

  final IconData icon;
  final double iconSize;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap == null ? null : () => onTap!(),
      icon: Icon(icon),
      iconSize: iconSize,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// 迷你播放条 → 全屏播放器路由：400ms 自定义转场
/// （缩放 + 淡入自左下角，KikoFlu `_PlayerPageRoute` 非 iOS 分支）。
class _PlayerPageRoute<T> extends PageRoute<T> {
  _PlayerPageRoute({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return builder(context);
  }

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => UiMotion.playerRoute;

  @override
  Duration get reverseTransitionDuration => UiMotion.playerRoute;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    const curve = UiMotion.entryCurve;
    final scale = Tween<double>(begin: 0.0, end: 1.0)
        .chain(CurveTween(curve: curve))
        .evaluate(animation);
    final opacity = CurveTween(curve: Curves.easeIn).evaluate(animation);
    return Transform.scale(
      scale: scale,
      alignment: Alignment.bottomLeft,
      child: Opacity(opacity: opacity, child: child),
    );
  }
}
