/// 视频预览播放页（2026-09-03，类似图片/字幕预览的"第 3 种"预览）。
/// 支持本地文件与在线 URL（作品文件树/附加文件中的 mp4/mkv/webm 等）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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

  @override
  void initState() {
    super.initState();
    _init();
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '无法播放视频：$e');
    }
  }

  @override
  void dispose() {
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
