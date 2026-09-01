/// 在线模块数据模型（M12，Kikoeru API 响应映射）。
library;


/// 在线作品（/api/works 列表项 + /api/work/{id} 详情）。
class OnlineWork {
  const OnlineWork({
    required this.id,
    required this.title,
    this.titleTranslation,
    this.circleName,
    this.circleId,
    this.vas = const [],
    this.tags = const [],
    this.nsfw = false,
    this.release,
    this.dlCount,
    this.ratingCount,
    this.price,
    this.averageRating,
    this.description,
    this.children,
  });

  final int id;
  final String title;
  final String? titleTranslation;
  final String? circleName;

  /// 服务端社团 id（相关推荐按社团检索用）。
  final int? circleId;
  final List<String> vas;
  final List<String> tags;
  final bool nsfw;
  final DateTime? release;
  final int? dlCount;
  final int? ratingCount;
  final int? price;
  final double? averageRating;
  final String? description;

  /// 文件树（详情接口返回；列表接口为 null）。
  final List<OnlineFileNode>? children;

  factory OnlineWork.fromJson(Map<String, dynamic> json) {
    return OnlineWork(
      id: json['id'] as int,
      title: (json['title'] ?? '') as String,
      titleTranslation: json['titleTranslation'] as String?,
      circleName: (json['circle'] as Map<String, dynamic>?)?['name']
          as String?,
      circleId: ((json['circle'] as Map<String, dynamic>?)?['id'] as num?)
          ?.toInt(),
      vas: ((json['vas'] as List?) ?? const [])
          .map((va) => ((va as Map)['name'] ?? '') as String)
          .where((name) => name.isNotEmpty)
          .toList(),
      tags: ((json['tags'] as List?) ?? const [])
          .map((tag) => ((tag as Map)['name'] ?? '') as String)
          .where((name) => name.isNotEmpty)
          .toList(),
      nsfw: json['nsfw'] == true || json['nsfw'] == 1,
      release: DateTime.tryParse((json['release'] ?? '') as String),
      dlCount: json['dlCount'] as int?,
      ratingCount: json['ratingCount'] as int?,
      price: json['price'] as int?,
      averageRating: (json['averageRating'] as num?)?.toDouble(),
      description: json['description'] as String?,
      children: (json['children'] as List?)
          ?.map((child) =>
              OnlineFileNode.fromJson(child as Map<String, dynamic>))
          .toList(),
    );
  }

  /// RJ 号（服务端 id 即 DLsite 编号）。
  String get rjCode => 'RJ${id.toString().padLeft(6, '0')}';
}

/// 在线文件树节点（type: folder / audio / video / text / image / other）。
class OnlineFileNode {
  const OnlineFileNode({
    required this.type,
    required this.title,
    this.hash,
    this.size,
    this.mediaStreamUrl,
    this.mediaDownloadUrl,
    this.children = const [],
  });

  final String type;
  final String title;

  /// 文件哈希（流媒体/下载 URL 的钥匙）。
  final String? hash;

  final int? size;
  final String? mediaStreamUrl;

  /// 服务端提供的完整下载 URL（raw 镜像域名）。
  final String? mediaDownloadUrl;
  final List<OnlineFileNode> children;

  bool get isFolder => type == 'folder';

  bool get isAudio => type == 'audio';

  factory OnlineFileNode.fromJson(Map<String, dynamic> json) {
    return OnlineFileNode(
      type: (json['type'] ?? 'file') as String,
      title: (json['title'] ?? json['name'] ?? '') as String,
      hash: json['hash'] as String?,
      size: json['size'] as int?,
      mediaStreamUrl: json['mediaStreamUrl'] as String?,
      mediaDownloadUrl: json['mediaDownloadUrl'] as String?,
      children: ((json['children'] as List?) ?? const [])
          .map((child) => OnlineFileNode.fromJson(child as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 已登录用户信息。
class OnlineUser {
  const OnlineUser({required this.id, required this.name});

  final int id;
  final String name;
}
