import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/net_meta.dart';
import '../models/work.dart';
import '../services/history_service.dart';

/// 本地作品库数据库（PRD §6.2：SQLite 作品库索引 + 音轨表含关联列）。
///
/// M2 版：扫描重建式（重扫全量替换 works/file_nodes）；
/// 增量扫描（mtime/size 检测）与播放进度/手动关联保留随 M4 引入。
class LocalLibraryDatabase {
  LocalLibraryDatabase._(this._db);

  static const String _dbName = 'kiko_local.db';
  static const int _dbVersion = 9;

  /// 全部迁移逻辑的单一来源（v1 之后每版增量；onCreate 与 onUpgrade 共用，
  /// 杜绝 schema 漂移——修复“全新安装缺列”致命 bug 2026-09-02）。
  static Future<void> _migrate(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS net_meta (
          rj_code TEXT PRIMARY KEY,
          work_id INTEGER,
          net_title TEXT,
          net_title_trans TEXT,
          net_circle TEXT,
          net_vas TEXT,
          net_tags TEXT,
          net_cover_url TEXT,
          net_description TEXT,
          net_release TEXT,
          net_rate_average REAL,
          net_rate_count INTEGER,
          net_dl_count INTEGER,
          net_review_count INTEGER,
          source TEXT NOT NULL,
          fetched_at INTEGER NOT NULL,
          no_result INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS play_history (
          track_key TEXT PRIMARY KEY,
          node_id INTEGER,
          work_id INTEGER,
          track_title TEXT NOT NULL,
          work_title TEXT NOT NULL,
          cover_path TEXT,
          artwork_url TEXT,
          position_ms INTEGER NOT NULL,
          duration_ms INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_history_updated '
          'ON play_history(updated_at DESC)');
    }
    if (oldVersion < 4) {
      await db.execute(
          'ALTER TABLE works ADD COLUMN vas_names TEXT');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE works ADD COLUMN tags TEXT');
    }
    if (oldVersion < 6) {
      await db.execute(
          'CREATE TABLE IF NOT EXISTS playlists (id INTEGER PRIMARY KEY '
          'AUTOINCREMENT, name TEXT NOT NULL, description TEXT, '
          'created_at INTEGER NOT NULL)');
      await db.execute(
          'CREATE TABLE IF NOT EXISTS playlist_items (id INTEGER PRIMARY KEY '
          'AUTOINCREMENT, playlist_id INTEGER NOT NULL, work_id INTEGER, '
          'node_id INTEGER, track_key TEXT NOT NULL, track_title TEXT NOT NULL, '
          'work_title TEXT, cover_path TEXT, sort_index INTEGER NOT NULL, '
          'FOREIGN KEY(playlist_id) REFERENCES playlists(id) '
          'ON DELETE CASCADE)');
    }
    if (oldVersion < 9) {
      // v9: 作品状态（想听/在听/听过 + 我的评分，2026-09-02）。
      await db.execute(
          'CREATE TABLE IF NOT EXISTS work_status (rj_code TEXT PRIMARY KEY, status TEXT NOT NULL DEFAULT \'none\', rating INTEGER, updated_at INTEGER NOT NULL)');
    }
    if (oldVersion < 8) {
      // v8: net_meta 销量/评论数（本地排序，2026-09-02）。
      try {
        await db.execute(
            'ALTER TABLE net_meta ADD COLUMN net_dl_count INTEGER');
      } catch (_) {}
      try {
        await db.execute(
            'ALTER TABLE net_meta ADD COLUMN net_review_count INTEGER');
      } catch (_) {}
    }
    if (oldVersion < 7) {
      // v7 自愈：修复历史上 onCreate 与 onUpgrade 漂移产生的坏库
      //（版本号已标 6 但缺列/缺表）。PRAGMA 检查后补齐。
      await _selfHealV7(db);
    }
  }

  /// v7 自愈：按需补齐缺失列/表（幂等，可重复执行）。
  static Future<void> _selfHealV7(Database db) async {
    // works 缺列检查。
    final columns = await db.rawQuery('PRAGMA table_info(works)');
    final columnNames = columns.map((c) => c['name'] as String).toSet();
    if (!columnNames.contains('vas_names')) {
      await db.execute('ALTER TABLE works ADD COLUMN vas_names TEXT');
    }
    if (!columnNames.contains('tags')) {
      await db.execute('ALTER TABLE works ADD COLUMN tags TEXT');
    }
    // 辅助表存在性（IF NOT EXISTS 幂等）。
    await db.execute(
        'CREATE TABLE IF NOT EXISTS playlists (id INTEGER PRIMARY KEY '
        'AUTOINCREMENT, name TEXT NOT NULL, description TEXT, '
        'created_at INTEGER NOT NULL)');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS playlist_items (id INTEGER PRIMARY KEY '
        'AUTOINCREMENT, playlist_id INTEGER NOT NULL, work_id INTEGER, '
        'node_id INTEGER, track_key TEXT NOT NULL, track_title TEXT NOT NULL, '
        'work_title TEXT, cover_path TEXT, sort_index INTEGER NOT NULL, '
        'FOREIGN KEY(playlist_id) REFERENCES playlists(id) '
        'ON DELETE CASCADE)');
  }

  /// 基础表（v1）——仅 onCreate 使用；其余版本全部走 [_migrate]。
  static Future<void> _createBaseTables(Database db) async {
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
    await db.execute('CREATE INDEX idx_works_rj_code ON works(rj_code)');
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
    // v9: 作品状态。
    await db.execute(
        'CREATE TABLE IF NOT EXISTS work_status (rj_code TEXT PRIMARY KEY, status TEXT NOT NULL DEFAULT \'none\', rating INTEGER, updated_at INTEGER NOT NULL)');
  }

  final Database _db;

  static Future<LocalLibraryDatabase> open() async {
    final db = await openDatabase(
      p.join(await getDatabasesPath(), _dbName),
      version: _dbVersion,
      onUpgrade: _migrate,
      onCreate: (db, version) async {
        // 全新安装：基础表 + 与升级同一套迁移（单一来源，杜绝漂移）。
        await _createBaseTables(db);
        await _migrate(db, 1, version);
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
          'vas_names': work.vasNames.isEmpty ? null : work.vasNames.join('\u0001'),
          'tags': work.tags.isEmpty ? null : work.tags.join('\u0001'),
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
      vasNames: ((row['vas_names'] as String?) ?? '')
          .split('\u0001')
          .where((v) => v.isNotEmpty)
          .toList(),
      tags: ((row['tags'] as String?) ?? '')
          .split('\u0001')
          .where((v) => v.isNotEmpty)
          .toList(),
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

  /// 网络封面兜底落盘后更新作品封面（PRD §5.11 封面降级链第 3 级）。
  /// 手动补录 RJ 号（未识别 RJ 作品，2026-09-02）。
  Future<void> updateWorkRjCode(int workId, String rjCode) async {
    await _db.update('works', {'rj_code': rjCode},
        where: 'id = ?', whereArgs: [workId]);
  }

  Future<void> updateWorkCover(int workId, String coverPath) async {
    await _db.update('works', {
      'cover_path': coverPath,
      'cover_source': 'network',
    }, where: 'id = ?', whereArgs: [workId]);
  }

  /// 显示字段回填（CV/标题，NetMeta 命中后调用；用户决策 2026-09-01）。
  Future<void> updateWorkDisplayFields(
    int workId, {
    List<String>? vasNames,
    String? title,
  }) async {
    final updates = <String, Object?>{};
    if (vasNames != null && vasNames.isNotEmpty) {
      updates['vas_names'] = vasNames.join('\u0001');
    }
    // 标题仅在本地标题无信息量（纯 RJ 号）时由网络标题补全——本地优先。
    if (title != null && title.isNotEmpty) {
      updates['title'] = title;
    }
    if (updates.isEmpty) return;
    await _db.update('works', updates, where: 'id = ?', whereArgs: [workId]);
  }

  /// 按 RJ 号查作品 id（封面兜底定位）。
  Future<int?> queryWorkIdByRj(String rjCode) async {
    final rows = await _db.query('works',
        columns: ['id'], where: 'rj_code = ?', whereArgs: [rjCode], limit: 1);
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  // ---- NetMeta 缓存（M11） ----

  // ---- 作品状态（v9）----

  Future<Map<String, dynamic>?> getWorkStatus(String rjCode) async {
    final rows = await _db.query('work_status',
        where: 'rj_code = ?', whereArgs: [rjCode], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> setWorkStatus(String rjCode, String status,
      {int? rating}) async {
    await _db.insert(
        'work_status',
        {
          'rj_code': rjCode,
          'status': status,
          'rating': rating,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearWorkStatus(String rjCode) async {
    await _db
        .delete('work_status', where: 'rj_code = ?', whereArgs: [rjCode]);
  }

  /// 全部状态（我的页列表用）。
  Future<List<Map<String, dynamic>>> allWorkStatus() async {
    return _db.query('work_status', orderBy: 'updated_at DESC');
  }

  /// 全部 NetMeta（本地排序/筛选批量加载，2026-09-02）。
  Future<List<NetMeta>> queryAllNetMeta() async {
    final rows = await _db.query('net_meta');
    return rows.map(_netMetaFromRow).toList();
  }

  Future<NetMeta?> queryNetMeta(String rjCode) async {
    final rows = await _db.query('net_meta',
        where: 'rj_code = ?', whereArgs: [rjCode], limit: 1);
    if (rows.isEmpty) return null;
    return _netMetaFromRow(rows.first);
  }

  Future<void> upsertNetMeta(NetMeta meta) async {
    await _db.insert(
        'net_meta',
        {
          'rj_code': meta.rjCode,
          'work_id': meta.workId,
          'net_title': meta.netTitle,
          'net_title_trans': meta.netTitleTrans,
          'net_circle': meta.netCircle,
          'net_vas': meta.netVas.join('\u0001'),
          'net_tags': meta.netTags.join('\u0001'),
          'net_cover_url': meta.netCoverUrl,
          'net_description': meta.netDescription,
          'net_release': meta.netRelease?.toIso8601String(),
          'net_rate_average': meta.netRateAverage,
          'net_rate_count': meta.netRateCount,
          'net_dl_count': meta.netDlCount,
          'net_review_count': meta.netReviewCount,
          'source': meta.source,
          'fetched_at': meta.fetchedAt.millisecondsSinceEpoch,
          'no_result': meta.noResult ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearNetMeta() => _db.delete('net_meta');

  NetMeta _netMetaFromRow(Map<String, Object?> row) {
    return NetMeta(
      rjCode: row['rj_code'] as String,
      workId: row['work_id'] as int?,
      netTitle: row['net_title'] as String?,
      netTitleTrans: row['net_title_trans'] as String?,
      netCircle: row['net_circle'] as String?,
      netVas: ((row['net_vas'] as String?) ?? '')
          .split('\u0001')
          .where((s) => s.isNotEmpty)
          .toList(),
      netTags: ((row['net_tags'] as String?) ?? '')
          .split('\u0001')
          .where((s) => s.isNotEmpty)
          .toList(),
      netCoverUrl: row['net_cover_url'] as String?,
      netDescription: row['net_description'] as String?,
      netRelease: DateTime.tryParse((row['net_release'] as String?) ?? ''),
      netRateAverage: row['net_rate_average'] as double?,
      netRateCount: row['net_rate_count'] as int?,
      netDlCount: row['net_dl_count'] as int?,
      netReviewCount: row['net_review_count'] as int?,
      source: row['source'] as String? ?? 'asmr_one',
      fetchedAt:
          DateTime.fromMillisecondsSinceEpoch(row['fetched_at'] as int),
      noResult: (row['no_result'] as int) == 1,
    );
  }

  // ---- 播放历史（M7，断点续播） ----

  Future<void> upsertHistory(HistoryEntry entry) async {
    // node → work 联查补全 workId。
    int? workId = entry.workId;
    if (workId == null && entry.nodeId != null) {
      final rows = await _db.query('file_nodes',
          columns: ['work_id'],
          where: 'id = ?',
          whereArgs: [entry.nodeId],
          limit: 1);
      workId = rows.isEmpty ? null : rows.first['work_id'] as int;
    }
    await _db.insert(
        'play_history',
        {
          'track_key': entry.trackKey,
          'node_id': entry.nodeId,
          'work_id': workId,
          'track_title': entry.trackTitle,
          'work_title': entry.workTitle,
          'cover_path': entry.coverPath,
          'artwork_url': entry.artworkUrl,
          'position_ms': entry.positionMs,
          'duration_ms': entry.durationMs,
          'updated_at': entry.updatedAt.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<HistoryEntry>> queryHistory({int limit = 100}) async {
    final rows = await _db.query('play_history',
        orderBy: 'updated_at DESC', limit: limit);
    return rows
        .map((row) => HistoryEntry(
              trackKey: row['track_key'] as String,
              nodeId: row['node_id'] as int?,
              workId: row['work_id'] as int?,
              trackTitle: row['track_title'] as String,
              workTitle: row['work_title'] as String,
              coverPath: row['cover_path'] as String?,
              artworkUrl: row['artwork_url'] as String?,
              positionMs: row['position_ms'] as int,
              durationMs: row['duration_ms'] as int,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(
                  row['updated_at'] as int),
            ))
        .toList();
  }

  Future<void> deleteHistory(String trackKey) =>
      _db.delete('play_history', where: 'track_key = ?', whereArgs: [trackKey]);

  Future<void> clearHistory() => _db.delete('play_history');

  // ---- 播放列表（M7，PRD §5.8） ----

  Future<int> insertPlaylist(String name, {String? description}) async {
    return _db.insert('playlists', {
      'name': name,
      'description': description,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> renamePlaylist(int id, String name,
      {String? description}) async {
    await _db.update(
        'playlists',
        {
          'name': name,
          'description': ?description,
        },
        where: 'id = ?',
        whereArgs: [id]);
  }

  Future<void> deletePlaylist(int id) async {
    await _db.delete('playlist_items',
        where: 'playlist_id = ?', whereArgs: [id]);
    await _db.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> queryPlaylists() async {
    return _db.rawQuery('''
      SELECT p.*, COUNT(i.id) AS item_count
      FROM playlists p LEFT JOIN playlist_items i ON i.playlist_id = p.id
      GROUP BY p.id ORDER BY p.created_at DESC
    ''');
  }

  Future<List<Map<String, Object?>>> queryPlaylistItems(
      int playlistId) async {
    return _db.query('playlist_items',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
        orderBy: 'sort_index ASC');
  }

  Future<void> addPlaylistItem(
      int playlistId, Map<String, Object?> item) async {
    final maxRow = await _db.rawQuery(
        'SELECT MAX(sort_index) AS m FROM playlist_items '
        'WHERE playlist_id = ?',
        [playlistId]);
    final next = ((maxRow.first['m'] as int?) ?? -1) + 1;
    await _db.insert('playlist_items', {
      ...item,
      'playlist_id': playlistId,
      'sort_index': next,
    });
  }

  Future<void> removePlaylistItem(int itemId) async {
    await _db
        .delete('playlist_items', where: 'id = ?', whereArgs: [itemId]);
  }

  Future<void> reorderPlaylistItems(
      int playlistId, List<int> orderedItemIds) async {
    await _db.transaction((txn) async {
      for (var i = 0; i < orderedItemIds.length; i++) {
        await txn.update('playlist_items', {'sort_index': i},
            where: 'id = ?', whereArgs: [orderedItemIds[i]]);
      }
    });
  }

  Future<void> close() => _db.close();
}
