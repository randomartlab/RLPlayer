import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:kiko_local/src/services/scan_rules.dart';

void main() {
  group('parseRjInfo（表层 RJ 识别，PRD 决策 5）', () {
    test('RJ 前缀 + 标题', () {
      final info = parseRjInfo('RJ123456 深夜的烧烤店');
      expect(info!.code, 'RJ123456');
      expect(info.title, '深夜的烧烤店');
    });

    test('小写前缀规范化为大写', () {
      expect(parseRjInfo('rj398752')!.code, 'RJ398752');
    });

    test('BJ/VJ 前缀', () {
      expect(parseRjInfo('BJ001234')!.code, 'BJ001234');
      expect(parseRjInfo('VJ009876')!.code, 'VJ009876');
    });

    test('标题在编号之前', () {
      final info = parseRjInfo('[社团] RJ424242');
      expect(info!.code, 'RJ424242');
      expect(info.title, '[社团]');
    });

    test('无 RJ 返回 null', () {
      expect(parseRjInfo('普通文件夹'), isNull);
    });

    test('位数不足不匹配（5 位）', () {
      expect(parseRjInfo('RJ12345'), isNull);
    });
  });

  group('classifyFile（文件分类）', () {
    test('音频扩展名', () {
      for (final name in ['a.mp3', 'b.M4A', 'c.flac', 'd.wav', 'e.ogg', 'f.opus']) {
        expect(classifyFile(name), FileClass.audio);
      }
    });

    test('歌词与字幕', () {
      expect(classifyFile('01.lrc'), FileClass.lyric);
      expect(classifyFile('01.vtt'), FileClass.subtitle);
      expect(classifyFile('01.srt'), FileClass.subtitle);
    });

    test('图片与 metadata', () {
      expect(classifyFile('cover.jpg'), FileClass.image);
      expect(classifyFile('metadata.json'), FileClass.metadata);
    });
  });

  group('compareNatural（数字感知排序）', () {
    test('track2 < track10', () {
      expect(compareNatural('track2.mp3', 'track10.mp3'), lessThan(0));
    });

    test('数字相同回退字典序', () {
      expect(compareNatural('a01', 'a01'), 0);
    });
  });

  group('associateSameName（同名自动关联，PRD §5.9.2）', () {
    test('第一优先：完全同名', () {
      final result = associateSameName(
        ['01.mp3', '02.mp3'],
        ['01.lrc', '02.lrc'],
      );
      expect(result['01.mp3'], '01.lrc');
      expect(result['02.mp3'], '02.lrc');
    });

    test('第二优先：唯一音频 ↔ 唯一旁车文件', () {
      final result = associateSameName(
        ['01.mp3'],
        ['lyrics.lrc'],
      );
      expect(result['01.mp3'], 'lyrics.lrc');
    });

    test('多音频 + 无同名 → 不关联', () {
      final result = associateSameName(
        ['01.mp3', '02.mp3'],
        ['lyrics.lrc'],
      );
      expect(result, isEmpty);
    });
  });

  group('pickLocalCover（封面 5 级降级链，本地部分）', () {
    CoverCandidate candidate(
      String name, {
      int size = 1000,
      int depth = 0,
      bool sameName = false,
    }) =>
        CoverCandidate(
          relativePath: name,
          absolutePath: '/work/$name',
          baseName: name.split('.').first.toLowerCase(),
          sizeBytes: size,
          depth: depth,
          sameNameAsAudio: sameName,
        );

    test('优先级 1：cover/folder 命名优先', () {
      final picked = pickLocalCover([
        candidate('cover.jpg', size: 100),
        candidate('big_image.png', size: 99999),
      ]);
      expect(picked, '/work/cover.jpg');
    });

    test('优先级 1 内：浅层优先', () {
      final picked = pickLocalCover([
        candidate('sub/cover.jpg', depth: 1),
        candidate('cover.jpg', depth: 0),
      ]);
      expect(picked, '/work/cover.jpg');
    });

    test('优先级 2：与音频同名 > 更大的无关图片', () {
      final picked = pickLocalCover([
        candidate('01.jpg', size: 500, sameName: true),
        candidate('random.png', size: 99999),
      ]);
      expect(picked, '/work/01.jpg');
    });

    test('优先级 3：最大字节数', () {
      final picked = pickLocalCover([
        candidate('a.jpg', size: 100),
        candidate('b.png', size: 99999),
      ]);
      expect(picked, '/work/b.png');
    });

    test('空候选返回 null', () {
      expect(pickLocalCover(const []), isNull);
    });
  });

  group('decodeTextWithFallback（编码嗅探）', () {
    test('UTF-8 直接命中', () {
      final text = decodeTextWithFallback(utf8.encode('こんにちは'));
      expect(text, 'こんにちは');
    });

    test('Shift-JIS 回退命中', () {
      // "こんにちは" 的 Shift-JIS 字节。
      const shiftJisBytes = [0x82, 0xB1, 0x82, 0xF1, 0x82, 0xC9, 0x82, 0xBF, 0x82, 0xCD];
      final text = decodeTextWithFallback(shiftJisBytes);
      expect(text, 'こんにちは');
    });

    test('GBK 回退命中', () {
      // "中文歌词" 的 GBK 字节。
      const gbkBytes = [0xD6, 0xD0, 0xCE, 0xC4, 0xB8, 0xE8, 0xB4, 0xCA];
      final text = decodeTextWithFallback(gbkBytes);
      expect(text, '中文歌词');
    });
  });

  group('isTinyAudio（小文件过滤）', () {
    test('体积与时长双条件才过滤', () {
      expect(isTinyAudio(50 * 1024, 5), isTrue);
      expect(isTinyAudio(50 * 1024, 30), isFalse);
      expect(isTinyAudio(500 * 1024, 5), isFalse);
    });

    test('时长未知不过滤（防误杀）', () {
      expect(isTinyAudio(50 * 1024, null), isFalse);
    });
  });
}
