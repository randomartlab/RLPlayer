import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:kiko_local/src/services/local_library_scanner.dart';
import 'package:kiko_local/src/models/work.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RJ 文件夹内普通图片（无封面关键词）也应成为封面', () async {
    final dir = Directory.systemTemp.createTempSync('cover_test');
    final workDir = Directory('${dir.path}/RJ01101674 碧蓝航线测试')
      ..createSync();
    // 最小占位 PNG（扫描器按扩展名+文件大小分类，不读图内容）。
    File('${workDir.path}/img_01.png').writeAsBytesSync(
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + List.filled(600, 0));
    File('${workDir.path}/track.mp3').writeAsBytesSync(List.filled(2048, 0));

    final scanner = LocalLibraryScanner();
    final works = await scanner.scanRoots([dir.path]);
    expect(works, isNotEmpty, reason: 'RJ 文件夹未识别为作品');
    final w = works.first;
    expect(w.rjCode, 'RJ01101674');
    expect(w.coverSource, isNot(CoverSource.placeholder),
        reason: '文件夹内有图片却仍是 placeholder');
  });
}
