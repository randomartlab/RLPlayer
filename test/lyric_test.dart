import 'package:flutter_test/flutter_test.dart';

import 'package:kiko_local/src/models/lyric.dart';

/// LRC 解析与歌词 seek 联动定位算法测试（PRD §5.6.4 / 验收 #13）。
void main() {
  group('Lyrics.parse', () {
    test('解析单时间戳行', () {
      final lyrics = Lyrics.parse('[00:12.50]第一句\n[01:02.00]第二句\n');
      expect(lyrics, isNotNull);
      expect(lyrics!.lines.length, 2);
      expect(lyrics.lines[0].timestamp, const Duration(seconds: 12, milliseconds: 500));
      expect(lyrics.lines[0].text, '第一句');
    });

    test('解析多时间戳行（重复时间戳保留多行）', () {
      final lyrics = Lyrics.parse('[00:08.00][00:08.50]双时间戳行\n');
      expect(lyrics, isNotNull);
      expect(lyrics!.lines.length, 2);
      expect(lyrics.lines[0].text, '双时间戳行');
      expect(lyrics.lines[1].text, '双时间戳行');
      expect(lyrics.lines[0].timestamp < lyrics.lines[1].timestamp, isTrue);
    });

    test('剥离增强格式行内标签', () {
      final lyrics = Lyrics.parse('[00:05.00]<00:05.00>逐<00:05.50>字\n');
      expect(lyrics, isNotNull);
      expect(lyrics!.lines.single.text, '逐字');
    });

    test('分数位按位数归一化（.5 = 500ms）', () {
      final lyrics = Lyrics.parse('[00:01.5]a\n');
      expect(lyrics!.lines.single.timestamp,
          const Duration(seconds: 1, milliseconds: 500));
    });

    test('无时间戳内容返回 null', () {
      expect(Lyrics.parse('纯文本\n没有时间标签'), isNull);
    });
  });

  group('Lyrics.lineIndexAt（seek 联动二分定位）', () {
    final lyrics = Lyrics.parse(
        '[00:10.00]A\n[00:20.00]B\n[00:30.00]C\n[00:40.00]D\n')!;

    test('命中区间内：t 命中 B', () {
      expect(lyrics.lineIndexAt(const Duration(seconds: 25)), 1);
    });

    test('恰好等于时间戳：t = 30 命中 C', () {
      expect(lyrics.lineIndexAt(const Duration(seconds: 30)), 2);
    });

    test('越界：早于首行定位首行', () {
      expect(lyrics.lineIndexAt(Duration.zero), 0);
      expect(lyrics.lineIndexAt(const Duration(seconds: 5)), 0);
    });

    test('越界：晚于末行定位末行', () {
      expect(lyrics.lineIndexAt(const Duration(minutes: 5)), 3);
    });
  });
}
