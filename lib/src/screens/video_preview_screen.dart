/// 视频预览播放页（2026-09-03，类似图片/字幕预览的"第 3 种"预览）。
/// 支持本地文件与在线 URL（作品文件树/附加文件中的 mp4/mkv/webm 等）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/lyric.dart';
import '../services/scan_rules.dart' show decodeTextWithFallback;
import '../services/subtitle_parser.dart' show parseVttOrSrt;
import '../utils/ui_tokens.dart';

class VideoPreviewScreen extends StatefulWidget {
  const VideoPreviewScreen.local({
    super.key,
    required this.path,
    this.title,
    this.headers,
  })  : url = null,
        mode = _VideoSource.file;

  const VideoPreviewScreen.network({
    super.key,
    required this.url,
    this.title,
    this.headers,
  })  : path = null,
        mode = _VideoSource.network;

  final String? path;
  final String? url;
  final String? title;
  final Map<String, String>? headers;
  final _VideoSource mode;

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

enum _VideoSource { file, network }

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  VideoPlayerController? _controller;
  String? _error;
  bool _initDone = false;
  bool _showControls = true;

  // 歌词时间轴（2026-09-05：与音频同规则的文件名匹配 .lrc/.vtt/.srt）。
  Lyrics? _lyrics;
  int _lineIndex = -1;
  bool _lyricsOverlay = false;
  Timer? _ticker;
  final ScrollController _lyricScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// 本地视频：按视频文件名匹配同目录同名歌词/字幕
  ///（video.lrc > video.vtt > video.srt，音频侧同规则）。
  Future<void> _loadSidecarLyrics() async {
    final path = widget.path;
    if (path == null || widget.mode != _VideoSource.file) return;
    final base = path.substring(0, path.lastIndexOf('.'));
    for (final ext in const ['.lrc', '.vtt', '.srt']) {
      final f = File('$base$ext');
      if (!await f.exists()) continue;
      try {
        final content = decodeTextWithFallback(await f.readAsBytes());
        if (content == null) continue;
        final parsed = ext == '.lrc'
            ? Lyrics.parse(content)
            : parseVttOrSrt(content);
        if (parsed != null && !parsed.isEmpty && mounted) {
          setState(() => _lyrics = parsed);
          _startTicker();
        }
        if (_lyrics != null) return;
      } catch (_) {}
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final ctrl = _controller;
      final lyrics = _lyrics;
      if (!mounted || ctrl == null || lyrics == null) return;
      final idx = lyrics.lineIndexAt(ctrl.value.position);
      if (idx != _lineIndex) {
        setState(() => _lineIndex = idx);
        if (_lyricsOverlay && _lyricScroll.hasClients) {
          final target = (idx * 46.0 - 120).clamp(0.0, double.infinity);
          _lyricScroll.animateTo(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  Future<void> _init() async {
    try {
      final ctrl = widget.mode == _VideoSource.file
          ? VideoPlayerController.file(File(widget.path!))
          : VideoPlayerController.networkUrl(
              Uri.parse(widget.url!),
              httpHeaders: widget.headers ?? const {},
            );
      _controller = ctrl;
      await ctrl.initialize();
      if (!mounted) return;
      setState(() => _initDone = true);
      await ctrl.play();
      ctrl.setLooping(false);
      unawaited(_loadSidecarLyrics());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '无法播放视频：$e');
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lyricScroll.dispose();
    _controller?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0
        ? '${d.inHours}:$m:$s'
        : '${d.inMinutes.remainder(60)}:$s';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title ?? '视频预览',
            style: const TextStyle(fontSize: 15)),
        actions: [
          if (_lyrics != null && !_lyrics!.isEmpty)
            IconButton(
              icon: Icon(_lyricsOverlay
                  ? Icons.lyrics_rounded
                  : Icons.lyrics_outlined),
              tooltip: '歌词',
              color: Colors.white,
              onPressed: () => setState(() => _lyricsOverlay = !_lyricsOverlay),
            ),
        ],
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(UiSpacing.large),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam_off_outlined,
                        size: 56, color: Colors.white70),
                    const SizedBox(height: UiSpacing.medium),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              )
            : !_initDone
                ? const CircularProgressIndicator(color: Colors.white70)
                : ctrl == null
                    ? const SizedBox.shrink()
                    : _buildPlayer(context, ctrl),
      ),
    );
  }

  Widget _buildPlayer(BuildContext context, VideoPlayerController ctrl) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: ctrl.value.aspectRatio <= 0
                ? 16 / 9
                : ctrl.value.aspectRatio,
            child: VideoPlayer(ctrl),
          ),
          // 顶部当前行歌词（随时间轴推进）。
          if (_lyrics != null && _lineIndex >= 0 && _lineIndex < _lyrics!.lines.length)
            Positioned(
              left: 24,
              right: 24,
              top: 8,
              child: _lyricsOverlay
                  ? const SizedBox.shrink()
                  : Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _lyrics!.lines[_lineIndex].text,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(color: Colors.black, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
            ),
          // 播放/暂停中间按钮。
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: ctrl,
            builder: (_, value, __) {
              if (!_showControls) return const SizedBox.shrink();
              return IconButton(
                iconSize: 64,
                color: Colors.white,
                icon: Icon(value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled),
                onPressed: () {
                  value.isPlaying ? ctrl.pause() : ctrl.play();
                  setState(() {});
                },
              );
            },
          ),
          // 全屏歌词时间轴列表（点击歌词按钮展开）。
          if (_lyrics != null && _lyricsOverlay)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: () => setState(() => _lyricsOverlay = false),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.78),
                  child: ListView.builder(
                    controller: _lyricScroll,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 180),
                    itemCount: _lyrics!.lines.length,
                    itemBuilder: (context, i) {
                      final isCurrent = i == _lineIndex;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          _lyrics!.lines[i].text,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isCurrent
                                ? scheme.primary
                                : Colors.white60,
                            fontSize: isCurrent ? 20 : 15,
                            fontWeight:
                                isCurrent ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          // 底部控制条。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _showControls
                ? ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: ctrl,
                    builder: (_, value, __) {
                      final dur = value.duration;
                      final pos = value.position;
                      return Container(
                        color: Colors.black54,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            VideoProgressIndicator(ctrl,
                                allowScrubbing: true,
                                colors: VideoProgressColors(
                                    playedColor: scheme.primary,
                                    bufferedColor: Colors.white30,
                                    backgroundColor: Colors.white12)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_fmt(pos),
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 11)),
                                Text(_fmt(dur),
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
