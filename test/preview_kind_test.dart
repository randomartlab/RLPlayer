import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiko_local/src/services/preview_kind.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('图片魔数优先（即使扩展名是 lrc）', () {
    final dir = Directory.systemTemp.createTempSync('pk');
    // PNG 魔数内容但 .lrc 扩展 → 判图（用户反馈混淆场景）。
    final f = File('${dir.path}/fake.lrc')
      ..writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] +
          List.filled(200, 0));
    expect(classifyPreviewFile(f), PreviewKind.image);
  });

  test('LRC 文本内容判字幕（即使扩展名是 png）', () {
    final dir = Directory.systemTemp.createTempSync('pk2');
    final f = File('${dir.path}/lyric.png')
      ..writeAsStringSync('[00:01.00]测试歌词\n[00:02.00]第二行');
    expect(classifyPreviewFile(f), PreviewKind.subtitle);
  });

  test('WEBVTT/SRT 判字幕', () {
    final dir = Directory.systemTemp.createTempSync('pk3');
    final vtt = File('${dir.path}/a.vtt')
      ..writeAsStringSync('WEBVTT\n\n00:00.000 --> 00:01.000\n你好');
    expect(classifyPreviewFile(vtt), PreviewKind.subtitle);
    final srt = File('${dir.path}/b.srt')
      ..writeAsStringSync('1\n00:00:01,000 --> 00:00:02,000\n字幕');
    expect(classifyPreviewFile(srt), PreviewKind.subtitle);
  });

  test('真 PNG 图片判图', () {
    final dir = Directory.systemTemp.createTempSync('pk4');
    final f = File('${dir.path}/cover.png')
      ..writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] +
          List.filled(400, 0));
    expect(classifyPreviewFile(f), PreviewKind.image);
  });
}
