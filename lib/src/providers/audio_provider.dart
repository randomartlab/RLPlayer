import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' show PlayerState;

import '../models/audio_track.dart';
import '../services/audio_player_service.dart';

/// 播放状态提供者（provider/ChangeNotifier 版，对齐 KikoFlu audio_provider 职责）。
///
/// M1 范围：当前音轨、播放/暂停、进度流、seek、上一曲/下一曲、迷你播放条可见性。
class AudioPlayerProvider extends ChangeNotifier {
  final AudioPlayerHandler handler;

  AudioPlayerProvider(this.handler) {
    _currentTrack = handler.currentTrack;
    _isPlaying = handler.player.playing;

    _subscriptions.addAll([
      handler.player.playerStateStream.listen((state) {
        _currentTrack = handler.currentTrack;
        _isPlaying = state.playing;
        notifyListeners();
      }),
      handler.player.currentIndexStream.listen((_) {
        _currentTrack = handler.currentTrack;
        notifyListeners();
      }),
    ]);
  }

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  AudioTrack? _currentTrack;
  bool _isPlaying = false;

  /// 迷你播放条可见性：用户下滑关闭后隐藏，新音轨载入时自动重新显示。
  bool _miniPlayerVisible = true;

  AudioTrack? get currentTrack => _currentTrack;

  bool get isPlaying => _isPlaying;

  bool get miniPlayerVisible => _miniPlayerVisible;

  /// 进度流（Mini Player / 播放器直接订阅，避免每 tick 重建整棵树）。
  Stream<Duration> get positionStream => handler.player.positionStream;

  Stream<Duration?> get durationStream => handler.player.durationStream;

  Stream<PlayerState> get playerStateStream => handler.player.playerStateStream;

  /// 进度条拖动 / seek 联动事件流：统一"定位到时刻 t"入口的触发源。
  final StreamController<Duration> _seekEvents =
      StreamController<Duration>.broadcast();

  Stream<Duration> get seekEvents => _seekEvents.stream;

  Future<void> playTracks(List<AudioTrack> tracks, {int initialIndex = 0}) async {
    _miniPlayerVisible = true;
    notifyListeners();
    await handler.playTracks(tracks, initialIndex: initialIndex);
  }

  Future<void> play() => handler.play();

  Future<void> pause() => handler.pause();

  Future<void> seek(Duration position) {
    _seekEvents.add(position);
    return handler.seek(position);
  }

  Future<void> skipToNext() => handler.skipToNext();

  Future<void> skipToPrevious() => handler.skipToPrevious();

  /// 迷你播放条下滑关闭：停止播放并移除通知栏（PRD §5.3）。
  Future<void> dismissMiniPlayer() async {
    _miniPlayerVisible = false;
    notifyListeners();
    await handler.stop();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _seekEvents.close();
    super.dispose();
  }
}
