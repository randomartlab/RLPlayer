/// 字幕/歌词文件预览页（本地 + 在线通用）。
///
/// 实机需求 2026-09-02：文件树中点击字幕文件进入预览。
/// 支持 .srt / .vtt（复用 subtitle_parser）与 .lrc（复用歌词解析）。
library;

import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/subtitle_parser.dart';
import '../services/scan_rules.dart' show decodeTextWithFallback;
import '../utils/ui_tokens.dart';

/// 预览数据源：本地文件路径或已下载的文本内容。
class SubtitlePreviewSource {
  const SubtitlePreviewSource({this.filePath, this.textContent, this.title});

  /// 本地文件路径（本地文件树用）。
  final String? filePath;

  /// 已取得的文本（在线文件树用，避免中转存储）。
  final String? textContent;

  final String? title;
}

class SubtitlePreviewScreen extends StatefulWidget {
  const SubtitlePreviewScreen({super.key, required this.source});

  final SubtitlePreviewSource source;

  @override
  State<SubtitlePreviewScreen> createState() => _SubtitlePreviewScreenState();
}

class _SubtitlePreviewScreenState extends State<SubtitlePreviewScreen> {
  List<_PreviewLine>? _lines;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      String content;
      if (widget.source.textContent != null) {
        content = widget.source.textContent!;
      } else {
        final file = File(widget.source.filePath!);
        // 编码嗅探：UTF-8 / GBK / Shift-JIS 等（实机反馈 2026-09-02：
        // 部分本地字幕为 GBK 编码 readAsString 乱码/异常）。
        final bytes = await file.readAsBytes();
        content = decodeTextWithFallback(bytes) ??
            utf8.decode(bytes, allowMalformed: true);
      }
      if (!mounted) return;
      setState(() => _lines = _parse(content));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '读取失败：$e');
    }
  }

  /// 解析为预览行（时间戳 + 文本）。
  List<_PreviewLine> _parse(String content) {
    // VTT/SRT → Lyrics 时间轴。
    final parsed = parseVttOrSrt(content);
    if (parsed != null && parsed.lines.isNotEmpty) {
      return parsed.lines
          .map((l) => _PreviewLine(
                timestamp: _formatDuration(l.timestamp),
                text: l.text,
              ))
          .toList();
    }
    // LRC：[mm:ss.xx] 文本。
    final lines = <_PreviewLine>[];
    final timeRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final match = timeRegex.firstMatch(line);
      if (match != null) {
        final text = line.substring(match.end).trim();
        if (text.isEmpty) continue;
        final m = int.parse(match.group(1)!);
        lines.add(_PreviewLine(
          timestamp: '$m:${match.group(2)}',
          text: text,
        ));
      } else if (!line.startsWith('[')) {
        // 无时间轴的纯文本行也展示（保留原文预览价值）。
        lines.add(_PreviewLine(timestamp: null, text: line));
      }
    }
    if (lines.isEmpty && content.trim().isNotEmpty) {
      // 兜底：按行原样展示。
      return content
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) => _PreviewLine(timestamp: null, text: l.trim()))
          .toList();
    }
    return lines;
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.source.title ?? '字幕预览')),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(UiSpacing.large),
                child: Text(_error!,
                    style: TextStyle(color: scheme.error)),
              ),
            )
          : _lines == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      vertical: UiSpacing.medium),
                  itemCount: _lines!.length,
                  itemBuilder: (context, index) {
                    final line = _lines![index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: UiSpacing.large,
                        vertical: UiSpacing.small,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (line.timestamp != null) ...[
                            SizedBox(
                              width: 64,
                              child: Text(
                                line.timestamp!,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: UiSpacing.medium),
                          ],
                          Expanded(
                            child: Text(
                              line.text,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(height: 1.45),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

class _PreviewLine {
  const _PreviewLine({this.timestamp, required this.text});

  final String? timestamp;
  final String text;
}
