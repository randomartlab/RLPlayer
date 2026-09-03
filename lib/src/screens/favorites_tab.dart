/// 「我的-收藏」Tab（2026-09-03 v1.5.2 重构）：账号在 asmr.one 的全部
/// 书签，复刻「作品-在线」瀑布流：
/// - 分页拉取 favourites（每 20）+ 下拉刷新；异常不转圈（有错误态/重试）
/// - 顶部按本地状态过滤（想听/在听/听过/回味/搁置/未标记）
/// - 卡片：封面 + 标题渐变 + 状态徽章 + 已收藏标记；点开在线详情
///
/// 与「喜欢」的区别（2026-09-03 用户梳理）：
/// 收藏 = 同步到 asmr.one 账号的书签（跨设备）；喜欢 ♥ = 仅本机的独立标记。
library;

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

const List<(String, String?)> _statusFilters = [
  ('全部', null),
  ('想听', 'marked'),
  ('在听', 'listening'),
  ('听过', 'listened'),
  ('回味', 'replay'),
  ('搁置', 'postponed'),
  ('未标记', 'none'),
];

class FavoritesTab extends StatefulWidget {
  const FavoritesTab({super.key});

  @override
  State<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<FavoritesTab> {
  final List<OnlineWork> _items = [];
  final Set<int> _seen = {};
  bool _loading = false;
  bool _error = false;
  bool _noMore = false;
  int _page = 0;

  /// 本地 work_status 快照（rj_code → status）。
  Map<String, String> _localStatus = {};
  String? _statusFilter; // null=全部, 'none'=未标记

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final mirror = context.read<MirrorProvider>();
    if (!mirror.hasAnyLogin) {
      setState(() {
        _loading = false;
        _error = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
      _noMore = false;
      _page = 0;
      _items.clear();
      _seen.clear();
    });
    await _loadStatusMap();
    await _loadPage(1);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadStatusMap() async {
    final db = context.read<LibraryProvider>().database;
    if (db == null) return;
    try {
      final rows = await db.allWorkStatus();
      if (!mounted) return;
      final map = <String, String>{};
      for (final r in rows) {
        map[(r['rj_code'] as String).toUpperCase()] =
            (r['status'] ?? 'none') as String;
      }
      setState(() => _localStatus = map);
    } catch (_) {}
  }

  Future<void> _loadPage(int page) async {
    final mirror = context.read<MirrorProvider>();
    try {
      final works = await mirror
          .withLoginHost((api) => api.getFavorites(page: page));
      if (!mounted) return;
      if (works == null) {
        setState(() {
          _error = true;
          _loading = false;
        });
        return;
      }
      setState(() {
        _page = page;
        for (final w in works) {
          if (_seen.add(w.id)) _items.add(w);
        }
        _noMore = works.length < 20;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('收藏拉取失败：$e'), duration: const Duration(seconds: 3)));
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _noMore || _error) return;
    setState(() => _loading = true);
    await _loadPage(_page + 1);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _remove(OnlineWork w) async {
    final mirror = context.read<MirrorProvider>();
    try {
      await mirror.withLoginHost((api) => api.removeFromFavorites(w.id));
      if (!mounted) return;
      // 同步内存书签态，避免详情页图标残留。
      context.read<OnlineProvider>().forgetFavorite(w.id);
      setState(() {
        _items.removeWhere((e) => e.id == w.id);
        _seen.remove(w.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已取消收藏：${w.title}'),
          duration: const Duration(seconds: 2)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('取消收藏失败：$e'), duration: const Duration(seconds: 3)));
    }
  }

  List<OnlineWork> get _visible {
    if (_statusFilter == null) return _items;
    return _items.where((w) {
      final s = _localStatus[w.rjCode.toUpperCase()] ?? 'none';
      if (_statusFilter == 'none') return s == 'none' || s.isEmpty;
      return s == _statusFilter;
    }).toList();
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
              Text('设置 → 服务器与账号 登录 asmr.one',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // 状态过滤 chips（本地五态；收藏瀑布与本地状态联动展示）。
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: UiSpacing.medium, vertical: 4),
            children: [
              for (final (label, value) in _statusFilters)
                Padding(
                  padding: const EdgeInsets.only(right: UiSpacing.xSmall),
                  child: FilterChip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    selected: _statusFilter == value,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onSelected: (_) =>
                        setState(() => _statusFilter = value),
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
              Icon(_error ? Icons.error_outline : Icons.bookmark_outline,
                  size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: UiSpacing.medium),
              Text(_error ? '收藏加载失败' : '账号暂无收藏',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              if (_error)
                FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
            ],
          ),
        ),
      );
    }

    final visible = _visible;
    if (visible.isEmpty) {
      return Center(
        child: Text('该状态下暂无收藏',
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: MasonryGridView.count(
        padding: const EdgeInsets.all(UiSpacing.small),
        crossAxisCount: 2,
        mainAxisSpacing: UiSpacing.small,
        crossAxisSpacing: UiSpacing.small,
        itemCount: visible.length + (!_noMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= visible.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: _error
                    ? OutlinedButton(
                        onPressed: _loadMore, child: const Text('重试加载'))
                    : OutlinedButton(
                        onPressed: _loadMore, child: const Text('加载更多')),
              ),
            );
          }
          final w = visible[index];
          return _FavoriteCard(
            work: w,
            status: _localStatus[w.rjCode.toUpperCase()] ?? 'none',
            onRemove: () => _remove(w),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => OnlineWorkDetailScreen(work: w))),
          );
        },
      ),
    );
  }
}

/// 收藏瀑布卡（复刻「作品-在线」卡：封面 4:3 + 渐变标题 + 徽章）。
class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({
    required this.work,
    required this.status,
    required this.onRemove,
    required this.onTap,
  });

  final OnlineWork work;
  final String status;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  static const Map<String, (String, IconData)> _statusMeta = {
    'marked': ('想听', Icons.headphones_outlined),
    'listening': ('在听', Icons.play_circle_outline),
    'listened': ('听过', Icons.task_alt),
    'replay': ('回味', Icons.replay_circle_filled_outlined),
    'postponed': ('搁置', Icons.snooze_outlined),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = _statusMeta[status];
    final mirror = context.read<MirrorProvider>();
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
            // 底部渐变遮罩 + 标题。
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets.fromLTRB(8, 18, 8, 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Text(
                  work.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
            // 状态徽章。
            if (meta != null)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(meta.$2,
                          size: 11, color: scheme.onPrimary),
                      const SizedBox(width: 3),
                      Text(meta.$1,
                          style: TextStyle(
                              fontSize: 10,
                              color: scheme.onPrimary)),
                    ],
                  ),
                ),
              ),
            // 取消收藏。
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
