import 'package:flutter/foundation.dart';

import '../models/online_models.dart';
import '../providers/library_provider.dart';
import '../providers/mirror_provider.dart';

/// 在线模块状态（M12）：作品列表、分页、排序、已下载标识。
class OnlineProvider extends ChangeNotifier {
  OnlineProvider({required this.mirror, required this.library});

  final MirrorProvider mirror;
  final LibraryProvider library;

  List<OnlineWork> _works = [];
  int _currentPage = 0;
  int _totalPages = 1;
  bool _loading = false;
  String? _error;

  /// 排序（PRD §5.12：发行日 / 评分 / 销量 / 价格）。
  String _order = 'release';

  /// 详情缓存（避免重复拉取）。
  final Map<int, OnlineWork> _detailCache = {};

  /// 书签收藏状态（服务端同步；游客模式仅本地内存态）。
  final Set<int> _favoriteIds = {};
  bool favoritesLoaded = false;

  Set<int> get favoriteIds => Set.unmodifiable(_favoriteIds);

  Future<void> loadFavorites() async {
    if (favoritesLoaded) return;
    try {
      final works = await mirror.api.getFavorites();
      _favoriteIds
        ..clear()
        ..addAll(works.map((w) => w.id));
      favoritesLoaded = true;
      debugPrint('[Online] 书签加载: ${_favoriteIds.length} 个');
      notifyListeners();
    } catch (_) {
      // 游客/未登录：书签功能降级为本地内存态。
    }
  }

  Future<void> toggleFavorite(int workId) async {
    final isFav = _favoriteIds.contains(workId);
    // 乐观更新。
    isFav ? _favoriteIds.remove(workId) : _favoriteIds.add(workId);
    notifyListeners();
    try {
      isFav
          ? await mirror.api.removeFromFavorites(workId)
          : await mirror.api.addToFavorites(workId);
    } catch (_) {
      // 回滚。
      isFav ? _favoriteIds.add(workId) : _favoriteIds.remove(workId);
      notifyListeners();
    }
  }

  List<OnlineWork> get favoriteWorks =>
      _works.where((w) => _favoriteIds.contains(w.id)).toList();

  bool _showFavoritesOnly = false;
  bool get showFavoritesOnly => _showFavoritesOnly;
  void toggleFavoritesOnly() {
    _showFavoritesOnly = !_showFavoritesOnly;
    notifyListeners();
  }

  /// 展示列表：收藏模式时过滤书签作品。
  List<OnlineWork> get works =>
      List.unmodifiable(_showFavoritesOnly
          ? _works.where((w) => _favoriteIds.contains(w.id)).toList()
          : _works);
  bool get loading => _loading;
  String? get error => _error;
  String get order => _order;

  bool get hasMore => _currentPage < _totalPages;

  /// 已下载作品 RJ 号集合（在线封面墙角标，PRD §5.12）。
  Set<String> get downloadedRjCodes =>
      library.works.map((w) => w.rjCode).whereType<String>().toSet();

  /// 切换排序并重载。
  Future<void> setOrder(String order) async {
    if (_order == order) return;
    _order = order;
    await refresh();
  }

  Future<void> refresh() async {
    _works = [];
    _currentPage = 0;
    _totalPages = 1;
    notifyListeners();
    await loadMore();
  }

  /// 加载下一页（滚动加载）。
  Future<void> loadMore() async {
    if (_loading || !hasMore) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final page = await mirror.api.getWorks(
        page: _currentPage + 1,
        order: _order,
      );
      mirror.reportRequestSuccess();
      _works = [..._works, ...page.works];
      _currentPage = page.currentPage;
      _totalPages = page.totalPages;
      debugPrint('[Online] 加载第 $_currentPage 页，共 ${_works.length} 作品');
    } catch (e) {
      mirror.reportRequestFailure();
      _error = '加载失败：$e';
      debugPrint('[Online] 加载失败: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 作品详情（含文件树，缓存）。
  Future<OnlineWork> getWorkDetail(int workId) async {
    final cached = _detailCache[workId];
    if (cached != null) return cached;
    final work = await mirror.api.getWork(workId);
    mirror.reportRequestSuccess();
    _detailCache[workId] = work;
    return work;
  }

  /// 展开文件树中的全部音轨（扁平列表，用于播放队列）。
  List<OnlineFileNode> flattenAudioNodes(List<OnlineFileNode> nodes) {
    final result = <OnlineFileNode>[];
    for (final node in nodes) {
      if (node.isFolder) {
        result.addAll(flattenAudioNodes(node.children));
      } else if (node.isAudio) {
        result.add(node);
      }
    }
    return result;
  }

  /// 展开可下载文件：音频 + 字幕/歌词（本地为主：下载入库后字幕可用）。
  static const _downloadableExts = {
    '.mp3', '.m4a', '.flac', '.wav', '.ogg', '.opus',
    '.srt', '.vtt', '.lrc', '.txt',
  };

  List<OnlineFileNode> flattenDownloadable(List<OnlineFileNode> nodes) {
    final result = <OnlineFileNode>[];
    void walk(List<OnlineFileNode> list) {
      for (final node in list) {
        if (node.isFolder) {
          walk(node.children);
        } else if (node.title.contains('.') &&
            _downloadableExts.contains(node.title
                .substring(node.title.lastIndexOf('.'))
                .toLowerCase())) {
          result.add(node);
        }
      }
    }

    walk(nodes);
    return result;
  }

  void clearCache() => _detailCache.clear();
}
