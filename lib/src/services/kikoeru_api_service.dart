import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/online_models.dart';

/// Kikoeru API 客户端（M12，KikoFlu `kikoeru_api_service.dart` 精简移植）。
///
/// 所有请求发往当前镜像实例；镜像选择由 `MirrorProvider` 负责，
/// 切换镜像时调用 [switchHost]。
class KikoeruApiService {
  KikoeruApiService() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Accept': 'application/json'},
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null && _token!.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        handler.next(options);
      },
    ));
  }

  late final Dio _dio;
  String? _host;
  String? _token;

  /// 当前镜像 base URL（含 https:// 前缀）。
  String get host => _host ?? '';
  String? get token => _token;

  void init(String host, [String? token]) {
    _host = normalizeHost(host);
    _token = token;
    _dio.options.baseUrl = _host!;
  }

  void switchHost(String host, [String? token]) => init(host, token);

  static String normalizeHost(String host) {
    if (host.startsWith('http://') || host.startsWith('https://')) {
      return host;
    }
    return 'https://$host';
  }

  // ---- 健康检查 / 测速（PRD 决策 1：超时 5s，取响应时间） ----

  /// 返回镜像延迟（ms）；不可达返回 null。
  static Future<int?> healthCheck(String host) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      validateStatus: (status) => status != null && status < 500,
    ));
    final sw = Stopwatch()..start();
    try {
      await dio.get('${normalizeHost(host)}/api/health');
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    } finally {
      dio.close();
    }
  }

  // ---- 账号 ----

  Future<OnlineUser> login(String name, String password) async {
    final response = await _dio.post('/api/auth/me', data: {
      'name': name,
      'password': password,
    });
    final data = response.data as Map<String, dynamic>;
    final token = data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw KikoeruApiException('登录失败：服务端未返回 token', null);
    }
    _token = token;
    return OnlineUser(
      id: (data['id'] as num?)?.toInt() ?? 0,
      name: (data['name'] ?? name) as String,
    );
  }

  void logout() => _token = null;

  // ---- 作品列表（游客可浏览） ----

  /// order: release / rating / dl_count / price（PRD §5.12 排序）。
  Future<OnlineWorksPage> getWorks({
    int page = 1,
    int pageSize = 20,
    String order = 'release',
    String sort = 'desc',
  }) async {
    final response = await _dio.get('/api/works', queryParameters: {
      'page': page,
      'pageSize': pageSize,
      'order': order,
      'sort': sort,
      'subtitle': 0,
    });
    final data = response.data as Map<String, dynamic>;
    final pagination = (data['pagination'] ?? {}) as Map<String, dynamic>;
    final works = ((data['works'] ?? []) as List)
        .map((w) => OnlineWork.fromJson(w as Map<String, dynamic>))
        .toList();
    // asmr.one 实测返回 {currentPage, pageSize, totalCount}（无 totalPages），
    // 用 totalCount/pageSize 推导；兼容直接返回 totalPages 的镜像。
    final currentPage = (pagination['currentPage'] as num?)?.toInt() ?? page;
    final totalCount =
        (pagination['totalCount'] ?? pagination['totalItems'] as num?)
                ?.toInt() ??
            works.length;
    final explicitTotalPages = (pagination['totalPages'] as num?)?.toInt();
    final totalPages = explicitTotalPages ??
        (pageSize > 0 ? (totalCount / pageSize).ceil() : 1);
    return OnlineWorksPage(
      works: works,
      currentPage: currentPage,
      totalPages: totalPages,
      totalItems: totalCount,
    );
  }

  // ---- 作品详情（含文件树） ----

  Future<OnlineWork> getWork(int workId) async {
    final response = await _dio.get('/api/work/$workId?v=2');
    return OnlineWork.fromJson(response.data as Map<String, dynamic>);
  }

  // ---- 文件树（独立接口，PRD §5.12 音轨树） ----

  Future<List<OnlineFileNode>> getTracks(int workId) async {
    final response = await _dio.get('/api/tracks/$workId');
    return ((response.data as List?) ?? const [])
        .map((node) => OnlineFileNode.fromJson(node as Map<String, dynamic>))
        .toList();
  }

  /// 作品列表（带分类参数：nsfw 年龄分级 / subtitle 字幕过滤）。
  Future<OnlineWorksPage> getWorksFiltered({
    int page = 1,
    int pageSize = 20,
    String order = 'release',
    String sort = 'desc',
    int? nsfw,
    int? subtitle,
  }) async {
    final response = await _dio.get('/api/works', queryParameters: {
      'page': page,
      'pageSize': pageSize,
      'order': order,
      'sort': sort,
      'subtitle': subtitle ?? 0,
      'nsfw': ?nsfw,
    });
    final data = response.data as Map<String, dynamic>;
    final pagination = (data['pagination'] ?? {}) as Map<String, dynamic>;
    final works = ((data['works'] ?? []) as List)
        .map((w) => OnlineWork.fromJson(w as Map<String, dynamic>))
        .toList();
    final currentPage = (pagination['currentPage'] as num?)?.toInt() ?? page;
    final totalCount =
        (pagination['totalCount'] ?? pagination['totalItems'] as num?)
                ?.toInt() ??
            works.length;
    final explicitTotalPages = (pagination['totalPages'] as num?)?.toInt();
    final totalPages = explicitTotalPages ??
        (pageSize > 0 ? (totalCount / pageSize).ceil() : 1);
    return OnlineWorksPage(
      works: works,
      currentPage: currentPage,
      totalPages: totalPages,
      totalItems: totalCount,
    );
  }

  /// 关键词搜索（在线标签过滤：标签名作关键词）。
  Future<List<OnlineWork>> searchWorks(String keyword,
      {int pageSize = 20}) async {
    final encoded = Uri.encodeComponent(keyword);
    final response = await _dio.get('/api/search/$encoded',
        queryParameters: {
          'page': 1,
          'pageSize': pageSize,
          'order': 'release',
          'sort': 'desc',
        });
    final data = response.data as Map<String, dynamic>;
    return (((data['works'] ?? const []) as List))
        .map((w) => OnlineWork.fromJson(w as Map<String, dynamic>))
        .toList();
  }

  /// 全部标签（搜索选择器；按使用数排序——API 无 count 排序参数，
  /// 实测返回字母序，2026-09-02 客户端排序兜底）。
  Future<List<Map<String, dynamic>>> getAllTags() async {
    final response = await _dio.get('/api/tags/',
        queryParameters: {'pageSize': 500});
    final data = response.data;
    return _sortByCount(data is List ? data : (data as Map)['tags']);
  }

  /// 全部声优（搜索选择器；按作品数客户端排序）。
  Future<List<Map<String, dynamic>>> getAllVas() async {
    final response = await _dio.get('/api/vas/',
        queryParameters: {'pageSize': 1000});
    final data = response.data;
    return _sortByCount(data is List ? data : (data as Map)['vas']);
  }

  /// 全部社团（搜索选择器；按作品数客户端排序）。
  Future<List<Map<String, dynamic>>> getAllCircles() async {
    final response = await _dio.get('/api/circles/',
        queryParameters: {'pageSize': 1000});
    final data = response.data;
    return _sortByCount(data is List ? data : (data as Map)['circles']);
  }

  /// 按 count 字段降序（选择器「作品量优先」而非 A-Z，实机反馈 2026-09-02）。
  static List<Map<String, dynamic>> _sortByCount(dynamic raw) {
    return ((raw as List? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList())
      ..sort((a, b) => ((b['count'] as num?) ?? 0)
          .compareTo((a['count'] as num?) ?? 0));
  }

  /// 作品评论（需登录 token；游客返回 null，2026-09-02）。
  ///
  /// 轮询多个候选端点（review / reviews / works/{id}/reviews），
  /// 取首个非空（2026-09-02 实测：kikoeru 不同部署端点不一致）。
  /// 404 = 无评论/未收录 → 空列表。
  Future<List<Map<String, dynamic>>?> getWorkReviews(int workId,
      {int page = 1, int pageSize = 20}) async {
    if (_token == null || _token!.isEmpty) return null;
    final endpoints = [
      '/api/review/$workId',
      '/api/reviews/$workId',
      '/api/works/$workId/reviews',
    ];
    for (final ep in endpoints) {
      try {
        final response = await _dio.get(ep,
            queryParameters: {'page': page, 'pageSize': pageSize});
        final extracted = _extractReviewList(response.data);
        if (extracted.isNotEmpty) {
          return extracted;
        }
        if (response.data is Map) {
          final keys = (response.data as Map).keys.take(12).toList();
          debugPrint('[Review] $ep 响应键 $keys 无条目');
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 404 || e.response?.statusCode == 401) {
          debugPrint('[Review] $ep -> ${e.response?.statusCode}');
          continue; // 该端点无数据/无权限 → 试下一个。
        }
        debugPrint('[Review] $ep 异常: $e');
        continue;
      }
    }
    return const [];
  }

  /// 评论列表多 key 递归提取（reviews/comments/data/items/results）。
  static List<Map<String, dynamic>> _extractReviewList(dynamic data) {
    final out = <Map<String, dynamic>>[];
    void walk(dynamic node) {
      if (node is List) {
        for (final item in node) {
          if (item is Map) {
            // 条目可能直接是评论，也可能包在 'review'/'comment' 下。
            final inner = (item['review'] ?? item['comment']) is Map
                ? (item['review'] ?? item['comment']) as Map
                : item;
            out.add(Map<String, dynamic>.from(inner));
          } else {
            walk(item);
          }
        }
      } else if (node is Map) {
        const keys = [
          'reviews', 'comments', 'data', 'items', 'results', 'list',
        ];
        for (final k in keys) {
          if (node[k] != null) walk(node[k]);
        }
      }
    }

    walk(data);
    // 去重（id/time+rating 相同判重）。
    final seen = <String>{};
    return out.where((m) {
      final id =
          '${m['id'] ?? m['time'] ?? m['rating']}_${m['comment'] ?? ''}';
      return seen.add(id);
    }).toList();
  }

  /// 声优的全部作品（搜索按 CV 选取后检索）。
  Future<List<OnlineWork>> getVaWorks(String vaId,
      {int pageSize = 20}) async {
    final response = await _dio.get('/api/vas/$vaId/works',
        queryParameters: {'page': 1, 'pageSize': pageSize});
    final data = response.data as Map<String, dynamic>;
    return (((data['works'] ?? const []) as List))
        .map((w) => OnlineWork.fromJson(w as Map<String, dynamic>))
        .toList();
  }

  /// 社团作品（分页 + 排序；社团模式页，2026-09-02）。
  Future<List<OnlineWork>> getCircleWorksPage(int circleId, int page,
      {int pageSize = 20, String order = 'release'}) async {
    final response = await _dio.get('/api/circles/$circleId/works',
        queryParameters: {
          'page': page,
          'pageSize': pageSize,
          'order': order,
          'sort': 'desc',
        });
    final data = response.data as Map<String, dynamic>;
    return (((data['works'] ?? const []) as List))
        .map((w) => OnlineWork.fromJson(w as Map<String, dynamic>))
        .toList();
  }

  /// 同社团作品（本地详情页网络相关推荐，M5 用户需求）。
  Future<List<OnlineWork>> getCircleWorks(int circleId,
      {int pageSize = 10}) async {
    final response = await _dio.get('/api/circles/$circleId/works',
        queryParameters: {
          'page': 1,
          'pageSize': pageSize,
          'order': 'release',
          'sort': 'desc',
        });
    final data = response.data as Map<String, dynamic>;
    return (((data['works'] ?? data['pagination']?['works']) as List? ?? const []))
        .map((w) => OnlineWork.fromJson(w as Map<String, dynamic>))
        .toList();
  }

  // ---- 收藏（服务端书签） ----

  Future<List<OnlineWork>> getFavorites({int page = 1}) async {
    final response = await _dio.get('/api/favourites', queryParameters: {
      'page': page,
      'pageSize': 20,
    });
    final data = response.data as Map<String, dynamic>;
    return (((data['works'] ?? data['favourites'] ?? []) as List))
        .map((w) => OnlineWork.fromJson(w as Map<String, dynamic>))
        .toList();
  }

  Future<void> addToFavorites(int workId) =>
      _dio.put('/api/favourites/$workId');

  Future<void> removeFromFavorites(int workId) =>
      _dio.delete('/api/favourites/$workId');

  // ---- 媒体 URL（token 走查询参数，播放器无需 Authorization header） ----

  /// 下载封面字节（网络封面兜底落盘用）。
  Future<List<int>?> downloadCover(int workId) async {
    try {
      final response = await _dio.get<List<int>>(coverUrl(workId),
          options: Options(responseType: ResponseType.bytes));
      return response.data;
    } catch (_) {
      return null;
    }
  }

  String coverUrl(int workId) =>
      '$_host/api/cover/$workId${_token != null && _token!.isNotEmpty ? '?token=$_token' : ''}';

  String streamUrl(String hash, String fileName) =>
      '$_host/api/media/stream/$hash/$fileName';

  String downloadUrl(String hash, String fileName) =>
      '$_host/api/media/download/$hash/$fileName';

  /// 文件节点的下载 URL（优先服务端提供的 mediaDownloadUrl）。
  String nodeDownloadUrl(OnlineFileNode node) {
    final mediaDownloadUrl = node.mediaDownloadUrl;
    if (mediaDownloadUrl != null && mediaDownloadUrl.isNotEmpty) {
      return mediaDownloadUrl;
    }
    final hash = node.hash;
    if (hash == null || hash.isEmpty) {
      throw KikoeruApiException('文件缺少 hash，无法下载', null);
    }
    return downloadUrl(hash, Uri.encodeComponent(node.title));
  }

  /// 文件节点的流媒体 URL（优先服务端提供的 mediaStreamUrl）。
  String nodeStreamUrl(OnlineFileNode node) {
    final mediaStreamUrl = node.mediaStreamUrl;
    if (mediaStreamUrl != null && mediaStreamUrl.isNotEmpty) {
      return mediaStreamUrl;
    }
    final hash = node.hash;
    if (hash == null || hash.isEmpty) {
      throw KikoeruApiException('文件缺少 hash，无法播放', null);
    }
    return streamUrl(hash, Uri.encodeComponent(node.title));
  }

}

/// 作品列表分页。
class OnlineWorksPage {
  const OnlineWorksPage({
    required this.works,
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
  });

  final List<OnlineWork> works;
  final int currentPage;
  final int totalPages;
  final int totalItems;

  bool get hasMore => currentPage < totalPages;
}

class KikoeruApiException implements Exception {
  KikoeruApiException(this.message, this.originalError);

  final String message;
  final dynamic originalError;

  @override
  String toString() => 'KikoeruApiException: $message ($originalError)';
}
