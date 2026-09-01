import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
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

class _OnlineWorksScreenState extends State<OnlineWorksScreen> {
  final ScrollController _scrollController = ScrollController();

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
        // 排序 chips + 当前镜像提示。
        Padding(
          padding: const EdgeInsets.fromLTRB(
              UiSpacing.medium, UiSpacing.xSmall, UiSpacing.medium, 0),
          child: SizedBox(
            height: UiControlSize.standard,
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

    return RefreshIndicator(
      onRefresh: () => online.refresh(),
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(UiSpacing.small),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.62,
          mainAxisSpacing: UiSpacing.small,
          crossAxisSpacing: UiSpacing.small,
        ),
        itemCount: online.works.length + (online.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= online.works.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(UiSpacing.large),
                child: CircularProgressIndicator(),
              ),
            );
          }
          return _OnlineWorkCard(work: online.works[index]);
        },
      ),
    );
  }
}

/// 在线作品卡片（中卡规格：封面 1.3 + 信息区）。
class _OnlineWorkCard extends StatelessWidget {
  const _OnlineWorkCard({required this.work});

  final OnlineWork work;

  @override
  Widget build(BuildContext context) {
    final online = context.watch<OnlineProvider>();
    final mirror = context.read<MirrorProvider>();
    final scheme = Theme.of(context).colorScheme;
    final downloaded = online.downloadedRjCodes.contains(work.rjCode);

    return InkWell(
      onTap: () => _openDetail(context),
      borderRadius: BorderRadius.circular(UiRadii.control),
      child: Padding(
        padding: const EdgeInsets.all(UiSpacing.small - 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(UiRadii.control),
                    child: CachedNetworkImage(
                      imageUrl: mirror.api.coverUrl(work.id),
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: scheme.surfaceContainerHighest,
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(Icons.album,
                            color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  // RJ 号角标。
                  Positioned(
                    left: UiSpacing.xSmall,
                    bottom: UiSpacing.xSmall,
                    child: _badge(context, work.rjCode),
                  ),
                  // 已下载角标（PRD §5.12：点击直接进入本地版）。
                  if (downloaded)
                    Positioned(
                      right: UiSpacing.xSmall,
                      top: UiSpacing.xSmall,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.9),
                          borderRadius:
                              BorderRadius.circular(UiRadii.tag),
                        ),
                        child: const Text(
                          '已下载',
                          style: TextStyle(
                              color: Colors.white, fontSize: 10, height: 1.2),
                        ),
                      ),
                    ),
                  if (work.nsfw)
                    Positioned(
                      right: UiSpacing.xSmall,
                      bottom: UiSpacing.xSmall,
                      child: _badge(context, 'R18',
                          color: scheme.error),
                    ),
                ],
              ),
            ),
            const SizedBox(height: UiSpacing.xSmall),
            Text(
              work.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500),
            ),
            if (work.circleName != null) ...[
              const SizedBox(height: 2),
              Text(
                work.circleName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: UiTextStyles.supporting.fontSize,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              [
                if (work.release != null)
                  '${work.release!.year}-${work.release!.month.toString().padLeft(2, '0')}-${work.release!.day.toString().padLeft(2, '0')}',
                if (work.averageRating != null)
                  '★${work.averageRating!.toStringAsFixed(1)}',
                if (work.dlCount != null) '${work.dlCount} 销量',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: UiTextStyles.supporting.fontSize,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: (color ?? Colors.black).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(UiRadii.tag),
      ),
      child: Text(
        text,
        style: const TextStyle(
            color: Colors.white, fontSize: 10, height: 1.2,
            fontWeight: FontWeight.w500),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => OnlineWorkDetailScreen(work: work),
      ),
    );
  }
}
