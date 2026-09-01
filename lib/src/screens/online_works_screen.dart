import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../models/online_models.dart';
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
  const OnlineWorksScreen({super.key});

  @override
  State<OnlineWorksScreen> createState() => _OnlineWorksScreenState();
}

enum _OnlineViewMode { large, small, list }

class _OnlineWorksScreenState extends State<OnlineWorksScreen> {
  final ScrollController _scrollController = ScrollController();
  _OnlineViewMode _viewMode = _OnlineViewMode.large;

  static const _orders = [
    ('release', '发行日'),
    ('rating', '评分'),
    ('dl_count', '销量'),
    ('price', '价格'),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    final online = context.read<OnlineProvider>();
    if (online.works.isEmpty && !online.loading) {
      unawaited(online.loadMore());
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      unawaited(context.read<OnlineProvider>().loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = context.watch<OnlineProvider>();
    final mirror = context.watch<MirrorProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
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
          itemCount: online.works.length + (online.hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= online.works.length) {
              return const Padding(
                padding: EdgeInsets.all(UiSpacing.large),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return _OnlineWorkCard(
                work: online.works[index], mode: CardMode.list);
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
        itemCount: online.works.length + (online.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= online.works.length) {
            return const Padding(
              padding: EdgeInsets.all(UiSpacing.large),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _OnlineWorkCard(
              work: online.works[index],
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
    final scheme = Theme.of(context).colorScheme;
    final downloaded = online.downloadedRjCodes.contains(work.rjCode);

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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
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
            Text(work.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500)),
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
