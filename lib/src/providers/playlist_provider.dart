import 'package:flutter/foundation.dart';

import '../models/audio_track.dart';
import '../models/work.dart';
import '../services/local_library_database.dart';
import 'audio_provider.dart';
import 'library_provider.dart';
import '../utils/playback_helpers.dart';

/// 播放列表条目（展示模型）。
class PlaylistItem {
  const PlaylistItem({
    required this.id,
    required this.playlistId,
    this.workId,
    this.nodeId,
    required this.trackKey,
    required this.trackTitle,
    this.workTitle,
    this.coverPath,
  });

  final int id;
  final int playlistId;
  final int? workId;
  final int? nodeId;
  final String trackKey;
  final String trackTitle;
  final String? workTitle;
  final String? coverPath;
}

/// 播放列表（展示模型）。
class PlaylistInfo {
  const PlaylistInfo({
    required this.id,
    required this.name,
    this.description,
    required this.itemCount,
  });

  final int id;
  final String name;
  final String? description;
  final int itemCount;
}

/// 播放列表提供者（M7，PRD §5.8）。
class PlaylistProvider extends ChangeNotifier {
  PlaylistProvider({required this.library, required this.audio});

  final LibraryProvider library;
  final AudioPlayerProvider audio;

  List<PlaylistInfo> _playlists = const [];
  List<PlaylistInfo> get playlists => List.unmodifiable(_playlists);

  LocalLibraryDatabase? get _db => library.database;

  Future<void> refresh() async {
    final db = _db;
    if (db == null) return;
    final rows = await db.queryPlaylists();
    _playlists = rows
        .map((r) => PlaylistInfo(
              id: r['id'] as int,
              name: r['name'] as String,
              description: r['description'] as String?,
              itemCount: (r['item_count'] as num?)?.toInt() ?? 0,
            ))
        .toList();
    notifyListeners();
  }

  Future<void> create(String name, {String? description}) async {
    final db = _db;
    if (db == null || name.trim().isEmpty) return;
    final trimmedName = name.trim();
    final trimmedDesc = description?.trim();
    await db.insertPlaylist(
      trimmedName.substring(0, trimmedName.length.clamp(0, 50)),
      description: trimmedDesc == null || trimmedDesc.isEmpty
          ? null
          : trimmedDesc.substring(0, trimmedDesc.length.clamp(0, 200)),
    );
    await refresh();
  }

  Future<void> remove(int playlistId) async {
    await _db?.deletePlaylist(playlistId);
    await refresh();
  }

  Future<void> rename(int playlistId, String name) async {
    await _db?.renamePlaylist(playlistId, name);
    await refresh();
  }

  Future<List<PlaylistItem>> itemsOf(int playlistId) async {
    final db = _db;
    if (db == null) return const [];
    final rows = await db.queryPlaylistItems(playlistId);
    return rows
        .map((r) => PlaylistItem(
              id: r['id'] as int,
              playlistId: r['playlist_id'] as int,
              workId: r['work_id'] as int?,
              nodeId: r['node_id'] as int?,
              trackKey: r['track_key'] as String,
              trackTitle: r['track_title'] as String,
              workTitle: r['work_title'] as String?,
              coverPath: r['cover_path'] as String?,
            ))
        .toList();
  }

  /// 加入音轨（本地作品音轨节点）。
  Future<void> addTrack(int playlistId, Work work, FileNode node) async {
    await _db?.addPlaylistItem(playlistId, {
      'work_id': work.id,
      'node_id': node.id,
      'track_key': 'node_${node.id}',
      'track_title': node.displayName,
      'work_title': work.title,
      'cover_path': work.coverPath,
    });
    await refresh();
  }

  Future<void> removeItem(int itemId) async {
    await _db?.removePlaylistItem(itemId);
    await refresh();
  }

  Future<void> reorder(int playlistId, List<PlaylistItem> ordered) async {
    await _db?.reorderPlaylistItems(
        playlistId, ordered.map((i) => i.id).toList());
  }

  /// 整体播放：逐条重建音轨（work 队列中定位该曲），跳过失效条目。
  Future<int> playAll(int playlistId, {int startIndex = 0}) async {
    final items = await itemsOf(playlistId);
    final tracks = <AudioTrack>[];
    final startOffsets = <int>[]; // 每条 item 在 tracks 中的起始 index。
    for (final item in items) {
      final workId = item.workId;
      if (workId == null) continue;
      final work =
          library.works.where((w) => w.id == workId).firstOrNull;
      if (work == null) continue;
      final nodes = await library.nodesOf(work);
      final workTracks = tracksOf(work, nodes);
      if (workTracks.isEmpty) continue;
      startOffsets.add(tracks.length);
      tracks.addAll(workTracks);
    }
    if (tracks.isEmpty) return 0;
    // 起始条目定位。
    var index = 0;
    if (startIndex > 0 && startIndex < startOffsets.length) {
      index = startOffsets[startIndex];
    }
    await audio.playTracks(tracks, initialIndex: index);
    return tracks.length;
  }
}
