import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/net_meta.dart';
import '../models/work.dart';
import '../services/net_meta_service.dart';
import '../providers/audio_provider.dart';
import '../providers/library_provider.dart';
import '../utils/playback_helpers.dart';
import '../utils/ui_tokens.dart';
import '../widgets/enhanced_work_card.dart';
import '../widgets/file_tree_view.dart';
import 'audio_player_screen.dart';

/// 本地作品详情页（PRD §5.5，骨架 = OfflineWorkDetailScreen + WorkDetailScreen
/// 视觉规格；网络参考区 M4 里程碑引入，当前页面 100% 本地信息）。
class WorkDetailScreen extends StatefulWidget {
  const WorkDetailScreen({super.key, required this.work});

  final Work work;

  @override
  State<WorkDetailScreen> createState() => _WorkDetailScreenState();
}

class _WorkDetailScreenState extends State<WorkDetailScreen> {
  List<FileNode> _nodes = const [];
  bool _fileTreeExpanded = true;
  NetMeta? _netMeta;
  bool _netMetaLoading = false;

  /// 封面兜底回写后的最新作品对象（覆盖 widget.work 显示）。
  Work? _workOverride;

  @override
  void initState() {
    super.initState();
    _loadNodes();
    _loadNetMeta();
  }

  Future<void> _loadNodes() async {
    final library = context.read<LibraryProvider>();
    final nodes = await library.nodesOf(widget.work);
    if (mounted) {
      setState(() => _nodes = nodes);
    }
  }

  /// M11 网络参考信息（PRD §5.5：本地信息优先，网络参考只补充显示在下方独立区块）。
  Future<void> _loadNetMeta({bool forceRefresh = false}) async {
    final rjCode = widget.work.rjCode;
    if (rjCode == null) return; // 未识别 RJ 的作品无参考信息。
    setState(() => _netMetaLoading = true);
    try {
      final meta = await context
          .read<NetMetaService>()
          .getMeta(rjCode, forceRefresh: forceRefresh);
      if (mounted) {
        // 网络封面可能已落盘回写（PRD 封面降级链），重新读作品对象刷新显示。
        final fresh =
            await context.read<LibraryProvider>().reloadWork(widget.work.id);
        setState(() {
          _netMeta = meta;
          if (fresh != null) _workOverride = fresh;
        });
      }
    } catch (e) {
      // 网络参考 best-effort：失败静默不显示（PRD 决策 4）；但记录原因便于诊断。
      debugPrint('[NetMeta] 详情页拉取失败: $e');
    } finally {
      if (mounted) setState(() => _netMetaLoading = false);
    }
  }

  Future<void> _playFrom(int trackIndex) async {
    final audio = context.read<AudioPlayerProvider>();
    final tracks = tracksOf(widget.work, _nodes);
    if (tracks.isEmpty) return;
    // 零延迟：先跳转播放器，音源后台加载（播放器自带 loading 态）。
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const AudioPlayerScreen(),
      ),
    );
    final index = trackIndex.clamp(0, tracks.length - 1);
    unawaited(audio.playTracks(tracks, initialIndex: index));
  }

  Future<void> _confirmRemove() async {
    final library = context.read<LibraryProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移出本地库'),
        content: Text('「${widget.work.title}」将从本地库移除（不删除源文件）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await library.removeWork(widget.work);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String? _formatTotalDuration(int? seconds) {
    if (seconds == null) return null;
    if (seconds < 3600) return '${seconds ~/ 60} 分钟';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return m > 0 ? '$h 小时 $m 分钟' : '$h 小时';
  }

  @override
  Widget build(BuildContext context) {
    final work = _workOverride ?? widget.work;
    final library = context.watch<LibraryProvider>();
    final related = library.relatedWorks(work);

    return Scaffold(
      appBar: AppBar(
        title: Text(work.rjCode ?? '本地作品'),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_circle_outline),
            tooltip: '播放全部',
            onPressed: () => unawaited(_playFrom(0)),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'remove') unawaited(_confirmRemove());
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'remove',
                child: Text('移出本地库'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        key: const PageStorageKey('work_detail_${0}'),
        padding: const EdgeInsets.fromLTRB(
            UiSpacing.large, UiSpacing.small, UiSpacing.large, UiSpacing.xLarge),
        children: [
          // ① 封面框（沉浸式：宽至屏宽-32，4:3 实测封面比例零裁切）。
          Center(
            child: Hero(
              tag: 'work_cover_${work.id}',
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width =
                      constraints.maxWidth.clamp(0, 480).toDouble();
                  return SizedBox(
                    width: width,
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: WorkCover(
                        work: work,
                        borderRadius: UiRadii.list,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: UiSpacing.large),

          // ② 标题行：16sp 自适应换行完整显示（§4.7 强约束：无 ellipsis）。
          Text(
            work.title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontSize: 22, fontWeight: FontWeight.bold),
            maxLines: null,
            overflow: TextOverflow.visible,
          ),
          const SizedBox(height: UiSpacing.small),

          // ③ 本地文件信息（RJ 号、文件数、总时长、本地路径）。
          _InfoRow(label: work.rjCode ?? '未识别 RJ 号', icon: Icons.tag),
          const SizedBox(height: UiSpacing.xSmall),
          _InfoRow(
            label: '${work.trackCount} 个音轨'
                '${_formatTotalDuration(work.durationSeconds) != null ? ' · ${_formatTotalDuration(work.durationSeconds)}' : ''}'
                '${work.hasLyric ? ' · 含歌词' : ''}'
                '${work.hasSubtitle ? ' · 含字幕' : ''}',
            icon: Icons.music_note_outlined,
          ),
          const SizedBox(height: UiSpacing.xSmall),
          _InfoRow(label: work.rootPath, icon: Icons.folder_outlined),
          if (work.circleName != null) ...[
            const SizedBox(height: UiSpacing.xSmall),
            _InfoRow(label: work.circleName!, icon: Icons.group_outlined),
          ],

          const SizedBox(height: UiSpacing.large),

          // ⑩ 文件树（可折叠）。
          _SectionHeader(
            title: '文件',
            trailing: IconButton(
              icon: Icon(
                _fileTreeExpanded
                    ? Icons.expand_less
                    : Icons.expand_more,
              ),
              onPressed: () =>
                  setState(() => _fileTreeExpanded = !_fileTreeExpanded),
            ),
          ),
          if (_fileTreeExpanded)
            FileTreeView(
              nodes: _nodes,
              onTrackTap: (index, node) => unawaited(_playFrom(index)),
            ),

          // ---- 网络参考信息（M11，PRD §5.5 ④–⑨：独立区块，辅助样式）----
          if (_netMetaLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: UiSpacing.medium),
              child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else if (_netMeta != null && !_netMeta!.noResult) ...[
            const SizedBox(height: UiSpacing.small),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: UiSpacing.small),
              child: Row(
                children: [
                  Expanded(
                    child: Text('网络参考信息',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 15)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: '刷新参考信息',
                    onPressed: () => _loadNetMeta(forceRefresh: true),
                  ),
                ],
              ),
            ),
            if (_netMeta!.netTitle != null &&
                _netMeta!.netTitle != widget.work.title)
              _RefLine(label: _netMeta!.netTitle!),
            if (_netMeta!.netCircle != null &&
                _netMeta!.netCircle != widget.work.circleName)
              _RefLine(label: '社团：${_netMeta!.netCircle!}'),
            if (_netMeta!.netVas.isNotEmpty)
              _RefLine(label: 'CV：${_netMeta!.netVas.join(' / ')}'),
            if (_netMeta!.netRelease != null)
              _RefLine(
                  label: '发行：${_netMeta!.netRelease!.year}-${_netMeta!.netRelease!.month.toString().padLeft(2, '0')}-${_netMeta!.netRelease!.day.toString().padLeft(2, '0')}'),
            if (_netMeta!.netRateAverage != null)
              _RefLine(
                  label: '评分：★${_netMeta!.netRateAverage!.toStringAsFixed(1)}（${_netMeta!.netRateCount ?? 0} 评价）'),
            if (_netMeta!.netTags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: UiSpacing.xSmall),
                child: Wrap(
                  spacing: UiSpacing.xSmall,
                  runSpacing: UiSpacing.xSmall,
                  children: [
                    for (final tag in _netMeta!.netTags.take(12))
                      Chip(
                        label: Text(tag, style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ),
            if (_netMeta!.netDescription != null &&
                _netMeta!.netDescription!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: UiSpacing.small),
                child: Text(
                  _netMeta!.netDescription!,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],

          const SizedBox(height: UiSpacing.large),

          // ⑪ 推荐位：横向滚动卡片列，高 190dp，卡片宽 120dp
          // （内容源：同社团/同标签的其他本地作品，PRD §5.5）。
          if (related.isNotEmpty) ...[
            _SectionHeader(title: '相关推荐'),
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: related.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: UiSpacing.medium),
                itemBuilder: (context, index) => _RelatedCard(
                  work: related[index],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: scheme.onSurfaceVariant),
        const SizedBox(width: UiSpacing.small),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: UiSpacing.small),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 18,
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _RelatedCard extends StatelessWidget {
  const _RelatedCard({required this.work});

  final Work work;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => WorkDetailScreen(work: work),
            ),
          );
        },
        borderRadius: BorderRadius.circular(UiRadii.control),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 0.72,
              child: WorkCover(work: work),
            ),
            const SizedBox(height: UiSpacing.xSmall),
            Text(
              work.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}


/// 参考区信息行（辅助样式：12sp 次级色，PRD §5.1 信息分层总则）。
class _RefLine extends StatelessWidget {
  const _RefLine({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          height: 1.4,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
