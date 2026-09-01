import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/audio_track.dart';

/// 播放内核服务（KikoFlu 播放组合沿用：just_audio + audio_service）。
///
/// M1 范围：单曲/队列播放、进度、seek、上一曲/下一曲；
/// MediaSession 通知栏控制、音频焦点由 audio_service + audio_session 处理。
class AudioPlayerHandler extends BaseAudioHandler {
  final AudioPlayer _player = AudioPlayer();

  /// 当前队列（M1 为内存态；M2 起由本地库/在线模块提供）。
  final List<AudioTrack> _queue = [];

  List<AudioTrack> get tracks => List.unmodifiable(_queue);

  AudioPlayer get player => _player;

  AudioPlayerHandler() {
    _notifyPlaybackState();
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    _player.durationStream.listen((duration) {
      final item = mediaItem.valueOrNull;
      if (item != null && duration != null) {
        mediaItem.add(item.copyWith(duration: duration));
      }
    });
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
      queueIndex: event.currentIndex,
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
    final index = _player.currentIndex ?? 0;
    return _queue.isNotEmpty && index < _queue.length ? _queue[index] : null;
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
    _notifyPlaybackState();
  }

  @override
  Future<void> skipToNext() async {
    final index = (_player.currentIndex ?? 0) + 1;
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
    final index = (_player.currentIndex ?? 0) - 1;
    if (index < 0) {
      await _player.seek(Duration.zero);
      return;
    }
    await _loadIndex(index, autoPlay: _player.playing);
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);
}
