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
    final mirror = context.read<MirrorProvider>();
    final audio = context.read<AudioPlayerProvider>();
    final detail = _detail;
    if (detail == null) return;

    final nodes = _tracks == null
        ? <OnlineFileNode>[]
        : _OnlineFileTree.flatten(_tracks!);
    final tracks = <AudioTrack>[];
    for (final node in nodes) {
      try {
        tracks.add(AudioTrack(
          id: 'online_${detail.id}_${node.title}',
          title: _stripExtension(node.title),
          artist: detail.title,
          source: mirror.api.nodeStreamUrl(node),
          artworkUrl: mirror.api.coverUrl(detail.id),
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
                        flatAudioNodes:
                            _OnlineFileTree.flatten(_tracks!),
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

/// 在线文件树（目录可折叠；展开内容紧跟所属文件夹，音轨行点按流播）。
class _OnlineFileTree extends StatefulWidget {
  const _OnlineFileTree({
    required this.nodes,
    required this.onTrackTap,
    this.depth = 0,
    required this.flatAudioNodes,
  });

  final List<OnlineFileNode> nodes;
  final void Function(int trackIndex) onTrackTap;

  /// 嵌套深度（缩进用）。
  final int depth;

  /// 整棵树扁平化后的音轨列表（根实例计算，逐层透传；序号与播放队列一致）。
  final List<OnlineFileNode> flatAudioNodes;

  /// 扁平化音轨（树前序遍历）。
  static List<OnlineFileNode> flatten(List<OnlineFileNode> nodes) {
    final out = <OnlineFileNode>[];
    void walk(List<OnlineFileNode> list) {
      for (final n in list) {
        if (n.isFolder) {
          walk(n.children);
        } else if (n.isAudio) {
          out.add(n);
        }
      }
    }

    walk(nodes);
    return out;
  }

  @override
  State<_OnlineFileTree> createState() => _OnlineFileTreeState();
}

class _OnlineFileTreeState extends State<_OnlineFileTree> {
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    // 顶层目录默认展开。
    if (widget.depth == 0) {
      for (final node in widget.nodes) {
        if (node.isFolder) _expanded.add(node.title);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final indent = widget.depth * 20.0;

    return Column(
      children: [
        for (final node in widget.nodes)
          if (node.isFolder) ...[
            // 文件夹行：点按切换展开。
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.only(left: 16 + indent, right: 16),
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
            ),
            // 展开的子树紧随其后（递归内联）。
            if (_expanded.contains(node.title) && node.children.isNotEmpty)
              _OnlineFileTree(
                nodes: node.children,
                onTrackTap: widget.onTrackTap,
                depth: widget.depth + 1,
                flatAudioNodes: widget.flatAudioNodes,
              ),
          ] else if (node.isAudio)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.only(left: 16 + indent, right: 16),
              leading: Icon(Icons.music_note_outlined,
                  size: UiIconSize.large, color: scheme.onSurfaceVariant),
              title: Text(
                _stripExt(node.title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.play_circle_outline),
              onTap: () =>
                  widget.onTrackTap(widget.flatAudioNodes.indexOf(node)),
            ),
      ],
    );
  }

  String _stripExt(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}
