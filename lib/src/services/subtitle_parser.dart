/// VTT / SRT 字幕解析（在线播放字幕自动匹配，PRD §5.6.4 字幕源）。
///
/// 解析为 [Lyrics] 时间轴模型，复用歌词视图与 seek 联动。
library;

import '../models/lyric.dart';

/// 解析 VTT 或 SRT 文本；无法解析返回 null。
Lyrics? parseVttOrSrt(String content) {
  // 统一换行，剥掉 VTT 头与 NOTE 块。
  final normalized = content.replaceAll('\r\n', '\n');
  var body = normalized;
  if (body.startsWith('WEBVTT')) {
    final firstCue = body.indexOf(RegExp(r'\n\n'));
    if (firstCue > 0) body = body.substring(firstCue + 2);
  }

  final lines = <LyricLine>[];
  final timeRegex = RegExp(
      r'(\d{1,2}):(\d{2}):(\d{2})[.,](\d{1,3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[.,](\d{1,3})');
  final shortTimeRegex = RegExp(
      r'(\d{1,2}):(\d{2})[.,](\d{1,3})\s*-->\s*(\d{1,2}):(\d{2})[.,](\d{1,3})');

  final blocks = body.split(RegExp(r'\n\s*\n'));
  for (final block in blocks) {
    final blockLines = block.split('\n');
    int? startMs;
    for (var i = 0; i < blockLines.length; i++) {
      final line = blockLines[i].trim();
      if (line.isEmpty) continue;

      final match = timeRegex.firstMatch(line) ?? shortTimeRegex.firstMatch(line);
      if (match != null) {
        startMs = _matchToStartMs(match);
        // cue 文本 = 时间行之后的所有行。
        final text = blockLines
            .skip(i + 1)
            .join(' ')
            .trim();
        if (text.isNotEmpty && startMs != null) {
          lines.add(LyricLine(
            timestamp: Duration(milliseconds: startMs),
            text: _stripVttTags(text),
          ));
        }
        break;
      }
    }
  }

  if (lines.isEmpty) return null;
  lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return Lyrics(lines: lines);
}

int? _matchToStartMs(RegExpMatch match) {
  // hh:mm:ss.mmm（8 组）或 mm:ss.mmm（4 组）。
  if (match.groupCount >= 8) {
    final h = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    final s = int.parse(match.group(3)!);
    final ms = _fracToMs(match.group(4)!);
    return ((h * 60 + m) * 60 + s) * 1000 + ms;
  }
  final m = int.parse(match.group(1)!);
  final s = int.parse(match.group(2)!);
  final ms = _fracToMs(match.group(3)!);
  return (m * 60 + s) * 1000 + ms;
}

int _fracToMs(String frac) =>
    int.parse(frac.length <= 3 ? frac.padRight(3, '0') : frac.substring(0, 3));

/// 剥离 VTT 行内标签（`<c>`、`<00:00:01.000>` 等）。
String _stripVttTags(String text) => text
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
