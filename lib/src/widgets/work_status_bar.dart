/// 作品操作条（详情页：标记进度五态 + 我的评分 + 收藏 + 喜欢，2026-09-03）。
///
/// 数据模型对齐 kikoeru/kikoflu 服务端 /api/review 协议：
/// - 状态 progress：marked(想听)/listening(在听)/listened(听过)/replay(回味)/postponed(搁置)
/// - 本地 work_status 表作缓存与离线兜底；已登录时写 one 站 review 同步
/// - 收藏 = one 站 favourites（服务端）；喜欢 = 本机 local_likes（独立双轨）
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/library_provider.dart';
import '../providers/mirror_provider.dart';
import '../utils/ui_tokens.dart';
import 'account_playlist_sheet.dart';

enum WorkStatus { none, marked, listening, listened, replay, postponed }

const Map<WorkStatus, String> _statusLabels = {
  WorkStatus.none: '',
  WorkStatus.marked: '想听',
  WorkStatus.listening: '在听',
  WorkStatus.listened: '听过',
  WorkStatus.replay: '回味',
  WorkStatus.postponed: '搁置',
};

const Map<WorkStatus, IconData> _statusIcons = {
  WorkStatus.none: Icons.clear,
  WorkStatus.marked: Icons.headphones_outlined,
  WorkStatus.listening: Icons.play_circle_outline,
  WorkStatus.listened: Icons.task_alt,
  WorkStatus.replay: Icons.replay_circle_filled_outlined,
  WorkStatus.postponed: Icons.snooze_outlined,
};

class WorkStatusBar extends StatefulWidget {
  const WorkStatusBar({super.key, required this.rjCode, this.workTitle});

  final String rjCode;

  /// 用于本机喜欢存储的标题（缺省用 rjCode）。
  final String? workTitle;

  @override
  State<WorkStatusBar> createState() => _WorkStatusBarState();
}

class _WorkStatusBarState extends State<WorkStatusBar> {
  WorkStatus _status = WorkStatus.none;
  int? _rating;
  bool _liked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final library = context.read<LibraryProvider>();
    final db = library.database;
    if (db == null) return;
    final row = await db.getWorkStatus(widget.rjCode);
    final liked = library.isLiked(widget.rjCode);
    if (mounted) {
      setState(() {
        if (row != null) {
          _status = WorkStatus.values.firstWhere(
            (s) => s.name == row['status'],
            orElse: () => WorkStatus.none,
          );
          _rating = row['rating'] as int?;
        }
        _liked = liked;
      });
    }
  }

  int? get _numeric =>
      int.tryParse(widget.rjCode.replaceFirst(
          RegExp(r'^(RJ|BJ|VJ)', caseSensitive: false), ''));

  /// 本地落库 + 站端同步（best-effort）。
  Future<void> _persist({required bool remove}) async {
    final library = context.read<LibraryProvider>();
    final db = library.database;
    if (db == null) return;
    if (remove) {
      await db.clearWorkStatus(widget.rjCode);
    } else {
      await db.setWorkStatus(
        widget.rjCode,
        _status == WorkStatus.none ? 'none' : _status.name,
        rating: _rating,
      );
    }
    final mirror = context.read<MirrorProvider>();
    final id = _numeric;
    if (id == null) return;
    if (!mirror.hasAnyLogin) return; // 离线：仅本地缓存。
    try {
      final ok = remove
          ? await mirror.deleteReview(id)
          : await mirror.saveReviewProgress(
              id,
              progress: _status == WorkStatus.none ? null : _status.name,
              rating: _rating,
            );
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(remove ? '已清除（已同步）' : '已同步到账号'),
            duration: const Duration(seconds: 2)));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('同步到服务器失败，已保存在本机'),
          duration: Duration(seconds: 3)));
    }
  }

  Future<void> _setStatus(WorkStatus status) async {
    final next = _status == status ? WorkStatus.none : status;
    setState(() => _status = next);
    await _persist(remove: next == WorkStatus.none);
  }

  Future<void> _setRating(int rating) async {
    setState(() => _rating = rating);
    await _persist(remove: false);
  }

  Future<void> _clearAll() async {
    final library = context.read<LibraryProvider>();
    final db = library.database;
    if (db == null) return;
    await db.clearWorkStatus(widget.rjCode);
    if (mounted) setState(() {
      _status = WorkStatus.none;
      _rating = null;
    });
    await _persist(remove: true);
  }

  Future<void> _toggleLike() async {
    final library = context.read<LibraryProvider>();
    setState(() => _liked = !_liked);
    await library.toggleLike(widget.rjCode,
        widget.workTitle ?? widget.rjCode);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mirror = context.watch<MirrorProvider>();
    final library = context.watch<LibraryProvider>();
    final numeric = _numeric;
    _liked = library.isLiked(widget.rjCode); // 全局保持同步

    Widget statusChip(WorkStatus status) {
      final selected = _status == status;
      return FilterChip(
        avatar: Icon(_statusIcons[status],
            size: 15,
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant),
        label: Text(_statusLabels[status]!, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => _setStatus(status),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: UiSpacing.xSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: UiSpacing.small,
            runSpacing: UiSpacing.xSmall,
            children: [
              // asmr.one 收藏（服务端书签，需登录）。
              // 本机喜欢（独立双轨）。
              Tooltip(
                message: '喜欢：仅保存在本机，不依赖账号',
                child: ActionChip(
                avatar: Icon(
                  _liked ? Icons.favorite : Icons.favorite_border,
                  size: 15,
                  color: _liked ? Colors.pinkAccent : scheme.onSurfaceVariant,
                ),
                label: Text(_liked ? '喜欢' : '喜欢',
                    style: const TextStyle(fontSize: 12)),
                onPressed: _toggleLike,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              statusChip(WorkStatus.marked),
              statusChip(WorkStatus.listening),
              statusChip(WorkStatus.listened),
              statusChip(WorkStatus.replay),
              statusChip(WorkStatus.postponed),
              // 我的评分（1-5，点击递增 5→清空）。
              ActionChip(
                avatar: Icon(
                  _rating != null ? Icons.star : Icons.star_outline,
                  size: 15,
                  color:
                      _rating != null ? Colors.amber : scheme.onSurfaceVariant,
                ),
                label: Text(_rating != null ? '$_rating 星' : '评分',
                    style: const TextStyle(fontSize: 12)),
                onPressed: () async {
                  final next = (_rating ?? 0) >= 5 ? null : (_rating ?? 0) + 1;
                  if (next == null) {
                    final library = context.read<LibraryProvider>();
                    await library.database?.clearWorkStatus(widget.rjCode);
                    if (mounted) setState(() {
                      _rating = null;
                      _status = WorkStatus.none;
                    });
                  } else {
                    await _setRating(next);
                  }
                },
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              if (_status != WorkStatus.none || _rating != null)
                ActionChip(
                  avatar: Icon(Icons.delete_outline,
                      size: 15, color: scheme.onSurfaceVariant),
                  label: const Text('清除标记', style: TextStyle(fontSize: 12)),
                  onPressed: _clearAll,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
          if (numeric != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: UiSpacing.medium,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => showAccountPlaylistSheet(
                      context,
                      workId: '$numeric',
                      workTitle: widget.workTitle ?? widget.rjCode,
                    ),
                    icon: const Icon(Icons.playlist_add, size: 14),
                    label: const Text('账号播放列表',
                        style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4)),
                  ),
                  Text(mirror.hasAnyLogin
                      ? '想听=账号书签·状态/评分/歌单同步账号'
                      : '登录后想听/状态/评分/歌单将同步账号',
                      style: TextStyle(
                          fontSize: 10, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
