/// 「我的-收藏」Tab（2026-09-03 v1.5.4 重构）：
/// 账号收藏 = 账号对作品的标记（/api/review；kikoflu MyReviews 同款）。
///
/// 说明：RLPlayer 曾按 /api/favourites 拉"书签收藏"，但新版 kikoeru-express
/// 服务器已无该端点（404），账号收藏语义由 review 承担——即「想听」标记即收藏。
/// 顶部五态 chips 走服务端 filter；瀑布卡展示 状态/评分/评语，可移除标记。
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../models/online_models.dart';
import '../providers/mirror_provider.dart';
import '../utils/ui_tokens.dart';
import 'online_work_detail_screen.dart';

const List<(String, String?)> _filters = [
  ('全部', null),
  ('想听', 'marked'),
  ('在听', 'listening'),
  ('听过', 'listened'),
  ('回味', 'replay'),
  ('搁置', 'postponed'),
];

class FavoritesTab extends StatefulWidget {
  const FavoritesTab({super.key});

  @override
  State<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<FavoritesTab> {
  final List<OnlineWork> _items = [];
  bool _loading = false;
  bool _error = false;
  bool _loaded = false;
  String? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final mirror = context.read<MirrorProvider>();
    if (!mirror.hasAnyLogin) {
      setState(() {
        _loading = false;
        _loaded = true;
        _error = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final list =
          await mirror.fetchMyReviewsAll(filter: _filter);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(list
              .map(_toOnlineWork)
              .whereType<OnlineWork>()
              .toList());
        _loading = false;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
        _loaded = true;
      });
      debugPrint('[Favorites] 拉取失败: $e');
    }
  }

  static OnlineWork? _toOnlineWork(Map<String, dynamic> item) {
    final w = item['work'] is Map<String, dynamic>
        ? item['work'] as Map<String, dynamic>
        : item;
    final id = w['id'];
    if (id is! num) return null;
    OnlineWork base;
    try {
      base = OnlineWork.fromJson(w);
    } catch (_) {
      base = OnlineWork(id: id.toInt(), title: (w['title'] ?? '') as String);
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

  /// 移除标记（账号收藏取消 = DELETE review）。
  Future<void> _removeMark(OnlineWork w) async {
    final mirror = context.read<MirrorProvider>();
    final ok = await mirror.deleteReview(w.id);
    if (!mounted) return;
    if (ok) {
      setState(() => _items.removeWhere((e) => e.id == w.id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已移除「${w.title}」的标记'),
          duration: const Duration(seconds: 2)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('移除失败（未登录或网络错误）'),
          duration: const Duration(seconds: 3)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mirror = context.watch<MirrorProvider>();

    if (!mirror.hasAnyLogin) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(UiSpacing.xLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bookmark_border,
                  size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: UiSpacing.medium),
              Text('登录后可查看账号收藏',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: UiSpacing.xSmall),
              Text('收藏 = 账号里标记的作品（想听即收藏）；设置 → 服务器与账号登录',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: UiSpacing.medium, vertical: 4),
            children: [
              for (final (label, value) in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: UiSpacing.xSmall),
                  child: FilterChip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    selected: _filter == value,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onSelected: (_) {
                      setState(() => _filter = value);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _buildBody(context, scheme)),
      ],
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme scheme) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _loaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(UiSpacing.xLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_error
                  ? Icons.error_outline
                  : Icons.bookmark_outline,
                  size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: UiSpacing.medium),
              Text(_error ? '收藏拉取失败' : '该分组暂无收藏',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              if (_error)
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: MasonryGridView.count(
        padding: const EdgeInsets.all(UiSpacing.small),
        crossAxisCount: 2,
        mainAxisSpacing: UiSpacing.small,
        crossAxisSpacing: UiSpacing.small,
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final w = _items[index];
          return _FavoriteCard(
            work: w,
            onRemove: () => _removeMark(w),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => OnlineWorkDetailScreen(work: w))),
          );
        },
      ),
    );
  }
}

/// 账号收藏瀑布卡（4:3 封面 + 状态/评分徽章 + 标题渐变 + 移除）。
class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({
    required this.work,
    required this.onRemove,
    required this.onTap,
  });

  final OnlineWork work;
  final VoidCallback onRemove;
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
            Positioned(
              right: 4,
              top: 4,
              child: Material(
                color: Colors.black38,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onRemove,
                  child: const Padding(
                    padding: EdgeInsets.all(5),
                    child: Icon(Icons.bookmark_remove_outlined,
                        size: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
