import 'package:flutter/foundation.dart';

import '../models/audio_track.dart';
import 'local_library_database.dart';

/// 播放历史条目（M7 首版，PRD §5.8）。
class HistoryEntry {
  const HistoryEntry({
    required this.trackKey,
    this.nodeId,
    this.workId,
    required this.trackTitle,
    required this.workTitle,
    this.coverPath,
    this.artworkUrl,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  /// 音轨唯一键（AudioTrack.id：`node_<id>` / `online_<workId>_<file>`）。
  final String trackKey;
  final int? nodeId;
  final int? workId;
  final String trackTitle;
  final String workTitle;
  final String? coverPath;
  final String? artworkUrl;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;

  double get progress =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;
}

/// 播放历史记录服务：周期（≤5s）与暂停/切歌/停止时写入断点（PRD §5.8 断点续播）。
class HistoryService {
  HistoryService(this.db);

  final LocalLibraryDatabase? db;

  /// 节流时间戳（public：暂停落盘时重置节流）。
  DateTime lastWriteAt = DateTime.fromMillisecondsSinceEpoch(0);

  void record(AudioTrack? track, int positionMs, int durationMs) {
    if (track == null || db == null || durationMs <= 0) return;
    // 节流：≤5 秒一次。
    final now = DateTime.now();
    if (now.difference(lastWriteAt).inMilliseconds < 5000) return;
    lastWriteAt = now;

    final nodeId = track.id.startsWith('node_')
        ? int.tryParse(track.id.substring(5))
        : null;
    final entry = HistoryEntry(
      trackKey: track.id,
      nodeId: nodeId,
      workId: null, // 由 DB 联查（node → work）补全。
      trackTitle: track.title,
      workTitle: track.artist ?? '',
      coverPath: track.artworkPath,
      artworkUrl: track.artworkUrl,
      positionMs: positionMs,
      durationMs: durationMs,
      updatedAt: now,
    );
    db!.upsertHistory(entry).catchError((e) {
      debugPrint('[History] 写入失败: $e');
    });
  }
}
