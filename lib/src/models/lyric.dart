/// LRC 歌词解析与时间轴定位（PRD §5.6.4、§5.9.2）。
///
/// 歌词 seek 联动的统一入口是 [Lyrics.lineIndexAt]：seek 事件与播放 tick
/// 事件都通过"定位到时刻 t"的同一算法求目标行，避免两套逻辑漂移。
class LyricLine {
  final Duration timestamp;
  final String text;

  const LyricLine({required this.timestamp, required this.text});
}

class Lyrics {
  /// 已按时间戳升序排序的歌词行。
  final List<LyricLine> lines;

  const Lyrics({required this.lines});

  bool get isEmpty => lines.isEmpty;

  /// 解析 LRC 文本；支持多时间戳行 `[mm:ss.xx][mm:ss.xx] 歌词`、
  /// 增强格式行内 `<mm:ss.xx>`（行内时间标签解析后剥离）、重复时间戳保留多行。
  /// 解析不出任何时间戳行时返回 null。
  static Lyrics? parse(String content) {
    final lines = <LyricLine>[];
    final timestampRegex = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
    final enhancedRegex = RegExp(r'<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>');

    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final matches = timestampRegex.allMatches(rawLine).toList();
      if (matches.isEmpty) continue;

      // 时间标签之后的剩余文本（剥离所有行首时间标签与行内增强标签）。
      var text = rawLine.substring(matches.last.end).trim();
      text = text.replaceAll(enhancedRegex, '').trim();

      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final fractionRaw = match.group(3) ?? '0';
        // 分数位按位数归一化：".5" = 500ms，".05" = 50ms，".005" = 5ms。
        final fraction = fractionRaw.length <= 3
            ? int.parse(fractionRaw.padRight(3, '0'))
            : int.parse(fractionRaw.substring(0, 3));
        final timestamp = Duration(
          milliseconds: minutes * 60000 + seconds * 1000 + fraction,
        );
        lines.add(LyricLine(timestamp: timestamp, text: text));
      }
    }

    if (lines.isEmpty) return null;
    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return Lyrics(lines: lines);
  }

  /// 二分查找时间戳 ≤ [t] 的最后一行（PRD §5.6.4 定位算法）。
  ///
  /// - t 早于首行时间戳 → 返回 0（定位首行）；
  /// - t 晚于末行 → 返回最后一行；
  /// - 空歌词返回 -1。
  int lineIndexAt(Duration t) {
    if (lines.isEmpty) return -1;

    var low = 0;
    var high = lines.length - 1;
    var result = 0;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].timestamp <= t) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }
}
