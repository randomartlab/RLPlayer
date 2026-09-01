import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/work.dart';

/// 本地作品库数据库（PRD §6.2：SQLite 作品库索引 + 音轨表含关联列）。
///
/// M2 版：扫描重建式（重扫全量替换 works/file_nodes）；
/// 增量扫描（mtime/size 检测）与播放进度/手动关联保留随 M4 引入。
class LocalLibraryDatabase {
  LocalLibraryDatabase._(this._db);

  static const String _dbName = 'kiko_local.db';
  static const int _dbVersion = 1;

  final Database _db;

  static Future<LocalLibraryDatabase> open() async {
    final db = await openDatabase(
      p.join(await getDatabasesPath(), _dbName),
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE works (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            rj_code TEXT,
            title TEXT NOT NULL,
            circle_name TEXT,
            root_path TEXT NOT NULL,
            cover_path TEXT,
            cover_source TEXT NOT NULL DEFAULT 'placeholder',
            duration_seconds INTEGER,
            track_count INTEGER NOT NULL,
            has_lyric INTEGER NOT NULL DEFAULT 0,
            has_subtitle INTEGER NOT NULL DEFAULT 0,
            nsfw INTEGER,
            added_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
            'CREATE UNIQUE INDEX idx_works_root_path ON works(root_path)');
        await db.execute(
            'CREATE INDEX idx_works_rj_code ON works(rj_code)');
        await db.execute('''
          CREATE TABLE file_nodes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            work_id INTEGER NOT NULL,
            is_directory INTEGER NOT NULL,
            name TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            parent_path TEXT NOT NULL,
            file_path TEXT,
            duration_seconds INTEGER,
            lyric_path TEXT,
            subtitle_path TEXT,
            FOREIGN KEY(work_id) REFERENCES works(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_nodes_work ON file_nodes(work_id)');
      },
    );
    return LocalLibraryDatabase._(db);
  }

  /// 全量替换本地库（M2：重扫 = 重建；works/file_nodes 整体替换）。
  Future<void> replaceAll(List<ScannedWork> works) async {
    await _db.transaction((txn) async {
      await txn.delete('file_nodes');
      await txn.delete('works');
      for (final work in works) {
        final workId = await txn.insert('works', {
          'rj_code': work.rjCode,
          'title': work.title,
          'circle_name': work.circleName,
          'root_path': work.rootPath,
          'cover_path': work.coverPath,
          'cover_source': work.coverSource.name,
          'duration_seconds': work.durationSeconds,
          'track_count': work.trackCount,
          'has_lyric': work.hasLyric ? 1 : 0,
          'has_subtitle': work.hasSubtitle ? 1 : 0,
          'nsfw': work.nsfw,
          'added_at': DateTime.now().millisecondsSinceEpoch,
        });
        final batch = txn.batch();
        for (final node in work.nodes) {
          batch.insert('file_nodes', {
            'work_id': workId,
            'is_directory': node.isDirectory ? 1 : 0,
            'name': node.name,
            'relative_path': node.relativePath,
            'parent_path': node.parentPath,
            'file_path': node.filePath,
            'duration_seconds': node.durationSeconds,
            'lyric_path': node.lyricPath,
            'subtitle_path': node.subtitlePath,
          });
        }
        await batch.commit(noResult: true);
      }
    });
  }

  Future<List<Work>> queryWorks({String? circleName}) async {
    var where = '';
    final args = <dynamic>[];
    if (circleName != null) {
      where = 'WHERE circle_name = ?';
      args.add(circleName);
    }
    final rows = await _db.rawQuery('''
      SELECT * FROM works $where
      ORDER BY (title COLLATE NOCASE), added_at DESC
    ''', args);
    return rows.map(_workFromRow).toList();
  }

  Future<Work?> queryWork(int id) async {
    final rows =
        await _db.query('works', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _workFromRow(rows.first);
  }

  Future<List<FileNode>> queryNodes(int workId) async {
    final rows = await _db.query(
      'file_nodes',
      where: 'work_id = ?',
      whereArgs: [workId],
      orderBy: 'is_directory DESC, id ASC',
    );
    return rows.map(_nodeFromRow).toList();
  }

  /// 移出库（不删源文件；内嵌封面缓存随源清理）。
  Future<void> deleteWork(int id, {String? coverPath}) async {
    await _db.delete('file_nodes', where: 'work_id = ?', whereArgs: [id]);
    await _db.delete('works', where: 'id = ?', whereArgs: [id]);
    // 仅清理提取到应用目录的内嵌封面（PRD §5.9.3）。
    if (coverPath != null) {
      final appDoc = await getApplicationDocumentsDirectory();
      final coversDir = p.join(appDoc.path, 'covers');
      if (p.isWithin(coversDir, coverPath)) {
        await File(coverPath).delete().catchError((_) => File(coverPath));
      }
    }
  }

  /// 存储统计（PRD §5.9.3）。
  Future<LibraryStats> stats() async {
    final row = await _db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM works) AS work_count,
        (SELECT COUNT(*) FROM file_nodes WHERE is_directory = 0) AS track_count,
        (SELECT COUNT(*) FROM file_nodes
          WHERE is_directory = 0 AND lyric_path IS NOT NULL) AS lyric_count,
        (SELECT COUNT(*) FROM works
          WHERE cover_path IS NULL OR cover_source = 'placeholder') AS no_cover_count
    ''');
    // 音频总字节数需 IO stat；此处单独统计。
    final tracks = await _db.rawQuery(
        "SELECT file_path FROM file_nodes WHERE is_directory = 0");
    var totalBytes = 0;
    for (final track in tracks) {
      final path = track['file_path'] as String?;
      if (path == null) continue;
      try {
        totalBytes += await File(path).length();
      } catch (_) {
        // 文件可能已被外部删除。
      }
    }
    final r = row.first;
    return LibraryStats(
      workCount: r['work_count'] as int,
      trackCount: r['track_count'] as int,
      lyricCount: r['lyric_count'] as int,
      noCoverCount: r['no_cover_count'] as int,
      totalBytes: totalBytes,
    );
  }

  /// 首次播放后回写音轨时长（PRD §5.9.2）。
  Future<void> updateTrackDuration(int nodeId, int seconds) async {
    await _db.update(
      'file_nodes',
      {'duration_seconds': seconds},
      where: 'id = ?',
      whereArgs: [nodeId],
    );
  }

  Work _workFromRow(Map<String, Object?> row) {
    return Work(
      id: row['id'] as int,
      rjCode: row['rj_code'] as String?,
      title: row['title'] as String,
      circleName: row['circle_name'] as String?,
      rootPath: row['root_path'] as String,
      coverPath: row['cover_path'] as String?,
      coverSource: CoverSource.values.firstWhere(
        (s) => s.name == row['cover_source'],
        orElse: () => CoverSource.placeholder,
      ),
      durationSeconds: row['duration_seconds'] as int?,
      trackCount: row['track_count'] as int,
      hasLyric: (row['has_lyric'] as int) == 1,
      hasSubtitle: (row['has_subtitle'] as int) == 1,
      nsfw: row['nsfw'] == null ? null : (row['nsfw'] as int) == 1,
      addedAt: DateTime.fromMillisecondsSinceEpoch(row['added_at'] as int),
    );
  }

  FileNode _nodeFromRow(Map<String, Object?> row) {
    return FileNode(
      id: row['id'] as int,
      workId: row['work_id'] as int,
      isDirectory: (row['is_directory'] as int) == 1,
      name: row['name'] as String,
      relativePath: row['relative_path'] as String,
      parentPath: row['parent_path'] as String,
      filePath: row['file_path'] as String?,
      durationSeconds: row['duration_seconds'] as int?,
      lyricPath: row['lyric_path'] as String?,
      subtitlePath: row['subtitle_path'] as String?,
    );
  }

  Future<void> close() => _db.close();
}
