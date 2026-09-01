import 'package:flutter_test/flutter_test.dart';

import 'package:kiko_local/src/services/subtitle_parser.dart';

void main() {
  test('解析 SRT', () {
    const srt = '''
1
00:00:01,000 --> 00:00:03,000
第一句字幕

2
00:01:02,500 --> 00:01:05,000
第二句字幕
''';
    final lyrics = parseVttOrSrt(srt);
    expect(lyrics, isNotNull);
    expect(lyrics!.lines.length, 2);
    expect(lyrics.lines[0].timestamp, const Duration(seconds: 1));
    expect(lyrics.lines[0].text, '第一句字幕');
    expect(lyrics.lines[1].timestamp,
        const Duration(minutes: 1, seconds: 2, milliseconds: 500));
  });

  test('解析 VTT（含头部与行内标签）', () {
    const vtt = '''
WEBVTT

00:00:05.000 --> 00:00:08.000
<v Speaker>你好<00:00:06.000>世界

00:00:10.000 --> 00:00:12.000
第二行
''';
    final lyrics = parseVttOrSrt(vtt);
    expect(lyrics, isNotNull);
    expect(lyrics!.lines.length, 2);
    expect(lyrics.lines[0].text, '你好 世界');
    expect(lyrics.lines[1].timestamp, const Duration(seconds: 10));
  });

  test('非字幕内容返回 null', () {
    expect(parseVttOrSrt('plain text\nno cues'), isNull);
  });
}
