/// 「我的-站标记」Tab（2026-09-03 C）：登录账号在 kikoeru/asmr.one 的
/// /api/review 标记列表（想听/在听/听过/回味/搁置 + 评分 + 评语）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/library_provider.dart';
import '../providers/mirror_provider.dart';
import '../utils/ui_tokens.dart';
import 'online_work_detail_screen.dart';
import '../models/online_models.dart';

const Map<String, String> _reviewLabels = {
  'marked': '想听',
  'listening': '在听',
  'listened': '听过',
  'replay': '回味',
  'postponed': '搁置',
};

class MyReviewsTab extends StatefulWidget {
  const MyReviewsTab({super.key});

  @override
  State<MyReviewsTab> createState() => _MyReviewsTabState();
}

class _MyReviewsTabState extends State<MyReviewsTab> {
  final List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final mirror = context.read<MirrorProvider>();
    if (!mirror.hasAnyLogin) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    final list = await mirror.fetchMyReviewsAll();
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(list);
      _loading = false;
      if (list.isEmpty) _error = false;
    });
  }

  Future<void> _remove(Map<String, dynamic> item) async {
    final id = _entryId(item);
    if (id == null) return;
    final mirror = context.read<MirrorProvider>();
    final ok = await mirror.deleteReview(id);
    // 同时清本地缓存行（best effort）。
    final rj = _entryRj(item);
    final library = context.read<LibraryProvider>();
    await library.database?.clearWorkStatus(rj);
    if (!mounted) return;
    if (ok) {
      setState(() => _items.removeWhere((e) => _entryId(e) == id));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已移除标记'), duration: Duration(seconds: 2)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('移除失败（未登录或网络错误）'),
          duration: Duration(seconds: 3)));
    }
  }

  // ---- 宽容解析：条目可能是 review 对象或带 work 内嵌的 work json ----
  static Map<String, dynamic>? _innerWork(Map<String, dynamic> m) {
    final w = m['work'];
    return w is Map<String, dynamic> ? w : null;
  }

  static int? _entryId(Map<String, dynamic> m) {
    final w = _innerWork(m);
    final raw = m['work_id'] ?? m['workId'] ?? m['id'] ??
        (w == null ? null : (w['id'] ?? w['work_id']));
    if (raw is int) return raw;
    return int.tryParse('$raw');
  }

  static String _entryTitle(Map<String, dynamic> m) {
    final w = _innerWork(m);
    final v = m['title'] ?? (w == null ? null : w['title']) ?? '';
    return v as String? ?? '';
  }

  static String? _entryProgress(Map<String, dynamic> m) =>
      (m['progress'] ?? _innerWork(m)?['progress']) as String?;

  static int? _entryRating(Map<String, dynamic> m) {
    final v = m['rating'] ?? _innerWork(m)?['rating'];
    return v is int ? v : (v is num ? v.toInt() : null);
  }

  static String? _entryText(Map<String, dynamic> m) =>
      (m['review_text'] ?? m['reviewText'] ?? m['comment']) as String?;

  static String _entryRj(Map<String, dynamic> m) {
    final id = _entryId(m);
    return id == null ? '' : 'RJ${id.toString().padLeft(6, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mirror = context.watch<MirrorProvider>();
    final library = context.watch<LibraryProvider>();
    final localRjs = library.works
        .map((w) => w.rjCode?.toUpperCase())
        .whereType<String>()
        .toSet();

    if (!mirror.hasAnyLogin) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(UiSpacing.xLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sync_problem,
                  size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: UiSpacing.medium),
              Text('登录后可查看账号标记',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: UiSpacing.xSmall),
              Text('在作品页点的「想听/在听/听过/评分」会同步到账号',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && !_loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(UiSpacing.xLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bookmark_outline,
                  size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: UiSpacing.medium),
              Text(_error ? '加载失败' : '账号暂无标记',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              TextButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: UiSpacing.small),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          final id = _entryId(item);
          final title = _entryTitle(item);
          final progress = _entryProgress(item);
          final rating = _entryRating(item);
          final text = _entryText(item);
          final rj = _entryRj(item).toUpperCase();
          final hasLocal = localRjs.contains(rj);
          final label = _reviewLabels[progress] ?? (progress ?? '');

          return ListTile(
            leading: Icon(
              progress == 'listening'
                  ? Icons.play_circle_outline
                  : progress == 'listened'
                      ? Icons.task_alt
                      : progress == 'replay'
                          ? Icons.replay_circle_filled_outlined
                          : progress == 'postponed'
                              ? Icons.snooze_outlined
                              : Icons.headphones_outlined,
              size: 24,
              color: scheme.primary,
            ),
            title: Row(
              children: [
                if (hasLocal) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4)),
                    child: Text('本地',
                        style: TextStyle(
                            fontSize: 9, color: scheme.onPrimaryContainer)),
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(title.isEmpty ? (id == null ? '?' : rj) : title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text([
                  rj,
                  if (label.isNotEmpty) label,
                  if (rating != null) '★$rating',
                ].join(' · '),
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
                if (text != null && text.isNotEmpty)
                  Text(text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.8))),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '移除标记',
              onPressed: () => _remove(item),
            ),
            onTap: id == null
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => OnlineWorkDetailScreen(
                        work: OnlineWork(id: id, title: title))),
                  ),
          );
        },
      ),
    );
  }
}
