/// M1 音轨模型（简化版；完整 Work/文件树模型随 M2 本地识别引擎引入）。
class AudioTrack {
  final String id;
  final String title;
  final String? artist;

  /// 音源：`asset:` 前缀 / 本地绝对路径 / http(s) URL。
  final String source;

  /// 封面：本地绝对路径或 asset 路径；null 时用占位封面。
  final String? artworkPath;

  /// 网络封面 URL（在线流播时使用，PRD §5.6.0 封面降级链的网络层）。
  final String? artworkUrl;

  /// 关联歌词（lrc 解析结果）；M1 由资产/手动加载，M2 由本地识别引擎自动关联。
  final String? lyricPath;

  /// 在线字幕 URL（vtt/srt，在线播放自动匹配）。
  final String? subtitleUrl;

  /// 本地字幕文件路径（vtt/srt，在线播放按 RJ 号从本地库回填；本地优先）。
  final String? subtitlePath;

  const AudioTrack({
    required this.id,
    required this.title,
    this.artist,
    required this.source,
    this.artworkPath,
    this.artworkUrl,
    this.lyricPath,
    this.subtitleUrl,
    this.subtitlePath,
  });
}
