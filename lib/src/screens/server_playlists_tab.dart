/// 「我的-播放列表」Tab（2026-09-03 v1.5.4）：本地 / 账号 双视图。
/// 账号视图 = kikoeru-express 服务器歌单（与 one 站账号同步），
/// 点歌单拉取歌单内作品并进入在线详情；本地视图保留原 PlaylistsScreen。
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/online_models.dart';
import '../providers/mirror_provider.dart';
import '../utils/ui_tokens.dart';
import 'online_work_detail_screen.dart';
import 'playlists_screen.dart';

enum _PlView { local, account }

class ServerPlaylistsTab extends StatefulWidget {
  const ServerPlaylistsTab({super.key});

  @override
  State<ServerPlaylistsTab> createState() => _ServerPlaylistsTabState();
}

class _ServerPlaylistsTabState extends State<ServerPlaylistsTab> {
  _PlView _view = _PlView.local;
  List<Map<String, dynamic>> _playlists = const [];
  bool _loading = false;
  bool _error = false;
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mirror = context.watch<MirrorProvider>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              UiSpacing.medium, UiSpacing.small, UiSpacing.medium, 0),
          child: Row(
            children: [
              SegmentedButton<_PlView>(
                segments: const [
                  ButtonSegment(
                      value: _PlView.local, label: Text('本地歌单')),
                  ButtonSegment(
                      value: _PlView.account, label: Text('账号歌单')),
                ],
                selected: {_view},
                style: const ButtonStyle(
                    visualDensity: VisualDensity.compact),
                onSelectionChanged: (v) async {
                  setState(() => _view = v.first);
                  if (v.first == _PlView.account && !_loaded) {
                    await _load();
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _view == _PlView.local
              ? const PlaylistsScreen()
              : _buildAccount(context, scheme, mirror),
        ),
      ],
    );
  }

  Future<void> _load() async {
    final mirror = context.read<MirrorProvider>();
    if (!mirror.hasAnyLogin) {
      setState(() {
        _loaded = true;
        _loading = false;
        _error = false;
        _playlists = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final list = await mirror.fetchAccountPlaylists();
      if (!mounted) return;
      setState(() {
        _playlists = list;
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
    }
  }

  Widget _buildAccount(BuildContext context, ColorScheme scheme,
      MirrorProvider mirror) {
    if (!mirror.hasAnyLogin) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(UiSpacing.xLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.queue_music,
                  size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: UiSpacing.medium),
              Text('登录后查看账号播放列表',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: UiSpacing.xSmall),
              Text('设置 → 服务器与账号 登录；作品详情可把作品加入账号歌单',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }
    if (_loading && _playlists.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_playlists.isEmpty && _loaded) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_error ? Icons.error_outline : Icons.queue_music,
                size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: UiSpacing.medium),
            Text(_error ? '账号歌单拉取失败' : '账号暂无播放列表',
                style: TextStyle(color: scheme.onSurfaceVariant)),
            if (_error)
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: UiSpacing.small),
        itemCount: _playlists.length,
        itemBuilder: (context, index) {
          final pl = _playlists[index];
          final id = _plId(pl);
          final name = (pl['name'] ?? pl['title'] ?? '未命名') as String;
          final count = _plCount(pl);
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.queue_music,
                  size: 18, color: scheme.onPrimaryContainer),
            ),
            title: Text(name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: count != null
                ? Text('$count 个作品',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant))
                : null,
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: id == null
                ? null
                : () => _openPlaylist(context, id, name),
          );
        },
      ),
    );
  }

  Future<void> _openPlaylist(
      BuildContext context, String id, String name) async {
    final mirror = context.read<MirrorProvider>();
    List<Map<String, dynamic>> raw = const [];
    try {
      raw = await mirror.fetchPlaylistWorks(id);
    } catch (_) {}
    if (!context.mounted) return;
    // 转 OnlineWork 并展示（容忍缺失字段）。
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        if (raw.isEmpty) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                  child: Text('歌单暂无作品',
                      style: TextStyle(color: scheme.onSurfaceVariant))),
            ),
          );
        }
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(UiSpacing.small),
                child: Text('$name（${raw.length}）',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: raw.length,
                  itemBuilder: (context, i) {
                    final item = raw[i];
                    final w = item['work'] is Map<String, dynamic>
                        ? item['work'] as Map<String, dynamic>
                        : item;
                    final idNum = w['id'];
                    final title = (w['title'] ?? '') as String;
                    if (idNum is! num) {
                      return ListTile(
                          dense: true,
                          title: Text('$title',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis));
                    }
                    return ListTile(
                      dense: true,
                      leading: SizedBox(
                        width: 42,
                        height: 42,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: CachedNetworkImage(
                            imageUrl:
                                context.read<MirrorProvider>().api.coverUrl(idNum.toInt()),
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => Container(
                                color: scheme.surfaceContainerHighest,
                                child: Icon(Icons.album,
                                    size: 18,
                                    color: scheme.onSurfaceVariant)),
                          ),
                        ),
                      ),
                      title: Text(title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(
                          builder: (_) => OnlineWorkDetailScreen(
                              work: OnlineWorkLike.fromJson(w)),
                        ));
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 歌单 JSON → OnlineWork（同 OnlineWork.fromJson 宽松构造）。
// ignore: non_constant_identifier_names
class OnlineWorkLike {
  static OnlineWork fromJson(Map<String, dynamic> w) {
    final id = w['id'];
    try {
      return OnlineWork.fromJson(w);
    } catch (_) {
      return OnlineWork(
        id: id is num ? id.toInt() : 0,
        title: (w['title'] ?? '') as String,
      );
    }
  }
}

String? _plId(Map<String, dynamic> pl) {
  final raw = pl['id'] ?? pl['playlist_id'] ?? pl['playlistId'];
  return raw == null ? null : raw.toString();
}

int? _plCount(Map<String, dynamic> pl) {
  final raw = pl['work_count'] ??
      pl['workCount'] ??
      pl['count'] ??
      (pl['works'] is List ? (pl['works'] as List).length : null);
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}
