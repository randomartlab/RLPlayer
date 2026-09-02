import 'dart:io';
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/net_meta.dart';
import '../models/online_models.dart';
import '../providers/mirror_provider.dart';
import '../providers/preferences_provider.dart';
import '../models/work.dart';
import '../services/net_meta_service.dart';
import '../services/translation_service.dart';
import '../providers/audio_provider.dart';
import '../providers/library_provider.dart';
import '../utils/playback_helpers.dart';
import '../utils/ui_tokens.dart';
import '../widgets/translation_toggle_button.dart';
import 'subtitle_preview_screen.dart';
import '../widgets/enhanced_work_card.dart';
import '../widgets/file_tree_view.dart';
import 'audio_player_screen.dart';
import 'online_work_detail_screen.dart';
import 'playlists_screen.dart' show showAddToPlaylistDialog;
import 'tag_filter_screen.dart';

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

  // ---- 标题翻译（实机需求 2026-09-02）----
  String? _titleTranslation;
  bool _titleTranslating = false;

  Future<void> _translateTitle() async {
    if (_titleTranslating) return;
    if (_titleTranslation != null) {
      // 再点切换回原文。
      setState(() => _titleTranslation = null);
      return;
    }
    setState(() => _titleTranslating = true);
    final result = await TranslationService.translate(widget.work.title);
    if (!mounted) return;
    setState(() {
      _titleTranslation = result;
      _titleTranslating = false;
    });
  }

  // ---- CV 名翻译（实机需求 2026-09-02）----
  final Map<String, String> _cvTranslations = {};
  bool _cvTranslating = false;

  Future<void> _translateCvs(List<String> vas) async {
    if (_cvTranslating || vas.isEmpty) return;
    setState(() => _cvTranslating = true);
    final result = await TranslationService.translateBatch(vas);
    if (!mounted) return;
    setState(() {
      _cvTranslations
        ..clear()
        ..addAll(result);
      _cvTranslating = false;
    });
  }

  // ---- 文件树文件名翻译（kikoflu 同款；仅非中文生效）----
  final Map<String, String> _fileTreeTranslations = {};
  bool _fileTreeShowTranslation = false;
  bool _fileTreeTranslating = false;
  String _fileTreeProgress = '';

  Future<void> _toggleFileTreeTranslation() async {
    if (_fileTreeTranslating) return;
    if (_fileTreeTranslations.isNotEmpty) {
      setState(() => _fileTreeShowTranslation = !_fileTreeShowTranslation);
      return;
    }
    if (_nodes.isEmpty) return;
    setState(() {
      _fileTreeTranslating = true;
      _fileTreeShowTranslation = true;
    });
    final names =
        _nodes.map((n) => n.displayName).where((n) => n.isNotEmpty).toList();
    final result = await TranslationService.translateBatch(names,
        onProgress: (done, total) {
      if (mounted) setState(() => _fileTreeProgress = '$done/$total');
    });
    if (!mounted) return;
    setState(() {
      _fileTreeTranslations
        ..clear()
        ..addAll(result);
      _fileTreeTranslating = false;
      _fileTreeProgress = '';
    });
  }

  String _fileTreeDisplayName(String original) =>
      _fileTreeShowTranslation &&
              _fileTreeTranslations.containsKey(original)
          ? _fileTreeTranslations[original]!
          : original;
  NetMeta? _netMeta;
  bool _netMetaLoading = false;

  /// 封面兜底回写后的最新作品对象（覆盖 widget.work 显示）。
  Work? _workOverride;

  /// 网络相关推荐（asmr.one 同社团，M5 用户需求）。
  List<OnlineWork> _onlineRelated = [];

  @override
  void initState() {
    super.initState();
    _loadNodes();
    _loadNetMeta();
  }

  Future<void> _loadNodes() async {
    final library = context.read<LibraryProvider>();
    final nodes = await library.nodesOf(widget.work);
    // 附加字幕/歌词文件节点（预览用，不进播放队列）。
    final subtitleNodes = _scanSubtitleFiles();
    if (mounted) {
      setState(() => _nodes = [...nodes, ...subtitleNodes]);
    }
  }

  /// 扫描作品目录下的 .srt/.vtt/.lrc 文件构造预览节点。
  List<FileNode> _scanSubtitleFiles() {
    final result = <FileNode>[];
    final root = Directory(widget.work.rootPath);
    if (!root.existsSync()) return result;
    // 已作为音轨 sidecar 关联的文件不重复列（树上按节点相对路径去重）。
    final existingPaths = _nodes
        .where((n) => !n.isDirectory)
        .map((n) => n.relativePath)
        .toSet();
    try {
      final entities = root.listSync(recursive: true);
      for (final entity in entities) {
        if (entity is! File) continue;
        final lower = entity.path.toLowerCase();
        if (!lower.endsWith('.srt') &&
            !lower.endsWith('.vtt') &&
            !lower.endsWith('.lrc')) {
          continue;
        }
        final rel = p.relative(entity.path, from: root.path);
        if (existingPaths.contains(rel)) continue;
        final parent = p.dirname(rel) == '.' ? '' : p.dirname(rel);
        result.add(FileNode(
          id: -entity.path.hashCode,
          workId: widget.work.id,
          isDirectory: false,
          name: p.basename(entity.path),
          relativePath: rel,
          parentPath: parent,
          filePath: entity.path,
          isSubtitleFile: true,
        ));
      }
    } catch (_) {
      // 目录不可读时静默——仅少展示字幕文件。
    }
    return result;
  }

  /// M11 网络参考信息（PRD §5.5：本地信息优先，网络参考只补充显示在下方独立区块）。
  Future<void> _loadNetMeta({bool forceRefresh = false}) async {
    final rjCode = widget.work.rjCode;
    if (rjCode == null) return; // 未识别 RJ 的作品无参考信息。
    // 偏好开关：网络元数据关闭时不拉取（PRD 验收：关开关后零请求）。
    if (!forceRefresh &&
        !context.read<PreferencesProvider>().metaEnabled) {
      return;
    }
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
      // 网络相关推荐：能拉到元数据的作品 → asmr.one 同社团作品。
      if (meta != null && !meta.noResult) {
        await _loadOnlineRelated();
      }
    } catch (e) {
      // 网络参考 best-effort：失败静默不显示（PRD 决策 4）；但记录原因便于诊断。
      debugPrint('[NetMeta] 详情页拉取失败: $e');
    } finally {
      if (mounted) setState(() => _netMetaLoading = false);
    }
  }

  /// 网络相关推荐（asmr.one 同社团；本地推荐在前、网络补充在后）。
  Future<void> _loadOnlineRelated() async {
    try {
      final mirror = context.read<MirrorProvider>();
      final numeric = int.tryParse((widget.work.rjCode ?? '')
          .replaceFirst(RegExp('^(RJ|BJ|VJ)', caseSensitive: false), ''));
      if (numeric == null) return;
      final detail = await mirror.api.getWork(numeric);
      final circleId = detail.circleId;
      if (circleId == null) return;
      final related = await mirror.api.getCircleWorks(circleId, pageSize: 12);
      final filtered =
          related.where((w) => w.id != numeric).toList(growable: false);
      if (mounted) {
        setState(() => _onlineRelated = filtered.take(10).toList());
      }
    } catch (_) {
      // 网络推荐 best-effort：失败静默（本地推荐仍显示）。
    }
  }

  /// 按节点精确定位播放（实机 bug 修复：视觉序号 ≠ DB 序号导致点任何
  /// 音轨都播第一个；改为按 track.id 匹配，不依赖顺序）。
  Future<void> _playFromNode(FileNode node) async {
    if (node.isSubtitleFile) {
      // 字幕/歌词文件 → 预览（实机需求 2026-09-02）。
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SubtitlePreviewScreen(
          source: SubtitlePreviewSource(
            title: node.name,
            filePath: node.filePath,
          ),
        ),
      ));
      return;
    }
    final audio = context.read<AudioPlayerProvider>();
    final tracks = tracksOf(widget.work, _nodes);
    if (tracks.isEmpty) return;
    final index = tracks
        .indexWhere((t) => t.id == 'node_${node.id}')
        .clamp(0, tracks.length - 1);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const AudioPlayerScreen(),
      ),
    );
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
            onPressed: () => unawaited(_playFromNode(_nodes.firstWhere(
                  (n) => !n.isDirectory,
                  orElse: () => _nodes.first))),
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

          // ② 标题行：自适应换行完整显示（§4.7 强约束：无 ellipsis）+
          //    非中文标题翻译（实机需求 2026-09-02）。
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  work.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontSize: 22, fontWeight: FontWeight.bold),
                  maxLines: null,
                  overflow: TextOverflow.visible,
                ),
              ),
              if (TranslationService.isMostlyChinese(work.title))
                const SizedBox.shrink()
              else
                _TitleTranslateButton(
                  translating: _titleTranslating,
                  translated: _titleTranslation != null,
                  onPressed: _translateTitle,
                ),
            ],
          ),
          if (_titleTranslation != null) ...[
            const SizedBox(height: UiSpacing.xSmall),
            Text(
              _titleTranslation!,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 17,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              maxLines: null,
            ),
          ],
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
              Row(
                children: [
                  Expanded(
                    child: _RefLine(
                        label: _cvTranslations.isEmpty
                            ? 'CV：${_netMeta!.netVas.join(' / ')}'
                            : 'CV：${_netMeta!.netVas.map((v) => _cvTranslations[v] ?? v).join(' / ')}'),
                  ),
                  if (_netMeta!.netVas
                      .any((v) => !TranslationService.isMostlyChinese(v)))
                    IconButton(
                      onPressed: _cvTranslating
                          ? null
                          : () => _translateCvs(_netMeta!.netVas),
                      icon: _cvTranslating
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.primary),
                            )
                          : Icon(
                              Icons.g_translate,
                              size: 18,
                              color: _cvTranslations.isEmpty
                                  ? Theme.of(context).colorScheme.onSurfaceVariant
                                  : Theme.of(context).colorScheme.primary,
                            ),
                      tooltip: '翻译 CV 名',
                    ),
                ],
              ),
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
                      ActionChip(
                        label: Text(tag, style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        // 点标签 → 过滤本地库同标签作品（用户需求）。
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) =>
                                TagFilterScreen(tag: tag),
                          ),
                        ),
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

          // ⑩ 文件树（恒展开；目录默认收起，点按展开）+ 文件名翻译切换
          // （按钮在标题行右侧，与在线树一致——实机反馈位置太隐蔽）。
          _SectionHeader(
            title: '文件',
            trailing: TranslationToggleButton(
              isTranslated: _fileTreeShowTranslation,
              isLoading: _fileTreeTranslating,
              progress: _fileTreeProgress,
              onPressed: _toggleFileTreeTranslation,
            ),
          ),
          FileTreeView(
            nodes: _nodes,
            onTrackTap: (node) => unawaited(_playFromNode(node)),
            onTrackLongPress: (node) =>
                showAddToPlaylistDialog(context, work, node),
            displayName: _fileTreeDisplayName,
          ),

          // ⑪ 推荐位：本地同社团在前 + asmr.one 同社团网络推荐补充
          // （用户需求 2026-09-01：有 RJ 且能拉到信息的作品拉网络推荐）。
          if (related.isNotEmpty || _onlineRelated.isNotEmpty) ...[
            _SectionHeader(title: '相关推荐'),
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: related.length + _onlineRelated.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: UiSpacing.medium),
                itemBuilder: (context, index) {
                  if (index < related.length) {
                    return _RelatedCard(work: related[index]);
                  }
                  return _OnlineRelatedCard(
                      work: _onlineRelated[index - related.length]);
                },
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

  /// 标题行右侧控件（如文件树翻译切换按钮）。
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
        if (trailing != null) trailing!,
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
            // 与在线推荐卡/详情页头图统一 4:3 横版（实机反馈：本地推荐
            // 封面竖版是遗留比例）。
            AspectRatio(
              aspectRatio: 4 / 3,
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


/// 网络相关推荐卡（asmr.one 同社团作品）。
class _OnlineRelatedCard extends StatelessWidget {
  const _OnlineRelatedCard({required this.work});

  final OnlineWork work;

  @override
  Widget build(BuildContext context) {
    final mirror = context.read<MirrorProvider>();
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 120,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => OnlineWorkDetailScreen(work: work),
            ),
          );
        },
        borderRadius: BorderRadius.circular(UiRadii.control),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(UiRadii.control),
                child: CachedNetworkImage(
                  imageUrl: mirror.api.coverUrl(work.id),
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      Container(color: scheme.surfaceContainerHighest),
                  errorWidget: (context, url, error) => Container(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(Icons.album,
                        color: scheme.onSurfaceVariant, size: 24),
                  ),
                ),
              ),
            ),
            const SizedBox(height: UiSpacing.xSmall),
            Text(
              work.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

/// 标题翻译小按钮（g 图标 + 译/原切换）。
class _TitleTranslateButton extends StatelessWidget {
  const _TitleTranslateButton({
    required this.translating,
    required this.translated,
    required this.onPressed,
  });

  final bool translating;
  final bool translated;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: translating ? null : onPressed,
      icon: translating
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
            )
          : Icon(
              Icons.g_translate,
              size: 22,
              color: translated ? scheme.primary : scheme.onSurfaceVariant,
            ),
      tooltip: translated ? '显示原文' : '翻译标题',
    );
  }
}
