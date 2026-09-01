import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/audio_track.dart';
import '../models/online_models.dart';
import '../providers/audio_provider.dart';
import '../providers/download_provider.dart';
import '../providers/library_provider.dart';
import '../providers/mirror_provider.dart';
import '../providers/online_provider.dart';
import '../utils/ui_tokens.dart';
import 'audio_player_screen.dart';
import 'work_detail_screen.dart';

/// 在线作品详情页（M12，沿用原版 work_detail_screen 布局骨架）：
/// 封面/标题/社团/标签/CV/简介/评分 + 文件树（流播/下载）。
/// 已下载 → 本地版详情（下载即入库互通，验收 #16）。
class OnlineWorkDetailScreen extends StatefulWidget {
  const OnlineWorkDetailScreen({super.key, required this.work});

  final OnlineWork work;

  @override
  State<OnlineWorkDetailScreen> createState() =>
      _OnlineWorkDetailScreenState();
}

class _OnlineWorkDetailScreenState extends State<OnlineWorkDetailScreen> {
  OnlineWork? _detail;
  List<OnlineFileNode>? _tracks;
  bool _loading = true;
  bool _tracksLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    // 先取依赖（await 前取 context，避免 async gap lint）。
    final online = context.read<OnlineProvider>();
    final api = context.read<MirrorProvider>().api;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await online.getWorkDetail(widget.work.id);
      if (mounted) setState(() => _detail = detail);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    // 文件树独立接口（/api/tracks/{id}）。
    try {
      final tracks = await api.getTracks(widget.work.id);
      if (mounted) setState(() => _tracks = tracks);
    } catch (_) {
      if (mounted) setState(() => _tracks = const []);
    } finally {
      if (mounted) setState(() => _tracksLoading = false);
    }
  }

  /// 流媒体播放：整作品队列（与本地播放共用内核，PRD §5.12）。
  Future<void> _playFrom(int startIndex) async {
    final online = context.read<OnlineProvider>();
    final mirror = context.read<MirrorProvider>();
    final audio = context.read<AudioPlayerProvider>();
    final detail = _detail;
    if (detail == null) return;

    final nodes = _tracks == null
        ? <OnlineFileNode>[]
        : online.flattenAudioNodes(_tracks!);
    final tracks = <AudioTrack>[];
    for (final node in nodes) {
      try {
        tracks.add(AudioTrack(
          id: 'online_${detail.id}_${node.title}',
          title: _stripExtension(node.title),
          artist: detail.title,
          source: mirror.api.nodeStreamUrl(node),
          artworkPath: null, // 在线封面走 URL，播放器 M3 显示占位
        ));
      } catch (_) {
        continue; // 缺 hash 的节点跳过。
      }
    }
    if (tracks.isEmpty) return;
    await audio.playTracks(tracks, initialIndex: startIndex);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (context) => const AudioPlayerScreen()),
    );
  }

  String _stripExtension(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// 下载全部音轨（下载即入库：落到扫描根目录 downloads/，完成触发重扫）。
  void _downloadAll() {
    final online = context.read<OnlineProvider>();
    final mirror = context.read<MirrorProvider>();
    final downloads = context.read<DownloadProvider>();
    final detail = _detail;
    if (detail == null) return;

    final nodes = _tracks == null
        ? <OnlineFileNode>[]
        : online.flattenAudioNodes(_tracks!);
    downloads.service.enqueueWork(detail, nodes,
        (node) => mirror.api.nodeDownloadUrl(node));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已加入下载队列：${detail.rjCode}（${nodes.length} 个文件）'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final online = context.watch<OnlineProvider>();
    final mirror = context.read<MirrorProvider>();
    final downloaded = online.downloadedRjCodes.contains(widget.work.rjCode);
    final work = _detail ?? widget.work;

    return Scaffold(
      appBar: AppBar(
        title: Text(work.rjCode),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: '下载全部',
            onPressed: _loading || _tracksLoading ? null : _downloadAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(context)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(UiSpacing.large,
                      UiSpacing.small, UiSpacing.large, UiSpacing.xLarge),
                  children: [
                    // 已下载 → 本地版详情入口（本地优先，PRD §5.12）。
                    if (downloaded)
                      Padding(
                        padding: const EdgeInsets.only(bottom: UiSpacing.medium),
                        child: Card(
                          color: scheme.primaryContainer,
                          child: ListTile(
                            leading: Icon(Icons.download_done,
                                color: scheme.onPrimaryContainer),
                            title: Text(
                              '已下载到本地库，点击打开本地版详情',
                              style: TextStyle(
                                  color: scheme.onPrimaryContainer,
                                  fontSize: 13),
                            ),
                            trailing: Icon(Icons.chevron_right,
                                color: scheme.onPrimaryContainer),
                            onTap: _openLocalDetail,
                          ),
                        ),
                      ),
                    Center(
                      child: SizedBox(
                        width: 220,
                        height: 220,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(UiRadii.list),
                          child: CachedNetworkImage(
                            imageUrl: mirror.api.coverUrl(work.id),
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                                color: scheme.surfaceContainerHighest),
                            errorWidget: (context, url, error) => Container(
                              color: scheme.surfaceContainerHighest,
                              child: Icon(Icons.album,
                                  color: scheme.onSurfaceVariant, size: 48),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: UiSpacing.large),
                    Text(
                      work.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: null,
                      overflow: TextOverflow.visible,
                    ),
                    if (work.titleTranslation != null &&
                        work.titleTranslation!.isNotEmpty) ...[
                      const SizedBox(height: UiSpacing.xSmall),
                      Text(
                        work.titleTranslation!,
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: UiSpacing.small),
                    _InfoLine(
                        icon: Icons.group_outlined,
                        text: work.circleName ?? '未知社团'),
                    if (work.vas.isNotEmpty)
                      _InfoLine(
                          icon: Icons.mic_outlined,
                          text: 'CV：${work.vas.join(' / ')}'),
                    _InfoLine(
                        icon: Icons.star_outline,
                        text: '★${work.averageRating?.toStringAsFixed(1) ?? '-'}'
                            '（${work.ratingCount ?? 0} 评价 · ${work.dlCount ?? 0} 销量）'),
                    if (work.release != null)
                      _InfoLine(
                          icon: Icons.calendar_today_outlined,
                          text:
                              '发行：${work.release!.year}-${work.release!.month.toString().padLeft(2, '0')}-${work.release!.day.toString().padLeft(2, '0')}'),
                    if (work.tags.isNotEmpty) ...[
                      const SizedBox(height: UiSpacing.medium),
                      Wrap(
                        spacing: UiSpacing.xSmall,
                        runSpacing: UiSpacing.xSmall,
                        children: [
                          for (final tag in work.tags.take(12))
                            Chip(
                              label: Text(tag,
                                  style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                        ],
                      ),
                    ],
                    if (work.description != null &&
                        work.description!.isNotEmpty) ...[
                      const SizedBox(height: UiSpacing.medium),
                      Text(
                        work.description!,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 8,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: UiSpacing.large),
                    // 文件树（流播入口）。
                    Text('音轨',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: UiSpacing.xSmall),
                    if (_tracksLoading)
                      const Padding(
                        padding: EdgeInsets.all(UiSpacing.medium),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_tracks != null && _tracks!.isNotEmpty)
                      _OnlineFileTree(
                        nodes: _tracks!,
                        onTrackTap: (index) => unawaited(_playFrom(index)),
                      ),
                  ],
                ),
    );
  }

  void _openLocalDetail() {
    final library = context.read<LibraryProvider>();
    final local = library.works
        .where((w) => w.rjCode == widget.work.rjCode)
        .firstOrNull;
    if (local == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (context) => WorkDetailScreen(work: local),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(UiSpacing.xLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 64, color: scheme.onSurfaceVariant),
            const SizedBox(height: UiSpacing.medium),
            Text('详情加载失败',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: UiSpacing.large),
            FilledButton.icon(
              onPressed: _loadDetail,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: UiSpacing.xSmall),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: UiIconSize.standard, color: scheme.onSurfaceVariant),
          const SizedBox(width: UiSpacing.small),
          Expanded(
            child: Text(
              text,
              style: UiTextStyles.supporting
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// 在线文件树（目录可折叠；音轨行点按流播）。
class _OnlineFileTree extends StatefulWidget {
  const _OnlineFileTree({required this.nodes, required this.onTrackTap});

  final List<OnlineFileNode> nodes;
  final void Function(int trackIndex) onTrackTap;

  @override
  State<_OnlineFileTree> createState() => _OnlineFileTreeState();
}

class _OnlineFileTreeState extends State<_OnlineFileTree> {
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    for (final node in widget.nodes) {
      if (node.isFolder) _expanded.add(node.title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final node in widget.nodes)
          if (node.isFolder)
            ListTile(
              dense: true,
              leading: Icon(
                _expanded.contains(node.title)
                    ? Icons.folder_open
                    : Icons.folder_outlined,
                color: scheme.primary,
                size: UiIconSize.large,
              ),
              title: Text(node.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Icon(
                  _expanded.contains(node.title)
                      ? Icons.expand_less
                      : Icons.expand_more,
                  color: scheme.onSurfaceVariant),
              onTap: () => setState(() {
                _expanded.contains(node.title)
                    ? _expanded.remove(node.title)
                    : _expanded.add(node.title);
              }),
            )
          else if (node.isAudio)
            Builder(builder: (context) {
              final index = _audioOrdinal(node);
              return ListTile(
                dense: true,
                leading: SizedBox(
                  width: UiIconSize.large,
                  child: Text('$index',
                      textAlign: TextAlign.center,
                      style: UiTextStyles.supporting
                          .copyWith(color: scheme.onSurfaceVariant)),
                ),
                title: Text(node.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.play_circle_outline),
                onTap: () => widget.onTrackTap(_globalAudioIndex(node)),
              );
            }),
        // 展开的目录渲染子树。
        for (final node in widget.nodes)
          if (node.isFolder && _expanded.contains(node.title))
            Padding(
              padding: const EdgeInsets.only(left: UiSpacing.large),
              child: _OnlineFileTree(
                nodes: node.children,
                onTrackTap: widget.onTrackTap,
              ),
            ),
      ],
    );
  }

  /// 目录内序号（简化：用于展示）。
  int _audioOrdinal(OnlineFileNode node) {
    var i = 0;
    for (final n in widget.nodes) {
      if (n.isAudio) {
        i++;
        if (identical(n, node)) return i;
      }
    }
    return i;
  }

  /// 全局音轨序号（与播放队列一致）：扁平展开后的位置。
  int _globalAudioIndex(OnlineFileNode node) {
    void collect(List<OnlineFileNode> nodes, List<OnlineFileNode> out) {
      for (final n in nodes) {
        if (n.isFolder) {
          collect(n.children, out);
        } else if (n.isAudio) {
          out.add(n);
        }
      }
    }

    final flat = <OnlineFileNode>[];
    collect(widget.nodes, flat);
    return flat.indexOf(node);
  }
}
