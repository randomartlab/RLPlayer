import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/net_meta.dart';
import '../models/work.dart';
import '../services/local_library_database.dart';
import '../services/local_library_scanner.dart';

/// 排序方式（作品库，PRD §5.4 排序/筛选）。
/// 本地作品排序维度（2026-09-02 新增网络元数据排序 + 正逆序）。
enum WorkSortBy { title, addedAt, rjCode, netRating, netDlCount, netRateCount }

/// 本地库提供者：扫描根目录管理、扫描执行、作品列表、移出库、统计。
class LibraryProvider extends ChangeNotifier {
  static const String _rootsKey = 'scan_roots';

  LocalLibraryDatabase? _db;

  /// 供 M11 NetMeta 等服务复用（M2 单库设计）。
  LocalLibraryDatabase? get database => _db;

  List<String> _roots = [];
  List<Work> _works = [];

  // 本机喜欢（独立于 one 站收藏；v10，2026-09-03）。
  final Set<String> _likedRj = {};
  final Map<String, String> _likedTitles = {};

  /// 扫描状态。
  bool _scanning = false;
  String? _scanningPath;
  int _scanningFound = 0;

  List<String> get roots => List.unmodifiable(_roots);
  List<Work> get works => List.unmodifiable(_works);
  Set<String> get likedRjCodes => Set.unmodifiable(_likedRj);
  Map<String, String> get likedTitles => Map.unmodifiable(_likedTitles);
  bool get scanning => _scanning;
  String? get scanningPath => _scanningPath;
  int get scanningFound => _scanningFound;

  WorkSortBy sortBy = WorkSortBy.title;

  /// true = 降序（默认）；false = 升序。
  bool sortDescending = true;

  // ---- 筛选（社团/CV/标签，2026-09-02）----
  String? filterCircle;
  String? filterVas;
  final Set<String> filterTags = {};

  // ---- 网络元数据（排序用；懒加载）----
  final Map<String, NetMeta> _netMetas = {};
  bool _netMetaLoaded = false;

  LibraryProvider() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getStringList(_rootsKey) ?? [];
    _roots = encoded;
    _db = await LocalLibraryDatabase.open();
    await _reloadWorks();
    await _loadLikes();
    notifyListeners();
  }

  Future<void> _loadLikes() async {
    final db = _db;
    if (db == null) return;
    final rows = await db.allLikes();
    _likedRj
      ..clear()
      ..addAll(rows.map((r) => r['rj_code'] as String));
    _likedTitles.clear();
    for (final r in rows) {
      _likedTitles[r['rj_code'] as String] = (r['title'] ?? '') as String;
    }
  }

  /// 作品来源文件夹标签：优先 source_root（扫描根）；旧数据按最长前缀
  /// 匹配扫描根推断；否则取作品目录的父目录名（2026-09-04）。
  String folderLabelOf(Work w) {
    final sr = w.sourceRoot;
    if (sr != null && sr.isNotEmpty) {
      return sr.split(RegExp(r'[/\\]')).last;
    }
    String? best;
    for (final r in _roots) {
      if (w.rootPath == r || w.rootPath.startsWith('$r/')) {
        if (best == null || r.length > best.length) best = r;
      }
    }
    if (best != null) return best.split(RegExp(r'[/\\]')).last;
    final seg = w.rootPath.split(RegExp(r'[/\\]'));
    return seg.length >= 2 ? seg[seg.length - 2] : (seg.isNotEmpty ? seg.last : '');
  }

  /// 全部来源文件夹名（有作品的），供筛选 chips。
  List<String> get sourceFolders {
    final set = <String>{};
    for (final w in _works) {
      final label = folderLabelOf(w);
      if (label.isNotEmpty) set.add(label);
    }
    return set.toList()..sort();
  }

  bool isLiked(String rjCode) => _likedRj.contains(rjCode);

  /// 切换本机喜欢并落库。
  Future<void> toggleLike(String rjCode, String title) async {
    final db = _db;
    if (db == null) return;
    final liked = _likedRj.contains(rjCode);
    await db.setLiked(rjCode, title, liked: !liked);
    if (liked) {
      _likedRj.remove(rjCode);
      _likedTitles.remove(rjCode);
    } else {
      _likedRj.add(rjCode);
      _likedTitles[rjCode] = title;
    }
    notifyListeners();
  }

  Future<void> _reloadWorks() async {
    final db = _db;
    if (db == null) return;
    _works = await db.queryWorks();
    _sortWorks();
  }

  /// 公开刷新（后台 NetMeta 回填含封面落盘后调用，2026-09-02）。
  Future<void> reloadWorks() async {
    await _reloadWorks();
    notifyListeners();
  }

  void _sortWorks() {
    int compare(Work a, Work b) {
      switch (sortBy) {
        case WorkSortBy.title:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case WorkSortBy.addedAt:
          return b.addedAt.compareTo(a.addedAt);
        case WorkSortBy.rjCode:
          return (a.rjCode ?? 'zzz').compareTo(b.rjCode ?? 'zzz');
        case WorkSortBy.netRating:
          return ((netMetaOf(b)?.netRateAverage ?? -1)
                  .compareTo(netMetaOf(a)?.netRateAverage ?? -1));
        case WorkSortBy.netDlCount:
          return (netMetaOf(b)?.netDlCount ?? -1)
              .compareTo(netMetaOf(a)?.netDlCount ?? -1);
        case WorkSortBy.netRateCount:
          return (netMetaOf(b)?.netRateCount ?? -1)
              .compareTo(netMetaOf(a)?.netRateCount ?? -1);
      }
    }

    final sorted = [..._works]..sort(compare);
    // 升序 = 反转（默认全部按"优/新在前"实现，toggle 反转）。
    _works = sortDescending ? sorted : sorted.reversed.toList();
  }

  Future<void> setSortBy(WorkSortBy value) async {
    sortBy = value;
    _sortWorks();
    notifyListeners();
  }

  Future<void> setSortDescending(bool value) async {
    sortDescending = value;
    _sortWorks();
    notifyListeners();
  }

  // ---- 筛选 ----

  /// 应用筛选后的作品列表（社团/CV/标签 AND 组合）。
  List<Work> get visibleWorks {
    if (filterCircle == null &&
        filterVas == null &&
        filterTags.isEmpty) {
      return List.unmodifiable(_works);
    }
    return List.unmodifiable(_works.where((w) {
      if (filterCircle != null && w.circleName != filterCircle) {
        // 兼容网络回填的社团名。
        final meta = netMetaOf(w);
        if (meta?.netCircle != filterCircle) return false;
      }
      if (filterVas != null &&
          !w.vasNames.contains(filterVas) &&
          !(netMetaOf(w)?.netVas.contains(filterVas) ?? false)) {
        return false;
      }
      if (filterTags.isNotEmpty &&
          !filterTags.every((t) =>
              w.tags.contains(t) ||
              (netMetaOf(w)?.netTags.contains(t) ?? false))) {
        return false;
      }
      return true;
    }));
  }

  Future<void> setFilterCircle(String? value) async {
    filterCircle = value;
    notifyListeners();
  }

  Future<void> setFilterVas(String? value) async {
    filterVas = value;
    notifyListeners();
  }

  Future<void> toggleFilterTag(String tag) async {
    if (filterTags.contains(tag)) {
      filterTags.remove(tag);
    } else {
      filterTags.add(tag);
    }
    notifyListeners();
  }

  Future<void> clearFilters() async {
    filterCircle = null;
    filterVas = null;
    filterTags.clear();
    notifyListeners();
  }

  /// 作品的网络元数据（排序/筛选用）。
  NetMeta? netMetaOf(Work work) {
    if (work.rjCode == null) return null;
    return _netMetas[work.rjCode];
  }

  /// 懒加载全部 NetMeta（首次按网络排序/筛选时触发）。
  Future<void> _ensureNetMetas() async {
    if (_netMetaLoaded || _db == null) return;
    final metas = await _db!.queryAllNetMeta();
    for (final m in metas) {
      _netMetas[m.rjCode] = m;
    }
    _netMetaLoaded = true;
  }

  /// 排序切换到网络维度前的预热入口。
  Future<void> warmNetMetas() async {
    await _ensureNetMetas();
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

  /// 最近一次扫描的统计（供 UI 反馈"无添加"原因）。
  int _lastScannedWorks = 0;
  String? _lastScanError;

  int get lastScannedWorks => _lastScannedWorks;
  String? get lastScanError => _lastScanError;

  /// 手动补录 RJ 号（详情页对未识别作品，2026-09-02）。
  Future<bool> setWorkRjCode(int workId, String rjCode) async {
    final db = _db;
    if (db == null) return false;
    await db.updateWorkRjCode(workId, rjCode.toUpperCase());
    await reloadWork(workId);
    return true;
  }

  Future<void> rescan() async {
    if (_scanning) return;
    final db = _db;
    if (db == null || _roots.isEmpty) return;

    _scanning = true;
    _scanningPath = null;
    _scanningFound = 0;
    _lastScannedWorks = 0;
    _lastScanError = null;
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
      _lastScannedWorks = scanned.length;
    } catch (e) {
      _lastScanError = e.toString();
      rethrow;
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

  /// 重新读取单个作品（封面兜底回写后刷新显示）。
  Future<Work?> reloadWork(int workId) async {
    final db = _db;
    if (db == null) return null;
    final fresh = await db.queryWork(workId);
    if (fresh != null) {
      final index = _works.indexWhere((w) => w.id == workId);
      if (index >= 0) {
        _works[index] = fresh;
        notifyListeners();
      }
    }
    return fresh;
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
