/// 本地作品库数据模型（PRD §6.1 本地化改造版）。
///
/// M2 范围：本地字段完整；NetMeta（网络参考元数据）M4 里程碑引入，
/// 届时在参考区展示、永不写回本模型。
library;

/// 封面来源标记（PRD §5.9.2：详情页与播放器统一走该降级链）。
enum CoverSource { localFile, embedded, placeholder }

/// 本地作品。
class Work {
  const Work({
    required this.id,
    this.rjCode,
    required this.title,
    this.circleName,
    this.vasNames = const [],
    this.tags = const [],
    required this.rootPath,
    this.coverPath,
    this.coverSource = CoverSource.placeholder,
    this.durationSeconds,
    required this.trackCount,
    this.hasLyric = false,
    this.hasSubtitle = false,
    this.nsfw,
    required this.addedAt,
  });

  final int id;

  /// RJ 号原文（如 "RJ123456"）；未识别作品为 null（待整理）。
  final String? rjCode;

  /// 本地标题：metadata.json > 文件夹名（去 RJ 前缀）。
  final String title;

  /// 社团名（本地 metadata.json）。
  final String? circleName;

  /// CV 名列表（本地 metadata.json vas；空时由 NetMeta 网络回填，用户决策）。
  final List<String> vasNames;

  /// 标签（本地 metadata.json tags；网络标签在 NetMeta）。
  final List<String> tags;

  /// RJ 文件夹绝对路径。
  final String rootPath;

  /// 封面绝对路径（localFile 原图直读 / embedded 落盘文件）。
  final String? coverPath;

  final CoverSource coverSource;

  /// 总时长（秒，音轨已知时长之和）；null = 未知。
  final int? durationSeconds;

  final int trackCount;

  /// 存在已关联 lrc 即 true。
  final bool hasLyric;

  /// 存在已关联 vtt/srt 即 true。
  final bool hasSubtitle;

  final bool? nsfw;

  final DateTime addedAt;

  Work copyWith({
    int? id,
    String? rjCode,
    String? title,
    String? circleName,
    List<String>? vasNames,
    List<String>? tags,
    String? rootPath,
    String? coverPath,
    CoverSource? coverSource,
    int? durationSeconds,
    int? trackCount,
    bool? hasLyric,
    bool? hasSubtitle,
    bool? nsfw,
    DateTime? addedAt,
  }) {
    return Work(
      id: id ?? this.id,
      rjCode: rjCode ?? this.rjCode,
      title: title ?? this.title,
      circleName: circleName ?? this.circleName,
      vasNames: vasNames ?? this.vasNames,
      tags: tags ?? this.tags,
      rootPath: rootPath ?? this.rootPath,
      coverPath: coverPath ?? this.coverPath,
      coverSource: coverSource ?? this.coverSource,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      trackCount: trackCount ?? this.trackCount,
      hasLyric: hasLyric ?? this.hasLyric,
      hasSubtitle: hasSubtitle ?? this.hasSubtitle,
      nsfw: nsfw ?? this.nsfw,
      addedAt: addedAt ?? this.addedAt,
    );
  }
}

/// 文件树节点（目录或音轨）。
class FileNode {
  const FileNode({
    required this.id,
    required this.workId,
    required this.isDirectory,
    required this.name,
    required this.relativePath,
    required this.parentPath,
    this.filePath,
    this.durationSeconds,
    this.lyricPath,
    this.subtitlePath,
    this.isSubtitleFile = false,
  });

  final int id;
  final int workId;

  /// true = 目录节点；false = 音轨节点。
  final bool isDirectory;

  /// 显示名（目录 = 文件夹名；音轨 = 文件名含扩展名）。
  final String name;

  /// 相对于作品根目录的路径（'/' 分隔）。
  final String relativePath;

  /// 父目录相对路径；'' = 根。
  final String parentPath;

  /// 音轨绝对路径（可播放源）。
  final String? filePath;

  /// 音轨时长（秒）；null = 未知。
  final int? durationSeconds;

  /// 已关联歌词绝对路径。
  final String? lyricPath;

  /// 已关联字幕绝对路径。
  final String? subtitlePath;

  /// 字幕/歌词文件节点（预览用；不进播放队列——tracksOf 会排除）。
  final bool isSubtitleFile;

  /// 播放器显示名（去扩展名）。
  String get displayName {
    if (isDirectory) return name;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

/// 扫描后的作品（写入数据库前的中间形态）。
class ScannedWork {
  const ScannedWork({
    this.rjCode,
    required this.title,
    this.circleName,
    this.vasNames = const [],
    this.tags = const [],
    required this.rootPath,
    this.coverPath,
    this.coverSource = CoverSource.placeholder,
    required this.durationSeconds,
    required this.trackCount,
    required this.hasLyric,
    required this.hasSubtitle,
    this.nsfw,
    required this.nodes,
  });

  final String? rjCode;
  final String title;
  final String? circleName;

  /// CV 名列表（本地 metadata.json vas）。
  final List<String> vasNames;

  /// 标签（本地 metadata.json tags）。
  final List<String> tags;
  final String rootPath;
  final String? coverPath;
  final CoverSource coverSource;
  final int? durationSeconds;
  final int trackCount;
  final bool hasLyric;
  final bool hasSubtitle;
  final bool? nsfw;

  /// 文件树节点（含目录与音轨，自然排序）。
  final List<ScannedNode> nodes;
}

/// 扫描后的文件树节点（未入库）。
class ScannedNode {
  const ScannedNode({
    required this.isDirectory,
    required this.name,
    required this.relativePath,
    required this.parentPath,
    this.filePath,
    this.durationSeconds,
    this.lyricPath,
    this.subtitlePath,
  });

  final bool isDirectory;
  final String name;
  final String relativePath;
  final String parentPath;
  final String? filePath;
  final int? durationSeconds;
  final String? lyricPath;
  final String? subtitlePath;
}

/// 库存储统计（PRD §5.9.3）。
class LibraryStats {
  const LibraryStats({
    required this.workCount,
    required this.trackCount,
    required this.lyricCount,
    required this.noCoverCount,
    required this.totalBytes,
  });

  final int workCount;
  final int trackCount;

  /// 已关联歌词的音轨数。
  final int lyricCount;

  /// 无封面作品数。
  final int noCoverCount;

  /// 音频文件总字节数。
  final int totalBytes;
}
