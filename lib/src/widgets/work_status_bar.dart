/// 作品状态操作条（详情页：想听/在听/听过 + 我的评分，2026-09-02）。
///
/// 状态存本地 DB（work_status 表）；在听状态由播放行为联动（可选）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/library_provider.dart';
import '../providers/mirror_provider.dart';
import '../providers/online_provider.dart';
import '../utils/ui_tokens.dart';

enum WorkStatus { none, wantListen, listening, listened }

class WorkStatusBar extends StatefulWidget {
  const WorkStatusBar({super.key, required this.rjCode});

  final String rjCode;

  @override
  State<WorkStatusBar> createState() => _WorkStatusBarState();
}

class _WorkStatusBarState extends State<WorkStatusBar> {
  WorkStatus _status = WorkStatus.none;
  int? _rating;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<LibraryProvider>().database;
    if (db == null) return;
    final row = await db.getWorkStatus(widget.rjCode);
    if (mounted && row != null) {
      setState(() {
        _status = WorkStatus.values.firstWhere(
          (s) => s.name == row['status'],
          orElse: () => WorkStatus.none,
        );
        _rating = row['rating'] as int?;
      });
    }
  }

  Future<void> _setStatus(WorkStatus status) async {
    final db = context.read<LibraryProvider>().database;
    if (db == null) return;
    final next = _status == status ? WorkStatus.none : status;
    setState(() => _status = next);
    if (next == WorkStatus.none) {
      await db.clearWorkStatus(widget.rjCode);
    } else {
      await db.setWorkStatus(widget.rjCode, next.name, rating: _rating);
    }
  }

  Future<void> _setRating(int rating) async {
    final db = context.read<LibraryProvider>().database;
    if (db == null) return;
    setState(() => _rating = rating);
    await db.setWorkStatus(widget.rjCode,
        _status == WorkStatus.none ? 'none' : _status.name,
        rating: rating);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget statusChip(WorkStatus status, String label, IconData icon) {
      final selected = _status == status;
      return FilterChip(
        avatar: Icon(icon,
            size: 15,
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => _setStatus(status),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    // 本地 RJ → asmr.one workId 数字（收藏互通，2026-09-03 M4）。
    final mirror = context.watch<MirrorProvider>();
    final online = context.watch<OnlineProvider>();
    final numeric = int.tryParse(
        widget.rjCode.replaceFirst(RegExp(r'^(RJ|BJ|VJ)', caseSensitive: false), ''));
    final fav = numeric != null && online.favoriteIds.contains(numeric);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: UiSpacing.xSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: UiSpacing.small,
            runSpacing: UiSpacing.xSmall,
            children: [
              // asmr.one 收藏（需登录）。
              if (numeric != null)
                ActionChip(
                  avatar: Icon(
                    fav ? Icons.bookmark : Icons.bookmark_border,
                    size: 15,
                    color: fav ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  label: Text(fav ? '已收藏' : '收藏',
                      style: const TextStyle(fontSize: 12)),
                  onPressed: () async {
                    if (!mirror.hasAnyLogin) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('收藏需先登录 asmr.one（设置 → 服务器与账号）'),
                          duration: Duration(seconds: 3)));
                      return;
                    }
                    online.toggleFavorite(numeric);
                    final now = online.favoriteIds.contains(numeric);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(now ? '已加入收藏' : '已取消收藏'),
                        duration: const Duration(seconds: 2)));
                  },
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              statusChip(WorkStatus.wantListen, '想听', Icons.headphones_outlined),
              statusChip(WorkStatus.listening, '在听', Icons.play_circle_outline),
              statusChip(WorkStatus.listened, '听过', Icons.task_alt),
              // 我的评分（1-5 星，点击循环）。
              ActionChip(
                avatar: Icon(
                  _rating != null ? Icons.star : Icons.star_outline,
                  size: 15,
                  color: _rating != null
                      ? Colors.amber
                      : scheme.onSurfaceVariant,
                ),
                label: Text(_rating != null ? '我的评分 $_rating' : '评分',
                    style: const TextStyle(fontSize: 12)),
                onPressed: () async {
                  final next = ((_rating ?? 0) % 5) + 1;
                  await _setRating(next);
                },
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
