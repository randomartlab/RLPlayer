import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../models/audio_track.dart';

/// 播放内核服务（KikoFlu 播放组合沿用：just_audio + audio_service）。
///
/// M1 范围：单曲/队列播放、进度、seek、上一曲/下一曲；
/// MediaSession 通知栏控制、音频焦点由 audio_service + audio_session 处理。
class AudioPlayerHandler extends BaseAudioHandler {
  final AudioPlayer _player = AudioPlayer();

  /// 自维护的当前曲目索引。
  ///
  /// just_audio 对单文件源（非 ConcatenatingAudioSource）的
  /// currentIndex 始终返回 0——依赖它会导致「点任何音轨都播第一首」
  /// （实机反馈根因 2026-09-02）。
  int _currentIndex = 0;

  /// 当前队列（M1 为内存态；M2 起由本地库/在线模块提供）。
  final List<AudioTrack> _queue = [];

  List<AudioTrack> get tracks => List.unmodifiable(_queue);

  AudioPlayer get player => _player;

  AudioPlayerHandler() {
    _configureAudioSession();
    _notifyPlaybackState();
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    _player.durationStream.listen((duration) {
      final item = mediaItem.valueOrNull;
      if (item != null && duration != null) {
        mediaItem.add(item.copyWith(duration: duration));
      }
    });
    // 自动连播：单文件播完 → 按循环模式切下一首/上一首（PRD §5.6.3）。
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _onTrackCompleted();
      }
    });
  }

  /// 循环模式（PRD §5.6.3：关闭/列表循环/单曲循环）。
  LoopMode _loopMode = LoopMode.off;
  LoopMode get loopMode => _loopMode;

  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;
    await _player.setLoopMode(mode);
  }

  void _onTrackCompleted() {
    if (_queue.isEmpty) return;
    switch (_loopMode) {
      case LoopMode.one:
        // 单曲循环：just_audio LoopMode.one 已自动重播；此处兜底。
        _loadIndex(_currentIndex, autoPlay: true);
      case LoopMode.all:
        final next = _currentIndex + 1;
        if (next < _queue.length) {
          _loadIndex(next, autoPlay: true);
        } else {
          _loadIndex(0, autoPlay: true); // 列表循环回开头。
        }
      case LoopMode.off:
        final next = _currentIndex + 1;
        if (next < _queue.length) {
          _loadIndex(next, autoPlay: true);
        }
        // 播完最后一首停止（不循环）。
    }
  }

  /// 队列重排（播放队列弹窗拖拽排序，PRD §5.6.5）。
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _queue.length ||
        _queue.isEmpty) {
      return;
    }
    // onReorderItem 已对移除项自动修正 newIndex。
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex.clamp(0, _queue.length), item);
    // 若当前曲被移动，校正 currentIndex（just_audio 索引不变，仍指向当前文件）。
    _notifyPlaybackState();
  }

  /// 队列删除（左滑删除）。
  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final isCurrent = index == _currentIndex;
    _queue.removeAt(index);
    if (_queue.isEmpty) {
      await stop();
      return;
    }
    if (isCurrent) {
      await _loadIndex(index.clamp(0, _queue.length - 1), autoPlay: true);
    }
    _notifyPlaybackState();
  }

  /// 显式配置音频会话（部分模拟器需要明确的 usage 路由才创建 AudioTrack）。
  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {
      // 配置失败不阻塞播放。
    }
  }

  /// 把 just_audio 播放事件转成 audio_service PlaybackState（通知栏控制源）。
  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _currentIndex,
    );
  }

  void _notifyPlaybackState() {
    final track = currentTrack;
    if (track == null) {
      mediaItem.add(null);
    } else {
      mediaItem.add(MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist,
        duration: _player.duration,
      ));
    }
  }

  /// 设置队列并从 [initialIndex] 开始播放。
  Future<void> playTracks(List<AudioTrack> tracks, {int initialIndex = 0}) async {
    _queue
      ..clear()
      ..addAll(tracks);
    await _loadIndex(initialIndex, autoPlay: true);
  }

  Future<void> _loadIndex(int index, {required bool autoPlay}) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    final track = _queue[index];

    final source = _sourceFor(track);
    await _player.setAudioSource(source);
    _notifyPlaybackState();
    if (autoPlay) {
      await _player.play();
    }
  }

  AudioSource _sourceFor(AudioTrack track) {
    final source = track.source;
    if (source.startsWith('asset:')) {
      return AudioSource.asset(source.substring('asset:'.length));
    }
    if (source.startsWith('http://') || source.startsWith('https://')) {
      return AudioSource.uri(Uri.parse(source));
    }
    return AudioSource.file(source);
  }

  AudioTrack? get currentTrack {
    return _queue.isNotEmpty && _currentIndex < _queue.length
        ? _queue[_currentIndex]
        : null;
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    _queue.clear();
    _currentIndex = 0;
    _notifyPlaybackState();
  }

  @override
  Future<void> skipToNext() async {
    final index = _currentIndex + 1;
    if (index >= _queue.length) return;
    await _loadIndex(index, autoPlay: _player.playing);
  }

  @override
  Future<void> skipToPrevious() async {
    // 播放超过 3 秒时回到本曲开头（常见播放器惯例，与原版一致）。
    if (_player.position.inSeconds >= 3) {
      await _player.seek(Duration.zero);
      return;
    }
    final index = _currentIndex - 1;
    if (index < 0) {
      await _player.seek(Duration.zero);
      return;
    }
    await _loadIndex(index, autoPlay: _player.playing);
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);
}
