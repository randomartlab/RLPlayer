/// 「我的-状态」Tab（2026-09-03 v1.5.3）：
/// 双视图——本地（本机五态分组）与 账号（拉 /api/review 瀑布，kikoflu 同款）。
/// 视图切换 SegmentedButton；账号模式未登录给出引导。
library;

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../models/online_models.dart';
import '../models/work.dart';
import '../providers/library_provider.dart';
import '../providers/mirror_provider.dart';
import '../utils/ui_tokens.dart';
import 'online_work_detail_screen.dart';
import 'work_detail_screen.dart';

enum _StatusView { local, account }

class StatusTab extends StatefulWidget {
  const StatusTab({super.key});

  @override
  State<StatusTab> createState() => _StatusTabState();
}

class _StatusTabState extends State<StatusTab> {
  _StatusView _view = _StatusView.local;
  List<Map<String, dynamic>>? _rows;
  bool _loading = true;

  // 账号视图
  final List<OnlineWork> _account = [];
  bool _acctLoading = false;
  bool _acctError = false;
  bool _acctLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  Future<void> _loadLocal() async {
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

  Future<void> _loadAccount() async {
    final mirror = context.read<MirrorProvider>();
    if (!mirror.hasAnyLogin) return;
    setState(() {
      _acctLoading = true;
      _acctError = false;
    });
    try {
      final list = await mirror.fetchMyReviewsAll();
      if (!mounted) return;
      setState(() {
        _account
          ..clear()
          ..addAll(list
              .map(_toOnlineWork)
              .whereType<OnlineWork>()
              .toList());
        _acctLoading = false;
        _acctLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _acctLoading = false;
        _acctError = true;
        _acctLoaded = true;
      });
    }
  }

  /// 把 /api/review 条目（wrapper 或 work json 内嵌 progress）转 OnlineWork。
  static OnlineWork? _toOnlineWork(Map<String, dynamic> item) {
    Map<String, dynamic>? w;
    if (item['work'] is Map<String, dynamic>) {
      w = item['work'] as Map<String, dynamic>;
    } else {
      w = item;
    }
    final id = w['id'];
    if (id is! int && id is! num) return null;
    final title = (w['title'] ?? '') as String;
    OnlineWork? base;
    try {
      base = OnlineWork.fromJson(w);
    } catch (_) {
      base = OnlineWork(id: id.toInt(), title: title);
    }
    final progress = (item['progress'] ?? w['progress']) as String?;
    final rating = item['rating'] ?? w['rating'];
    final text =
        (item['review_text'] ?? item['reviewText'] ?? w['review_text']) as String?;
    return OnlineWork(
      id: base.id,
      title: base.title,
      titleTranslation: base.titleTranslation,
      circleName: base.circleName,
      circleId: base.circleId,
      vas: base.vas,
      tags: base.tags,
      nsfw: base.nsfw,
      release: base.release,
      dlCount: base.dlCount,
      ratingCount: base.ratingCount,
      reviewCount: base.reviewCount,
      price: base.price,
      averageRating: base.averageRating,
      sourceId: base.sourceId,
      description: base.description,
      children: base.children,
      progress: progress,
      myRating: rating is num ? rating.toInt() : null,
      reviewText: text,
    );
  }

  /// 删除某作品本地状态行并刷新。
  Future<void> _clear(String rjCode) async {
    final library = context.read<LibraryProvider>();
    final db = library.database;
    if (db == null) return;
    await db.clearWorkStatus(rjCode);
    await _loadLocal();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final library = context.watch<LibraryProvider>();
    final mirror = context.watch<MirrorProvider>();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              UiSpacing.medium, UiSpacing.small, UiSpacing.medium, 0),
          child: Row(
            children: [
              SegmentedButton<_StatusView>(
                segments: const [
                  ButtonSegment(
                      value: _StatusView.local, label: Text('本机')),
                  ButtonSegment(
                      value: _StatusView.account, label: Text('账号')),
                ],
                selected: {_view},
                style: const ButtonStyle(
                    visualDensity: VisualDensity.compact),
                onSelectionChanged: (v) async {
                  setState(() => _view = v.first);
                  if (v.first == _StatusView.account &&
                      !_acctLoaded &&
                      mirror.hasAnyLogin) {
                    await _loadAccount();
                  }
                },
              ),
              const SizedBox(width: UiSpacing.small),
              if (_view == _StatusView.account)
                Expanded(
                  child: Text(
                    mirror.hasAnyLogin
                        ? '账号标记（与 one 站同步）'
                        : '未登录：仅显示本机',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _view == _StatusView.local
              ? _buildLocal(context, scheme, library)
              : _buildAccount(context, scheme, mirror),
        ),
      ],
    );
  }

  // ---- 本机视图（分组列表） ----
  Widget _buildLocal(BuildContext context, ColorScheme scheme,
      LibraryProvider library) {
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
              Text('切「账号」可看已同步到 one 站的状态；本机在作品页点想听/评分后汇总',
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
      onRefresh: _loadLocal,
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

  // ---- 账号视图（瀑布，kikoflu 同款） ----
  Widget _buildAccount(BuildContext context, ColorScheme scheme,
      MirrorProvider mirror) {
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
              Text('登录后可同步账号标记',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: UiSpacing.xSmall),
              Text('设置 → 服务器与账号 登录后，这里以瀑布展示账号标记',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }
    if (_acctLoading && _account.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_account.isEmpty && _acctLoaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(UiSpacing.xLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_acctError
                  ? Icons.error_outline
                  : Icons.bookmark_border,
                  size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: UiSpacing.medium),
              Text(_acctError ? '账号标记拉取失败' : '账号暂无标记',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              if (_acctError)
                FilledButton.icon(
                  onPressed: _loadAccount,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAccount,
      child: MasonryGridView.count(
        padding: const EdgeInsets.all(UiSpacing.small),
        crossAxisCount: 2,
        mainAxisSpacing: UiSpacing.small,
        crossAxisSpacing: UiSpacing.small,
        itemCount: _account.length,
        itemBuilder: (context, index) {
          final w = _account[index];
          return _AccountCard(
            work: w,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => OnlineWorkDetailScreen(work: w))),
          );
        },
      ),
    );
  }
}

/// 账号标记瀑布卡（4:3 封面 + 状态/评分徽章 + 标题渐变）。
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.work, required this.onTap});

  final OnlineWork work;
  final VoidCallback onTap;

  static const Map<String, (String, IconData)> _meta = {
    'marked': ('想听', Icons.headphones_outlined),
    'listening': ('在听', Icons.play_circle_outline),
    'listened': ('听过', Icons.task_alt),
    'replay': ('回味', Icons.replay_circle_filled_outlined),
    'postponed': ('搁置', Icons.snooze_outlined),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mirror = context.read<MirrorProvider>();
    final meta = _meta[work.progress];
    final badge = <Widget>[
      if (meta != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(meta.$2, size: 11, color: scheme.onPrimary),
              const SizedBox(width: 3),
              Text(meta.$1,
                  style: TextStyle(fontSize: 10, color: scheme.onPrimary)),
            ],
          ),
        ),
      if (work.myRating != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star, size: 11, color: Colors.black87),
              const SizedBox(width: 3),
              Text('${work.myRating}',
                  style:
                      const TextStyle(fontSize: 10, color: Colors.black87)),
            ],
          ),
        ),
    ];
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(UiRadii.control),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: CachedNetworkImage(
                imageUrl: mirror.api.coverUrl(work.id),
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    Container(color: scheme.surfaceContainerHighest),
                errorWidget: (_, _, _) => Container(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(Icons.album,
                      color: scheme.onSurfaceVariant, size: 36),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 18, 8, 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (work.reviewText != null &&
                        work.reviewText!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text('“${work.reviewText}”',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 9,
                                color: Colors.white70,
                                fontStyle: FontStyle.italic)),
                      ),
                    Text(
                      work.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            if (badge.isNotEmpty)
              Positioned(
                left: 6,
                top: 6,
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: badge,
                ),
              ),
          ],
        ),
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
