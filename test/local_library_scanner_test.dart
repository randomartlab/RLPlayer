import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kiko_local/src/services/local_library_scanner.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kiko_scan_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  File makeFile(String path, [String content = 'x']) {
    final file = File('${tempDir.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  test('穿透扫描：任意层级嵌套的 RJ 文件夹被发现（验收 #17）', () async {
    // 根目录/合集分类/RJ123456/ 穿透发现。
    makeFile('合集分类/RJ123456 深夜食堂/01.mp3');
    makeFile('合集分类/RJ123456 深夜食堂/02.mp3');
    makeFile('合集分类/RJ123456 深夜食堂/cover.jpg');
    // 更深层嵌套。
    makeFile('A/B/C/RJ008888/track.flac');

    final scanner = LocalLibraryScanner();
    final works = await scanner.scanRoots([tempDir.path]);

    expect(works.length, 2);
    final rj123 = works.firstWhere((w) => w.rjCode == 'RJ123456');
    expect(rj123.title, '深夜食堂'); // 表层文件夹名 RJ 之外的文字作标题
    expect(rj123.trackCount, 2);
    expect(rj123.coverPath, isNotNull); // cover.jpg 优先级 1 命中
    expect(works.any((w) => w.rjCode == 'RJ008888'), isTrue);
  });

  test('非 RJ 音频文件夹 → 待整理作品（文件夹名作标题）', () async {
    makeFile('散装音乐集/song_a.mp3');
    makeFile('散装音乐集/song_b.ogg');

    final scanner = LocalLibraryScanner();
    final works = await scanner.scanRoots([tempDir.path]);

    expect(works.length, 1);
    expect(works.first.rjCode, isNull);
    expect(works.first.title, '散装音乐集');
    expect(works.first.trackCount, 2);
  });

  test('根目录散落音频 → 按父目录聚合为一个作品', () async {
    makeFile('loose_01.mp3');
    makeFile('loose_02.mp3');

    final scanner = LocalLibraryScanner();
    final works = await scanner.scanRoots([tempDir.path]);

    expect(works.length, 1);
    expect(works.first.trackCount, 2);
  });

  test('同名歌词/字幕自动关联（验收 #11）', () async {
    makeFile('RJ111111/01.mp3');
    makeFile('RJ111111/01.lrc', '[00:01.00]第一句');
    makeFile('RJ111111/01.srt');
    makeFile('RJ111111/02.mp3');

    final scanner = LocalLibraryScanner();
    final works = await scanner.scanRoots([tempDir.path]);

    final work = works.single;
    expect(work.hasLyric, isTrue);
    expect(work.hasSubtitle, isTrue);
    final track1 = work.nodes
        .firstWhere((n) => !n.isDirectory && n.name == '01.mp3');
    expect(track1.lyricPath, isNotNull);
    expect(track1.subtitlePath, isNotNull);
    final track2 = work.nodes
        .firstWhere((n) => !n.isDirectory && n.name == '02.mp3');
    expect(track2.lyricPath, isNull);
  });

  test('子目录文件树还原 + 自然排序', () async {
    makeFile('RJ222222/disc1/track2.mp3');
    makeFile('RJ222222/disc1/track10.mp3');
    makeFile('RJ222222/disc2/song.mp3');

    final scanner = LocalLibraryScanner();
    final works = await scanner.scanRoots([tempDir.path]);

    final nodes = works.single.nodes;
    // 目录在前，自然排序 track2 < track10。
    final disc1Index =
        nodes.indexWhere((n) => n.isDirectory && n.name == 'disc1');
    expect(disc1Index, greaterThanOrEqualTo(0));
    final names =
        nodes.where((n) => !n.isDirectory).map((n) => n.name).toList();
    expect(names.indexOf('track2.mp3'), lessThan(names.indexOf('track10.mp3')));
  });

  test('嵌套 RJ 文件夹不重复入库（表层 RJ 为准）', () async {
    makeFile('RJ333333/RJ444444/nested.mp3');
    makeFile('RJ333333/outer.mp3');

    final scanner = LocalLibraryScanner();
    final works = await scanner.scanRoots([tempDir.path]);

    expect(works.length, 1);
    expect(works.first.rjCode, 'RJ333333');
    expect(works.first.trackCount, 2); // 嵌套子文件夹音轨并入文件树
  });

  test('metadata.json 字段映射（Kikoeru 格式）', () async {
    makeFile('普通文件夹/track.mp3');
    File('${tempDir.path}/普通文件夹/metadata.json').writeAsStringSync('''
    {
      "id": 555555,
      "title": "元数据标题",
      "circle": {"name": "示例社团"},
      "nsfw": true
    }
    ''');

    final scanner = LocalLibraryScanner();
    final works = await scanner.scanRoots([tempDir.path]);

    final work = works.single;
    expect(work.rjCode, 'RJ555555'); // 文件夹无 RJ → metadata 补充
    expect(work.title, '元数据标题');
    expect(work.circleName, '示例社团');
    expect(work.nsfw, isTrue);
  });

  test('隐藏文件与空文件夹跳过', () async {
    makeFile('RJ666666/.hidden.mp3');
    makeFile('RJ666666/.DS_Store');
    makeFile('RJ666666/visible.mp3');
    Directory('${tempDir.path}/空文件夹').createSync();

    final scanner = LocalLibraryScanner();
    final works = await scanner.scanRoots([tempDir.path]);

    expect(works.length, 1);
    expect(works.first.trackCount, 1); // 仅 visible.mp3
  });
}
