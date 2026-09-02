import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  /// v8 迁移：v7 形态 net_meta（无销量/评论列）→ ALTER 补列 → 可写入读取。
  test('v8 迁移补 net_dl_count/net_review_count 列', () async {
    final db = await factory.openDatabase(inMemoryDatabasePath);
    // v7 形态 net_meta。
    await db.execute('''CREATE TABLE net_meta (
      rj_code TEXT PRIMARY KEY, work_id INTEGER,
      net_title TEXT, net_title_trans TEXT, net_circle TEXT,
      net_vas TEXT, net_tags TEXT, net_cover_url TEXT,
      net_description TEXT, net_release TEXT,
      net_rate_average REAL, net_rate_count INTEGER,
      source TEXT NOT NULL, fetched_at INTEGER NOT NULL,
      no_result INTEGER NOT NULL DEFAULT 0)''');

    // v8 迁移（幂等 try 语义复现）。
    try {
      await db.execute('ALTER TABLE net_meta ADD COLUMN net_dl_count INTEGER');
    } catch (_) {}
    try {
      await db.execute(
          'ALTER TABLE net_meta ADD COLUMN net_review_count INTEGER');
    } catch (_) {}
    // 幂等重跑。
    try {
      await db.execute('ALTER TABLE net_meta ADD COLUMN net_dl_count INTEGER');
    } catch (_) {}

    await db.insert('net_meta', {
      'rj_code': 'RJ999999',
      'work_id': 999999,
      'source': 'asmr_one',
      'fetched_at': DateTime.now().millisecondsSinceEpoch,
      'no_result': 0,
      'net_dl_count': 1234,
      'net_review_count': 56,
    });
    final row =
        (await db.query('net_meta', where: 'rj_code = ?', whereArgs: ['RJ999999'])).first;
    expect(row['net_dl_count'], 1234);
    expect(row['net_review_count'], 56);
    await db.close();
  });
}
