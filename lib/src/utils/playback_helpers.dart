import '../models/audio_track.dart';
import '../models/work.dart';

/// 从作品文件节点构建播放音轨队列（PRD §5.6.0 信息展示层级）。
///
/// 音轨名（去扩展名）、作品名、封面、歌词路径全部取本地值；
/// 网络元数据不进入播放队列。
List<AudioTrack> tracksOf(Work work, List<FileNode> nodes) {
  return nodes
      .where((node) =>
          !node.isDirectory &&
          !node.isSubtitleFile &&
          !node.isImageFile &&
          !node.isVideoFile &&
          node.filePath != null)
      .map((node) => AudioTrack(
            id: 'node_${node.id}',
            title: node.displayName,
            artist: work.title,
            source: node.filePath!,
            artworkPath: work.coverPath,
            lyricPath: node.lyricPath,
          ))
      .toList();
}
