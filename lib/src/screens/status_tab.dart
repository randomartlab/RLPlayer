/// 「我的-状态清单」Tab（2026-09-03 M1）：
/// 把想听/在听/听过/已评分（work_status）聚合为可浏览分组。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/library_provider.dart';
import '../models/work.dart';
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

  /// 删除某作品状态行并刷新。
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
              Text('暂无状态标记',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: UiSpacing.xSmall),
              Text('在作品详情页点「想听 / 在听 / 听过 / 评分」后，会在这里汇总',
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

    // 分组：想听 / 在听 / 听过 / 已评分。
    List<Map<String, dynamic>> group(String status) => rows
        .where((r) => r['status'] == status)
        .toList()
      ..sort((a, b) =>
          ((b['updated_at'] as num?) ?? 0)
              .compareTo((a['updated_at'] as num?) ?? 0));
    final want = group('wantListen');
    final listening = group('listening');
    final listened = group('listened');
    final rated = rows.where((r) => r['rating'] != null).toList()
      ..sort((a, b) =>
          ((b['updated_at'] as num?) ?? 0)
              .compareTo((a['updated_at'] as num?) ?? 0));

    Widget section(String title, IconData icon, List<Map<String, dynamic>> items) {
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
                      builder: (_) =>
                          WorkDetailScreen(work: workByRj(r['rj_code'] as String)!))),
              onClear: () => _clear(r['rj_code'] as String),
            ),
          const SizedBox(height: UiSpacing.small),
        ],
      );
    }

    return ListView(
      children: [
        const SizedBox(height: UiSpacing.xSmall),
        section('想听', Icons.headphones_outlined, want),
        section('在听', Icons.play_circle_outline, listening),
        section('听过', Icons.task_alt, listened),
        section('已评分', Icons.star_outline, rated),
        const SizedBox(height: UiSpacing.medium),
      ],
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
