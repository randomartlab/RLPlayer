import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  /// 复现坏库（缺 vas_names/tags）→ 自愈补列 → 用户报错的 INSERT 成功。
  test('坏库自愈后 INSERT 含 vas_names 成功（用户报错复现）', () async {
    final db = await factory.openDatabase(inMemoryDatabasePath);
    // 基础 works 表（坏库形态：无 vas_names/tags）。
    await db.execute('''CREATE TABLE works (
      id INTEGER PRIMARY KEY AUTOINCREMENT, rj_code TEXT,
      title TEXT NOT NULL, circle_name TEXT, root_path TEXT NOT NULL,
      cover_path TEXT, cover_source TEXT NOT NULL DEFAULT 'placeholder',
      duration_seconds INTEGER, track_count INTEGER NOT NULL,
      has_lyric INTEGER NOT NULL DEFAULT 0,
      has_subtitle INTEGER NOT NULL DEFAULT 0,
      nsfw INTEGER, added_at INTEGER NOT NULL)''');

    // 自愈（PRAGMA 检查补列）。
    final cols = (await db.rawQuery('PRAGMA table_info(works)'))
        .map((c) => c['name'] as String)
        .toSet();
    expect(cols.contains('vas_names'), isFalse);
    if (!cols.contains('vas_names')) {
      await db.execute('ALTER TABLE works ADD COLUMN vas_names TEXT');
    }
    if (!cols.contains('tags')) {
      await db.execute('ALTER TABLE works ADD COLUMN tags TEXT');
    }

    // 用户报错的原始 INSERT 语句。
    await db.insert('works', {
      'rj_code': 'RJ123456',
      'title': '午夜电台',
      'circle_name': null,
      'vas_names': null,
      'tags': null,
      'root_path': '/mnt/shared/test',
      'cover_path': '/mnt/shared/test/cover.jpg',
      'cover_source': 'localFile',
      'duration_seconds': 80,
      'track_count': 2,
      'has_lyric': 1,
      'has_subtitle': 0,
      'nsfw': null,
      'added_at': 1788281381656,
    });
    expect(await db.query('works'), isNotEmpty);
    await db.close();
  });

  test('幂等：自愈重复执行不报错', () async {
    final db = await factory.openDatabase(inMemoryDatabasePath);
    await db.execute('''CREATE TABLE works (
      id INTEGER PRIMARY KEY AUTOINCREMENT, rj_code TEXT,
      title TEXT NOT NULL, root_path TEXT NOT NULL)''');
    for (var i = 0; i < 2; i++) {
      final cols = (await db.rawQuery('PRAGMA table_info(works)'))
          .map((c) => c['name'] as String)
          .toSet();
      if (!cols.contains('vas_names')) {
        await db.execute('ALTER TABLE works ADD COLUMN vas_names TEXT');
      }
    }
    await db.close();
  });
}
