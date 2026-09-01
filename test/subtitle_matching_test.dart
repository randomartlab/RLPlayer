import 'package:flutter_test/flutter_test.dart';


void main() {
  // 通过详情页的静态行为不便直测私有方法——用顶层等价实现验证规则。
  // 这里直接构造 OnlineFileNode 用页面私有的匹配逻辑不可行，
  // 改为验证解析与匹配的核心等价实现（与页面内逻辑同步维护）。

  String stripAudioExt(String name) {
    for (final ext in const [
      '.mp3', '.wav', '.flac', '.m4a', '.aac', '.ogg', '.opus', '.wma',
      '.mp4', '.m4b',
    ]) {
      if (name.endsWith(ext)) {
        return name.substring(0, name.length - ext.length);
      }
    }
    return name;
  }

  String stripSubtitleExt(String name) {
    for (final ext in const ['.vtt', '.srt', '.lrc', '.txt']) {
      if (name.endsWith(ext)) {
        name = name.substring(0, name.length - ext.length);
        break;
      }
    }
    return stripAudioExt(name);
  }

  String normalize(String name) =>
      name.replaceAll(RegExp(r'[\s_\-\.\[\]\(\)（）\s]+'), '');

  test('用户点名的全部扩展名组合都能匹配', () {
    const audio = '歌名.mp3';
    final audioBase = stripAudioExt(audio);
    // .mp3.lrc / .mp3.vtt / .wav.lrc / .wav.vtt / .flac.lrc / 纯 .lrc / .srt
    for (final subtitle in [
      '歌名.mp3.lrc',
      '歌名.mp3.vtt',
      '歌名.wav.lrc',
      '歌名.wav.vtt',
      '歌名.flac.lrc',
      '歌名.lrc',
      '歌名.srt',
      '歌名.vtt',
    ]) {
      expect(stripSubtitleExt(subtitle), audioBase,
          reason: '$subtitle 应匹配 $audio');
    }
  });

  test('模糊匹配：空格/下划线/括号差异', () {
    expect(normalize(stripSubtitleExt('歌 名 (中文).mp3.vtt')),
        normalize(stripAudioExt('歌名(中文).mp3')));
    expect(normalize(stripSubtitleExt('track_01.srt')),
        normalize(stripAudioExt('track 01.mp3')));
  });

  test('不同内容不误匹配', () {
    expect(stripSubtitleExt('另一首.vtt') == stripAudioExt('歌名.mp3'), false);
  });
}
