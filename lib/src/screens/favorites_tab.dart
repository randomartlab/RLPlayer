/// 「我的-在线收藏」Tab（2026-09-03 M2）。
///
/// 登录后拉取 asmr.one favourites（分页），本地已有显示「本地」徽章，
/// 可移除收藏；点击进在线详情。游客引导到设置登录。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/online_models.dart';
import '../providers/library_provider.dart';
import '../providers/mirror_provider.dart';
import '../utils/ui_tokens.dart';
import 'online_work_detail_screen.dart';

class FavoritesTab extends StatefulWidget {
  const FavoritesTab({super.key});

  @override
  State<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<FavoritesTab> {
  final List<OnlineWork> _items = [];
  bool _loading = false;
  bool _loadError = false;
  bool _noMore = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(1));
  }

  Future<void> _load(int page) async {
    final mirror = context.read<MirrorProvider>();
    if (!mirror.hasAnyLogin) return;
    setState(() => _loading = true);
    final works = await mirror.withLoginHost((api) => api.getFavorites(page: page));
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (works == null) {
        _loadError = true;
        return;
      }
      _loadError = false;
      _page = page;
      final seen = _items.map((e) => e.id).toSet();
      for (final w in works) {
        if (!seen.contains(w.id)) _items.add(w);
      }
      _noMore = works.length < 20;
    });
  }

  Future<void> _loadMore() async {
    if (_loading || _noMore) return;
    await _load(_page + 1);
  }

  Future<void> _remove(OnlineWork w) async {
    final mirror = context.read<MirrorProvider>();
    await mirror.withLoginHost((api) => api.removeFromFavorites(w.id));
    if (!mounted) return;
    setState(() => _items.removeWhere((e) => e.id == w.id));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已取消收藏：${w.title}'),
        duration: const Duration(seconds: 2)));
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
              Icon(Icons.bookmark_border,
                  size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: UiSpacing.medium),
              Text('登录后可查看在线收藏',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: UiSpacing.xSmall),
              Text('请到 设置 → 服务器与账号 登录 asmr.one 账号',
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
              Text(_loadError ? '收藏加载失败' : '暂无收藏',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              if (_loadError)
                TextButton(onPressed: () => _load(1), child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _items.clear();
        _noMore = false;
        _page = 0;
        await _load(1);
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: UiSpacing.small),
        itemCount: _items.length + (_noMore || _loading ? 0 : 1),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: OutlinedButton(
                    onPressed: _loadMore, child: const Text('加载更多')),
              ),
            );
          }
          final w = _items[index];
          final rj = (w.sourceId ?? 'RJ${w.id}').toUpperCase();
          final hasLocal = localRjs.contains(rj);
          return ListTile(
            leading: SizedBox(
              width: 52,
              height: 52,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  mirror.api.coverUrl(w.id),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(Icons.album,
                          color: scheme.onSurfaceVariant)),
                ),
              ),
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
                  child: Text(w.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            subtitle: Text(
              [w.circleName ?? '', rj].where((e) => e.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.bookmark_remove_outlined, size: 20),
              tooltip: '取消收藏',
              onPressed: () => _remove(w),
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => OnlineWorkDetailScreen(work: w))),
          );
        },
      ),
    );
  }
}
