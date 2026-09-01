import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' show LoopMode, PlayerState;

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

  /// 当前音轨时长（同步读，历史记录用）。
  Duration? get duration => handler.player.duration;

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

  /// 立即反馈：currentTrack/迷你播放条先就位，音源加载后台进行（零感知延迟）。
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

  // ---- M5：倍速 / 循环 / 睡眠定时 / 队列 ----

  double get speed => handler.player.speed;

  LoopMode get loopMode => handler.loopMode;

  Future<void> setSpeed(double value) => handler.setSpeed(value);

  Future<void> cycleLoopMode() {
    final next = switch (handler.loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    return handler.setLoopMode(next);
  }

  List<AudioTrack> get queue => handler.tracks;

  int get currentIndex => handler.player.currentIndex ?? 0;

  Future<void> jumpTo(int index) async {
    await handler.playTracks(handler.tracks, initialIndex: index);
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) =>
      handler.reorderQueue(oldIndex, newIndex);

  Future<void> removeFromQueue(int index) => handler.removeAt(index);

  /// 睡眠定时（PRD §5.6.6）：时长模式 + 指定时刻模式 + 取消。
  Timer? _sleepTimer;
  DateTime? _sleepAt;

  /// 到点时刻（展示用）；null = 未设置。
  DateTime? get sleepAt => _sleepAt;

  /// 时长模式：[minutes] 分钟后淡出停止。
  void setSleepTimerMinutes(int minutes) {
    _sleepTimer?.cancel();
    _sleepAt = DateTime.now().add(Duration(minutes: minutes));
    _sleepTimer = Timer(Duration(minutes: minutes), _onSleepTimeout);
    notifyListeners();
  }

  /// 指定时刻模式：24 小时制 [hour]:[minute] 到点停止。
  void setSleepTimerAt(int hour, int minute) {
    _sleepTimer?.cancel();
    var target = DateTime(
        DateTime.now().year, DateTime.now().month, DateTime.now().day,
        hour, minute);
    if (!target.isAfter(DateTime.now())) {
      target = target.add(const Duration(days: 1)); // 已过时刻 → 明天。
    }
    _sleepAt = target;
    _sleepTimer = Timer(target.difference(DateTime.now()), _onSleepTimeout);
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepAt = null;
    notifyListeners();
  }

  /// 到点淡出停止（PRD 验收：睡眠定时到点淡出停止播放）。
  Future<void> _onSleepTimeout() async {
    _sleepTimer = null;
    _sleepAt = null;
    // 3 秒淡出后暂停。
    const steps = 10;
    for (var i = steps; i >= 1; i--) {
      await handler.player.setVolume(i / steps);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    await pause();
    await handler.player.setVolume(1.0); // 恢复音量供下次播放。
    notifyListeners();
  }

  /// 迷你播放条下滑关闭：停止播放并移除通知栏（PRD §5.3）。
  Future<void> dismissMiniPlayer() async {
    _miniPlayerVisible = false;
    notifyListeners();
    await handler.stop();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _seekEvents.close();
    super.dispose();
  }
}
