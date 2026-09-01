import 'package:dio/dio.dart';

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
    return OnlineWorksPage(
      works: works,
      currentPage: (pagination['currentPage'] as num?)?.toInt() ?? page,
      totalPages: (pagination['totalPages'] as num?)?.toInt() ?? 1,
      totalItems: (pagination['totalItems'] as num?)?.toInt() ?? works.length,
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
