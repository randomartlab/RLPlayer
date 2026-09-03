/// 「我的-状态」Tab（2026-09-03 v1.5.4）：本机五态分组（账号标记瀑布见「收藏」）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/work.dart';
import '../providers/library_provider.dart';
import '../utils/ui_tokens.dart';
import 'work_detail_screen.dart';

class StatusTab extends StatefulWidget {
  const StatusTab({super.key});

  @override
  State<StatusTab> createState() => _StatusTabState();
}

class _StatusTabState extends State<StatusTab> {
  List<Map<String, dynamic>>? _rows;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final library = context.read<LibraryProvider>();
    final db = library.database;
    if (db == null) {
      setState(() {
        _rows = const [];
        _loading = false;
      });
      return;
    }
    final rows = await db.allWorkStatus();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _clear(String rjCode) async {
    final library = context.read<LibraryProvider>();
    final db = library.database;
    if (db == null) return;
    await db.clearWorkStatus(rjCode);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final scheme = Theme.of(context).colorScheme;
    final rows = _rows ?? const [];
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(UiSpacing.xLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bookmark_border,
                  size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: UiSpacing.medium),
              Text('暂无本机状态标记',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: UiSpacing.xSmall),
              Text('账号侧同款瀑布请到「收藏」查看；本机在作品页点想听/评分后汇总',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    Work? workByRj(String rj) {
      for (final w in library.works) {
        if (w.rjCode?.toUpperCase() == rj.toUpperCase()) return w;
      }
      return null;
    }

    List<Map<String, dynamic>> group(String status) => rows
        .where((r) => r['status'] == status)
        .toList()
      ..sort((a, b) =>
          ((b['updated_at'] as num?) ?? 0)
              .compareTo((a['updated_at'] as num?) ?? 0));
    final want = group('marked');
    final listening = group('listening');
    final listened = group('listened');
    final replay = group('replay');
    final postponed = group('postponed');
    final rated = rows.where((r) => r['rating'] != null).toList()
      ..sort((a, b) =>
          ((b['updated_at'] as num?) ?? 0)
              .compareTo((a['updated_at'] as num?) ?? 0));

    Widget section(String title, IconData icon,
        List<Map<String, dynamic>> items) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(UiSpacing.medium,
                UiSpacing.small, UiSpacing.medium, 0),
            child: Row(
              children: [
                Icon(icon, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text('$title（${items.length}）',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary)),
              ],
            ),
          ),
          for (final r in items)
            _StatusRow(
              rj: r['rj_code'] as String,
              rating: r['rating'] as int?,
              work: workByRj(r['rj_code'] as String),
              onOpen: workByRj(r['rj_code'] as String) == null
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => WorkDetailScreen(
                          work: workByRj(r['rj_code'] as String)!))),
              onClear: () => _clear(r['rj_code'] as String),
            ),
          const SizedBox(height: UiSpacing.small),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: UiSpacing.xSmall),
          section('想听', Icons.headphones_outlined, want),
          section('在听', Icons.play_circle_outline, listening),
          section('听过', Icons.task_alt, listened),
          section('回味', Icons.replay_circle_filled_outlined, replay),
          section('搁置', Icons.snooze_outlined, postponed),
          section('已评分', Icons.star_outline, rated),
          const SizedBox(height: UiSpacing.medium),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.rj,
    required this.rating,
    required this.work,
    this.onOpen,
    required this.onClear,
  });

  final String rj;
  final int? rating;
  final Work? work;
  final VoidCallback? onOpen;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: onOpen == null
          ? null
          : SizedBox(
              width: 44,
              height: 44,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: work!.coverPath != null
                    ? Image.file(
                        File(work!.coverPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(Icons.album,
                            color: scheme.onSurfaceVariant),
                      )
                    : Icon(Icons.album,
                        color: scheme.onSurfaceVariant),
              ),
            ),
      title: Text(work?.title ?? rj,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          [work?.rjCode ?? rj, if (rating != null) '评分 ★$rating']
              .join(' · '),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      trailing: IconButton(
        onPressed: onClear,
        icon: const Icon(Icons.clear, size: 18),
        tooltip: '清除状态',
      ),
      onTap: onOpen,
    );
  }
}
