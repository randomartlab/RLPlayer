import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../models/online_models.dart';
import '../providers/library_provider.dart';
import '../providers/mirror_provider.dart';
import '../providers/online_provider.dart';
import '../utils/ui_tokens.dart';
import 'online_work_detail_screen.dart';

/// 在线封面墙（M12，布局复用中卡网格规格，UI 规范 §5.8）。
///
/// - 排序 chips：发行日 / 评分 / 销量 / 价格（PRD §5.12）；
/// - 滚动分页加载；游客可浏览；
/// - 已下载作品角标 → 点击进入本地详情（M4 版）；未下载 → 在线详情；
/// - 断网/失败错误态不崩溃（验收 #15）。
class OnlineWorksScreen extends StatefulWidget {
  const OnlineWorksScreen(
      {super.key, this.circleId, this.circleTitle, this.likedOnly = false});

  /// 社团模式：传入则列出该社团全部作品（点社团名进入，用户需求 2026-09-02）。
  final int? circleId;
  final String? circleTitle;

  /// 只显示本机 ♥ 喜欢（作品页过滤，2026-09-03）。
  final bool likedOnly;

  @override
  State<OnlineWorksScreen> createState() => _OnlineWorksScreenState();
}

enum _OnlineViewMode { large, small, list }

class _OnlineWorksScreenState extends State<OnlineWorksScreen> {
  final ScrollController _scrollController = ScrollController();
  _OnlineViewMode _viewMode = _OnlineViewMode.large;

  // ---- 社团模式（点社团名进入；独立于全局 OnlineProvider）----
  final List<OnlineWork> _circleWorks = [];
  int _circlePage = 0;
  bool _circleLoading = false;
  bool _circleHasMore = true;
  String? _circleError;
  String _circleOrder = 'release';

  bool get _isCircleMode => widget.circleId != null;

  // order 实测可用值（2026-09-02）：release / rate_average_2dp / dl_count /
  // price / review_count。'rating' 为无效值会返回空列表——已修正。
  static const _orders = [
    ('release', '发行日'),
    ('rate_average_2dp', '评分'),
    ('dl_count', '销量'),
    ('review_count', '评价量'),
    ('price', '价格'),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (_isCircleMode) {
      unawaited(_loadCircleMore());
    } else {
      final online = context.read<OnlineProvider>();
      if (online.works.isEmpty && !online.loading) {
        unawaited(online.loadMore());
      }
    }
  }

  Future<void> _loadCircleMore() async {
    if (_circleLoading || !_circleHasMore || !_isCircleMode) return;
    setState(() => _circleLoading = true);
    try {
      final mirror = context.read<MirrorProvider>();
      final works = await mirror.api.getCircleWorksPage(
          widget.circleId!, _circlePage + 1,
          order: _circleOrder);
      _circleWorks.addAll(works);
      _circleHasMore = works.length >= 20;
      _circlePage++;
      _circleError = null;
    } catch (e) {
      _circleError = '$e';
    } finally {
      if (mounted) setState(() => _circleLoading = false);
    }
  }

  Future<void> _refreshCircle() async {
    _circlePage = 0;
    _circleHasMore = true;
    await _loadCircleMore();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 400 ||
        pos.pixels >= pos.maxScrollExtent * 0.85) {
      if (_isCircleMode) {
        unawaited(_loadCircleMore());
      } else {
        unawaited(context.read<OnlineProvider>().loadMore());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = context.watch<OnlineProvider>();
    final mirror = context.watch<MirrorProvider>();
    final scheme = Theme.of(context).colorScheme;
    if (!_isCircleMode) {
      // 首次进入加载书签状态（游客静默失败）。
      if (!online.favoritesLoaded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          online.loadFavorites();
        });
      }
    }

    if (_isCircleMode) {
      // 社团模式：标题 + 排序 + 列表（无分类 chips）。
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(UiSpacing.medium,
                UiSpacing.xSmall, UiSpacing.medium, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.circleTitle ?? '社团作品',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PopupMenuButton<String>(
                  initialValue: _circleOrder,
                  onSelected: (value) {
                    setState(() => _circleOrder = value);
                    _circlePage = 0;
                    _circleHasMore = true;
                    _circleWorks.clear();
                    unawaited(_loadCircleMore());
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'release', child: Text('发行日')),
                    PopupMenuItem(
                        value: 'rate_average_2dp', child: Text('评分')),
                    PopupMenuItem(value: 'dl_count', child: Text('销量')),
                    PopupMenuItem(value: 'review_count', child: Text('评价量')),
                    PopupMenuItem(value: 'price', child: Text('价格')),
                  ],
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Icon(Icons.sort), Text('排序')],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(context, online)),
        ],
      );
    }

    return Column(
      children: [
        // 分类 chips（用户清单 #2：全部/全年龄/R18/带字幕）。
        Padding(
          padding: const EdgeInsets.fromLTRB(
              UiSpacing.medium, UiSpacing.xSmall, UiSpacing.medium, 0),
          child: SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (value, label) in const [
                  (0, '全部'),
                  (1, '全年龄'),
                  (2, 'R18'),
                  (3, '带字幕'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: UiSpacing.small),
                    child: FilterChip(
                      label: Text(label),
                      selected: online.category == value,
                      onSelected: (_) => online.setCategory(value),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // 工具行：视图切换（大网格/小网格/列表，对齐 KikoFlu 卡片模式）+ 排序 chips。
        Padding(
          padding: const EdgeInsets.fromLTRB(
              UiSpacing.medium, UiSpacing.xSmall, UiSpacing.medium, 0),
          child: SizedBox(
            height: UiControlSize.standard,
            child: Row(
              children: [
                _ViewModeIcon(
                  icon: Icons.grid_view,
                  selected: _viewMode == _OnlineViewMode.large,
                  tooltip: '大网格',
                  onTap: () =>
                      setState(() => _viewMode = _OnlineViewMode.large),
                ),
                _ViewModeIcon(
                  icon: Icons.grid_view_outlined,
                  selected: _viewMode == _OnlineViewMode.small,
                  tooltip: '小网格',
                  onTap: () =>
                      setState(() => _viewMode = _OnlineViewMode.small),
                ),
                _ViewModeIcon(
                  icon: Icons.view_list_outlined,
                  selected: _viewMode == _OnlineViewMode.list,
                  tooltip: '列表',
                  onTap: () =>
                      setState(() => _viewMode = _OnlineViewMode.list),
                ),
                const VerticalDivider(width: 1, indent: 12, endIndent: 12),
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final (value, label) in _orders)
                        Padding(
                          padding: const EdgeInsets.only(right: UiSpacing.small),
                          child: FilterChip(
                            label: Text(label),
                            selected: online.order == value,
                            onSelected: (_) => online.setOrder(value),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: UiSpacing.medium),
          child: Row(
            children: [
              Icon(Icons.dns_outlined,
                  size: UiIconSize.small, color: scheme.onSurfaceVariant),
              const SizedBox(width: UiSpacing.xSmall),
              Expanded(
                child: Text(
                  '当前镜像：${mirror.activeHost}'
                  '${mirror.activeMirror?.latencyMs != null ? '（${mirror.activeMirror!.latencyMs}ms）' : ''}'
                  '${mirror.currentUser != null ? ' · 已登录 ${mirror.currentUser!.name}' : ' · 游客浏览'}',
                  style: UiTextStyles.supporting
                      .copyWith(color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(context, online)),
      ],
    );
  }

  Widget _buildBody(BuildContext context, OnlineProvider online) {
    final scheme = Theme.of(context).colorScheme;

    // 社团模式：独立数据源渲染。
    if (_isCircleMode) {
      if (_circleError != null && _circleWorks.isEmpty) {
        return Center(child: Text('加载失败：$_circleError'));
      }
      if (_circleWorks.isEmpty && _circleLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return RefreshIndicator(
        onRefresh: _refreshCircle,
        child: MasonryGridView.count(
          controller: _scrollController,
          padding: const EdgeInsets.all(UiSpacing.small),
          crossAxisCount: 2,
          mainAxisSpacing: UiSpacing.small,
          crossAxisSpacing: UiSpacing.small,
          itemCount: _circleWorks.length + (_circleHasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _circleWorks.length) {
              return _LoadMoreFooter(
                loading: _circleLoading,
                hasMore: _circleHasMore,
                onLoad: () => _loadCircleMore(),
              );
            }
            return _OnlineWorkCard(
                work: _circleWorks[index], mode: CardMode.medium);
          },
        ),
      );
    }

    // ♥ 喜欢过滤（作品页过滤；仅对全局在线流，社团模式不受影响）。
    final likedOnly = widget.likedOnly;
    final library = context.watch<LibraryProvider>();
    final likedIds = library.likedRjCodes
        .map((rj) => rj.replaceFirst(RegExp(r'^(RJ|BJ|VJ)', caseSensitive: false), ''))
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    final List<OnlineWork> works = likedOnly
        ? online.works
            .where((w) => likedIds.contains(w.id.toString()))
            .toList()
        : online.works;

    if (likedOnly && works.isEmpty && !online.loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(UiSpacing.xLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.favorite_border,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: UiSpacing.medium),
              Text('没有 ♥ 喜欢的在线作品',
                  style: TextStyle(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    // 错误态（断网/镜像不可达）：保留页面结构不崩溃（验收 #15）。
    if (online.error != null && online.works.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(UiSpacing.xLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 64, color: scheme.onSurfaceVariant),
              const SizedBox(height: UiSpacing.medium),
              Text(
                '在线服务暂不可用',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: UiSpacing.xSmall),
              Text(
                online.error!,
                style: UiTextStyles.supporting
                    .copyWith(color: scheme.onSurfaceVariant),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: UiSpacing.large),
              FilledButton.icon(
                onPressed: () => online.refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (online.works.isEmpty && online.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_viewMode == _OnlineViewMode.list) {
      return RefreshIndicator(
        onRefresh: () => online.refresh(),
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: UiSpacing.small),
          itemCount: works.length + (!likedOnly && online.hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= works.length) {
              return _LoadMoreFooter(
                loading: online.loading,
                hasMore: online.hasMore,
                onLoad: () => context.read<OnlineProvider>().loadMore(),
              );
            }
            return _OnlineWorkCard(work: works[index], mode: CardMode.list);
          },
        ),
      );
    }

    final small = _viewMode == _OnlineViewMode.small;
    return RefreshIndicator(
      onRefresh: () => online.refresh(),
      child: MasonryGridView.count(
        controller: _scrollController,
        padding: const EdgeInsets.all(UiSpacing.small),
        crossAxisCount: small ? 3 : 2,
        mainAxisSpacing: UiSpacing.small,
        crossAxisSpacing: UiSpacing.small,
        itemCount: works.length + (!likedOnly && online.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= works.length) {
            return _LoadMoreFooter(
              loading: online.loading,
              hasMore: online.hasMore,
              onLoad: () => context.read<OnlineProvider>().loadMore(),
            );
          }
          return _OnlineWorkCard(
              work: works[index],
              mode: small ? CardMode.compact : CardMode.medium);
        },
      ),
    );
  }
}

/// 在线作品卡片三变体（对齐本地墙 / KikoFlu 卡片模式）。
enum CardMode { compact, medium, list }

class _OnlineWorkCard extends StatelessWidget {
  const _OnlineWorkCard({required this.work, this.mode = CardMode.medium});

  final OnlineWork work;
  final CardMode mode;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      CardMode.compact => _CompactCard(work: work),
      CardMode.list => _ListCard(work: work),
      CardMode.medium => _MediumCard(work: work),
    };
  }
}

mixin _OnlineCardBase {
  Widget coverStack(BuildContext context, OnlineWork work,
      {double? aspectRatio, double? width, double? height}) {
    final online = context.watch<OnlineProvider>();
    final mirror = context.read<MirrorProvider>();
    final library = context.watch<LibraryProvider>();
    final scheme = Theme.of(context).colorScheme;
    final downloaded = online.downloadedRjCodes.contains(work.rjCode);
    final liked = library.isLiked(work.rjCode);

    Widget cover = _cover(context, mirror, work);

    // 定尺寸容器在外（masonry 需要子项有固有尺寸），Stack 在内 expand 填满。
    // 修复白屏：裸 Stack 在无界高度约束下抛布局异常。
    final stack = Stack(
      fit: StackFit.expand,
      children: [
        cover,
        Positioned(
          left: UiSpacing.xSmall,
          bottom: UiSpacing.xSmall,
          child: _badge(work.rjCode),
        ),
        if (work.nsfw)
          Positioned(
            right: UiSpacing.xSmall,
            bottom: UiSpacing.xSmall,
            child: _badge('R18', color: scheme.error),
          ),
        // ♥ 本机喜欢快捷（在线流也可标记/筛选，2026-09-04）。
        Positioned(
          left: UiSpacing.xSmall,
          top: UiSpacing.xSmall,
          child: GestureDetector(
            onTap: () =>
                library.toggleLike(work.rjCode, work.title),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black38,
                shape: BoxShape.circle,
              ),
              child: Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                size: 15,
                color: liked ? Colors.pinkAccent : Colors.white,
              ),
            ),
          ),
        ),
        if (downloaded)
          Positioned(
            right: UiSpacing.xSmall,
            top: UiSpacing.xSmall,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(UiRadii.tag),
              ),
              child: const Text('已下载',
                  style: TextStyle(
                      color: Colors.white, fontSize: 10, height: 1.2)),
            ),
          ),
      ],
    );

    if (aspectRatio != null) {
      return AspectRatio(aspectRatio: aspectRatio, child: stack);
    }
    return SizedBox(
      width: width ?? 80,
      height: height ?? 80,
      child: stack,
    );
  }

  Widget _cover(BuildContext context, MirrorProvider mirror, OnlineWork work) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(UiRadii.control),
      child: CachedNetworkImage(
        imageUrl: mirror.api.coverUrl(work.id),
        fit: BoxFit.cover,
        placeholder: (context, url) =>
            Container(color: scheme.surfaceContainerHighest),
        errorWidget: (context, url, error) => Container(
          color: scheme.surfaceContainerHighest,
          child: Icon(Icons.album, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _badge(String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: (color ?? Colors.black).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(UiRadii.tag),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              height: 1.2,
              fontWeight: FontWeight.w500)),
    );
  }

  String dateLabel(OnlineWork work) {
    final r = work.release;
    if (r == null) return '';
    return '${r.year}-${r.month.toString().padLeft(2, '0')}-${r.day.toString().padLeft(2, '0')}';
  }

  void openDetail(BuildContext context, OnlineWork work) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => OnlineWorkDetailScreen(work: work),
      ),
    );
  }
}

/// 中卡（大网格）：封面 1.3 + 标题/社团/评分行。
class _MediumCard extends StatelessWidget with _OnlineCardBase {
  _MediumCard({required this.work});

  final OnlineWork work;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => openDetail(context, work),
      borderRadius: BorderRadius.circular(UiRadii.control),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面 4:3（实测 asmr.one 封面 560×420，零裁切）。
            coverStack(context, work, aspectRatio: 4 / 3),
            const SizedBox(height: UiSpacing.xSmall),
            Text(work.title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.35)),
            if (work.circleName != null) ...[
              const SizedBox(height: 2),
              Text(work.circleName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 3),
            Text(
              [
                if (work.averageRating != null)
                  '★${work.averageRating!.toStringAsFixed(1)}',
                if (work.dlCount != null) '${work.dlCount}',
                dateLabel(work),
              ].where((s) => s.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13, height: 1.3, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 紧凑卡（小网格）：正方形封面 + 单行标题。
class _CompactCard extends StatelessWidget with _OnlineCardBase {
  _CompactCard({required this.work});

  final OnlineWork work;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openDetail(context, work),
      borderRadius: BorderRadius.circular(UiRadii.control),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            coverStack(context, work, aspectRatio: 4 / 3),
            const SizedBox(height: UiSpacing.xSmall),
            // 实机反馈 2026-09-02：三列窄卡单行截断 → 两行自适应。
            Text(work.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.25)),
          ],
        ),
      ),
    );
  }
}

/// 全卡（列表行）：80×80 封面 + 两行信息。
class _ListCard extends StatelessWidget with _OnlineCardBase {
  _ListCard({required this.work});

  final OnlineWork work;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => openDetail(context, work),
      borderRadius: BorderRadius.circular(UiRadii.list),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: UiSpacing.medium, vertical: UiSpacing.small),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: coverStack(context, work, width: 80, height: 80),
            ),
            const SizedBox(width: UiSpacing.medium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(work.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (work.circleName != null) work.circleName!,
                      work.rjCode,
                      if (work.averageRating != null)
                        '★${work.averageRating!.toStringAsFixed(1)}',
                      if (work.dlCount != null) '${work.dlCount} 销量',
                      dateLabel(work),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// 工具栏视图切换按钮。
class _ViewModeIcon extends StatelessWidget {
  const _ViewModeIcon({
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      color: selected ? scheme.primary : scheme.onSurfaceVariant,
      onPressed: onTap,
    );
  }
}

/// 列表底部加载态（兜底按钮 + 自动触发说明，2026-09-03：
/// 防止滚动监听失效导致下拉不继续加载）。
class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.loading,
    required this.hasMore,
    required this.onLoad,
  });

  final bool loading;
  final bool hasMore;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text('已加载全部',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: onLoad,
          icon: const Icon(Icons.expand_more, size: 18),
          label: const Text('加载更多'),
          style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact),
        ),
      ),
    );
  }
}
