/// M1 音轨模型（简化版；完整 Work/文件树模型随 M2 本地识别引擎引入）。
class AudioTrack {
  final String id;
  final String title;
  final String? artist;

  /// 音源：`asset:` 前缀 / 本地绝对路径 / http(s) URL。
  final String source;

  /// 封面：本地绝对路径或 asset 路径；null 时用占位封面。
  final String? artworkPath;

  /// 关联歌词（lrc 解析结果）；M1 由资产/手动加载，M2 由本地识别引擎自动关联。
  final String? lyricPath;

  const AudioTrack({
    required this.id,
    required this.title,
    this.artist,
    required this.source,
    this.artworkPath,
    this.lyricPath,
  });
}
