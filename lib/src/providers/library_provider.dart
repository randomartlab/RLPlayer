import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/work.dart';
import '../services/local_library_database.dart';
import '../services/local_library_scanner.dart';

/// 排序方式（作品库，PRD §5.4 排序/筛选）。
enum WorkSortBy { title, addedAt, rjCode }

/// 本地库提供者：扫描根目录管理、扫描执行、作品列表、移出库、统计。
class LibraryProvider extends ChangeNotifier {
  static const String _rootsKey = 'scan_roots';

  LocalLibraryDatabase? _db;

  List<String> _roots = [];
  List<Work> _works = [];

  /// 扫描状态。
  bool _scanning = false;
  String? _scanningPath;
  int _scanningFound = 0;

  List<String> get roots => List.unmodifiable(_roots);
  List<Work> get works => List.unmodifiable(_works);
  bool get scanning => _scanning;
  String? get scanningPath => _scanningPath;
  int get scanningFound => _scanningFound;

  WorkSortBy sortBy = WorkSortBy.title;

  LibraryProvider() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getStringList(_rootsKey) ?? [];
    _roots = encoded;
    _db = await LocalLibraryDatabase.open();
    await _reloadWorks();
    notifyListeners();
  }

  Future<void> _reloadWorks() async {
    final db = _db;
    if (db == null) return;
    _works = await db.queryWorks();
    _sortWorks();
  }

  void _sortWorks() {
    switch (sortBy) {
      case WorkSortBy.title:
        _works.sort((a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case WorkSortBy.addedAt:
        _works.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case WorkSortBy.rjCode:
        _works.sort((a, b) => (a.rjCode ?? 'zzz').compareTo(b.rjCode ?? 'zzz'));
    }
  }

  Future<void> setSortBy(WorkSortBy value) async {
    sortBy = value;
    _sortWorks();
    notifyListeners();
  }

  // ---- 扫描根目录管理（SAF 多目录语义，M2 为文件路径直访版）----

  Future<bool> addRoot(String path) async {
    if (_roots.contains(path)) return false;
    if (!await Directory(path).exists()) return false;
    _roots.add(path);
    await _persistRoots();
    notifyListeners();
    return true;
  }

  Future<void> removeRoot(String path) async {
    _roots.remove(path);
    await _persistRoots();
    notifyListeners();
  }

  Future<void> _persistRoots() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_rootsKey, _roots);
  }

  // ---- 扫描（PRD §5.9：不阻塞 UI、进度可见、可取消）----

  LocalLibraryScanner? _activeScanner;

  Future<void> rescan() async {
    if (_scanning) return;
    final db = _db;
    if (db == null || _roots.isEmpty) return;

    _scanning = true;
    _scanningPath = null;
    _scanningFound = 0;
    notifyListeners();

    try {
      final appDoc = await getApplicationDocumentsDirectory();
      final coversDir = Directory(p.join(appDoc.path, 'covers'));
      await coversDir.create(recursive: true);

      final scanner = LocalLibraryScanner(embeddedCoverDir: coversDir)
        ..onProgress = (path, found) {
          _scanningPath = path;
          _scanningFound = found;
          notifyListeners();
        };
      _activeScanner = scanner;

      final scanned = await scanner.scanRoots(_roots);
      await scanner.cleanOrphanEmbeddedCovers();
      await db.replaceAll(scanned);
      await _reloadWorks();
    } finally {
      _activeScanner = null;
      _scanning = false;
      _scanningPath = null;
      notifyListeners();
    }
  }

  void cancelScan() {
    _activeScanner?.cancelled = true;
  }

  // ---- 作品操作 ----

  Future<void> removeWork(Work work) async {
    final db = _db;
    if (db == null) return;
    await db.deleteWork(work.id, coverPath: work.coverPath);
    _works.removeWhere((w) => w.id == work.id);
    notifyListeners();
  }

  Future<List<FileNode>> nodesOf(Work work) async {
    final db = _db;
    if (db == null) return const [];
    return db.queryNodes(work.id);
  }

  Future<LibraryStats?> stats() async => _db?.stats();

  /// 同社团的其他本地作品（详情页推荐位，PRD §5.5 ⑪）。
  List<Work> relatedWorks(Work work, {int limit = 10}) {
    final circle = work.circleName;
    if (circle == null || circle.isEmpty) {
      // 无社团时回退到最近添加的其他作品。
      return _works
          .where((w) => w.id != work.id)
          .toList()
          .take(limit)
          .toList();
    }
    final related =
        _works.where((w) => w.id != work.id && w.circleName == circle).toList();
    if (related.length < limit) {
      for (final other in _works) {
        if (other.id == work.id ||
            other.circleName == circle ||
            related.contains(other)) {
          continue;
        }
        related.add(other);
        if (related.length >= limit) break;
      }
    }
    return related.take(limit).toList();
  }
}

/// JSON 编解码辅助（根目录列表持久化格式预留）。
String encodeRoots(List<String> roots) => jsonEncode(roots);
