import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/audio_track.dart';
import '../models/online_models.dart';
import '../models/work.dart';
import '../providers/audio_provider.dart';
import '../providers/download_provider.dart';
import '../providers/library_provider.dart';
import '../providers/mirror_provider.dart';
import '../providers/online_provider.dart';
import '../utils/ui_tokens.dart';
import '../widgets/comment_section.dart';
import '../widgets/translation_toggle_button.dart';
import 'audio_player_screen.dart';
import 'package:kiko_local/src/services/translation_service.dart';
import 'online_works_screen.dart';
import 'subtitle_preview_screen.dart';
import 'tag_filter_screen.dart';
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

  /// 字幕/歌词文件数（用户反馈：是否带字幕应明确标注）。
  int _subtitleCount = 0;
  int _lyricCount = 0;

  /// 标题译文（Google gtx，失败保持 null）。
  String? _titleTranslation;
  bool _translating = false;

  // ---- 文件树文件名翻译（状态提升到本层，树组件只读展示）----
  final Map<String, String> _fileTreeTranslations = {};
  bool _fileTreeShowTranslation = false;
  bool _fileTreeTranslating = false;
  String _fileTreeProgress = '';

  bool get _fileTreeTranslationVisible => _fileTreeShowTranslation;

  Future<void> _toggleFileTreeTranslation() async {
    if (_fileTreeTranslating) return;
    if (_fileTreeTranslations.isNotEmpty) {
      // kikoflu 同款：已有译文 → 原文/译文切换。
      setState(() => _fileTreeShowTranslation = !_fileTreeShowTranslation);
      return;
    }
    if (_tracks == null || _tracks!.isEmpty) return;
    setState(() {
      _fileTreeTranslating = true;
      _fileTreeShowTranslation = true;
    });
    // 收集键与显示键严格一致（音频行显示去扩展名——此前批量翻译用
    // 完整名作键导致查询永远 miss，实机反馈 2026-09-02「拿到数据
    // 不显示」根因）。
    final names = <String>[];
    void collect(List<OnlineFileNode> nodes) {
      for (final n in nodes) {
        if (n.isFolder) {
          names.add(n.title);
        } else if (n.isAudio) {
          names.add(_stripExtension(n.title));
        } else {
          names.add(n.title);
        }
        if (n.children.isNotEmpty) collect(n.children);
      }
    }

    collect(_tracks!);
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

  /// 文件树行显示名（译文优先；仅非中文条目会有译文）。
  String _fileTreeDisplayName(String original) =>
      _fileTreeShowTranslation &&
              _fileTreeTranslations.containsKey(original)
          ? _fileTreeTranslations[original]!
          : original;

  Future<void> _translateTitle() async {
    if (_translating) return;
    setState(() => _translating = true);
    final result = await TranslationService.translate(widget.work.title);
    if (mounted) {
      setState(() {
        _titleTranslation = result;
        _translating = false;
      });
    }
  }
  bool _loading = true;
  bool _tracksLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  /// DLsite 外链：展示可复制链接（避免引入 url_launcher 依赖）。
  void launchDlsite(BuildContext context, int workId) {
    final url =
        'https://www.dlsite.com/maniax/work/=/product_id/RJ${workId.toString().padLeft(6, '0')}.html';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('DLsite 作品页'),
        content: SelectableText(url),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭')),
        ],
      ),
    );
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
      if (mounted) {
        setState(() {
          _tracks = tracks;
          _subtitleCount = _countByExt(tracks, const {'.srt', '.vtt'});
          _lyricCount = _countByExt(tracks, const {'.lrc'});
        });
      }
    } catch (_) {
      if (mounted) setState(() => _tracks = const []);
    } finally {
      if (mounted) setState(() => _tracksLoading = false);
    }
  }

  int _countByExt(List<OnlineFileNode> nodes, Set<String> exts) {
    var count = 0;
    void walk(List<OnlineFileNode> list) {
      for (final n in list) {
        if (n.isFolder) {
          walk(n.children);
        } else if (n.title.contains('.') &&
            exts.contains(
                n.title.substring(n.title.lastIndexOf('.')).toLowerCase())) {
          count++;
        }
      }
    }

    walk(nodes);
    return count;
  }

  /// 流媒体播放：整作品队列（与本地播放共用内核，PRD §5.12）。
  /// 音轨自动匹配在线字幕（KikoFlu SubtitleMatcher 规则：字幕名去字幕
  /// 扩展 + 音频扩展后与音频基础名相同即命中）。
  Future<void> _playFrom(int startIndex) async {
    final mirror = context.read<MirrorProvider>();
    final audio = context.read<AudioPlayerProvider>();
    final detail = _detail;
    if (detail == null || _tracks == null) return;

    final audioNodes = _OnlineFileTree.flatten(_tracks!);
    final subtitleNodes =
        _flattenByExts(_tracks!, const {'.vtt', '.srt', '.lrc'});

    // 本地库按 RJ 号回填（用户约定：在线播放优先用本地已有的歌词/字幕）。
    final localNodes = await _localNodesForRj(detail.rjCode);

    final tracks = <AudioTrack>[];
    for (final node in audioNodes) {
      try {
        final subtitle = _matchSubtitle(node, subtitleNodes);
        // 本地同名音轨（基础名模糊匹配）→ 继承本地歌词/字幕。
        final localMatch = _localMatch(localNodes, node);
        final localLyricPath = localMatch?.lyricPath;
        final localSubtitlePath = localMatch?.subtitlePath;
        tracks.add(AudioTrack(
          id: 'online_${detail.id}_${node.title}',
          title: _stripExtension(node.title),
          artist: detail.title,
          source: mirror.api.nodeStreamUrl(node),
          artworkUrl: mirror.api.coverUrl(detail.id),
          lyricPath: localLyricPath,
          subtitlePath: localSubtitlePath,
          subtitleUrl: subtitle != null
              ? mirror.api.nodeStreamUrl(subtitle)
              : null,
        ));
      } catch (_) {
        continue; // 缺 hash 的节点跳过。
      }
    }
    if (tracks.isEmpty) return;
    // 单击即播：先跳转播放器，加载在后台进行（避免网络加载阻塞导航）。
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (context) => const AudioPlayerScreen()),
    );
    final index = startIndex.clamp(0, tracks.length - 1);
    unawaited(audio.playTracks(tracks, initialIndex: index));
  }

  List<OnlineFileNode> _flattenByExts(
      List<OnlineFileNode> nodes, Set<String> exts) {
    final result = <OnlineFileNode>[];
    void walk(List<OnlineFileNode> list) {
      for (final n in list) {
        if (n.isFolder) {
          walk(n.children);
        } else if (n.title.contains('.') &&
            exts.contains(
                n.title.substring(n.title.lastIndexOf('.')).toLowerCase())) {
          result.add(n);
        }
      }
    }

    walk(nodes);
    return result;
  }

  /// 字幕匹配（KikoFlu SubtitleMatcher）：'歌名.mp3.vtt' → '歌名'，
  /// 与音频 '歌名.mp3' → '歌名' 相同即命中。
  OnlineFileNode? _matchSubtitle(
      OnlineFileNode audio, List<OnlineFileNode> subtitles) {
    final audioFull = audio.title.toLowerCase();
    final audioBase = _stripAudioExt(audioFull);
    if (audioBase.isEmpty) return null;

    // 第〇层（用户强调 2026-09-01）：字幕名去掉字幕扩展后 = 音频完整名
    // （名+音频扩展）——该站字幕命名常态为「歌名.mp3.vtt」「歌名.mp3.lrc」。
    for (final subtitle in subtitles) {
      var name = subtitle.title.toLowerCase();
      for (final ext in const ['.vtt', '.srt', '.lrc']) {
        if (name.endsWith(ext)) {
          name = name.substring(0, name.length - ext.length);
          break;
        }
      }
      if (audioFull == name) return subtitle;
    }
    // 第一层：精确匹配（双层剥离后基础名比对，覆盖 歌名.vtt/歌名.lrc 等）。
    for (final subtitle in subtitles) {
      final subBase = _stripSubtitleExt(subtitle.title.toLowerCase());
      if (audioBase == subBase) return subtitle;
    }
    // 第二层：normalize 模糊匹配（空格/下划线/连字符/括号差异）。
    final audioNorm = _normalize(audioBase);
    if (audioNorm.isEmpty) return null;
    for (final subtitle in subtitles) {
      final subNorm =
          _normalize(_stripSubtitleExt(subtitle.title.toLowerCase()));
      if (audioNorm == subNorm) return subtitle;
    }
    return null;
  }

  /// 字幕名双层剥离：先去字幕扩展（.vtt/.srt/.lrc），再去音频扩展
  /// （.mp3/.wav/.flac/.m4a 等），得到内容基础名。
  String _stripSubtitleExt(String name) {
    for (final ext in const ['.vtt', '.srt', '.lrc']) {
      if (name.endsWith(ext)) {
        name = name.substring(0, name.length - ext.length);
        break;
      }
    }
    return _stripAudioExt(name);
  }

  /// 本地库同 RJ 作品的文件节点（无则空列表）。
  Future<List<FileNode>> _localNodesForRj(String rjCode) async {
    try {
      final library = context.read<LibraryProvider>();
      final work = library.works
          .where((w) => w.rjCode == rjCode)
          .firstOrNull;
      if (work == null) return const [];
      return await library.nodesOf(work);
    } catch (_) {
      return const [];
    }
  }

  /// 在线音轨 → 本地同名节点（基础名双层剥离 + normalize 模糊匹配）。
  FileNode? _localMatch(List<FileNode> localNodes, OnlineFileNode online) {
    final onlineBase =
        _normalize(_stripAudioExt(_stripAudioExt(online.title.toLowerCase())));
    for (final node in localNodes) {
      if (node.isDirectory) continue;
      final localBase = _normalize(
          _stripAudioExt(node.displayName.toLowerCase()));
      if (onlineBase.isNotEmpty && onlineBase == localBase) return node;
    }
    return null;
  }

  /// 归一化模糊匹配（KikoFlu normalizeForMatching：去空格/标点差异）。
  String _normalize(String name) =>
      name.replaceAll(RegExp(r'[\s_\-\.\[\]\(\)（）\s]+'), '');

  String _stripAudioExt(String name) {
    for (final ext in const [
      '.mp3', '.wav', '.flac', '.m4a', '.aac', '.ogg', '.opus', '.wma',
      '.mp4', '.m4b',
    ]) {
      if (name.endsWith(ext)) {
        return name.substring(0, name.length - ext.length);
      }
    }
    return name;
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
        : online.flattenDownloadable(_tracks!);
    downloads.service.enqueueWork(detail, nodes,
        (node) => mirror.api.nodeDownloadUrl(node));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已加入下载队列：${detail.rjCode}（${nodes.length} 个文件），到「我的 → 下载管理」查看进度'),
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
          // 书签（服务端收藏，M12 用户清单 #1）。
          IconButton(
            icon: Icon(online.favoriteIds.contains(work.id)
                ? Icons.bookmark
                : Icons.bookmark_border_outlined),
            tooltip: online.favoriteIds.contains(work.id) ? '移除书签' : '加入书签',
            onPressed: () => online.toggleFavorite(work.id),
          ),
          // 外部链接（DLsite 作品页，#7）。
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'DLsite 作品页',
            onPressed: () => launchDlsite(context, work.id),
          ),
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
                    // 沉浸式封面：宽至屏宽-32，4:3 实测比例零裁切。
                    Center(
                      child: LayoutBuilder(
                        builder: (context, constraints) => SizedBox(
                          width: constraints.maxWidth.clamp(0, 480),
                          child: AspectRatio(
                            aspectRatio: 4 / 3,
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
                      ),
                    ),
                    const SizedBox(height: UiSpacing.large),
                    // 标题 + 免费翻译按钮（无官方译名时；实机需求 2026-09-02）。
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            work.title,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                            maxLines: null,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                        if (!TranslationService.isMostlyChinese(work.title))
                          _TitleTranslateButton(
                            translating: _translating,
                            translated: _titleTranslation != null,
                            onPressed: _translateTitle,
                          ),
                      ],
                    ),
                    if (work.titleTranslation != null &&
                        work.titleTranslation!.isNotEmpty) ...[
                      const SizedBox(height: UiSpacing.xSmall),
                      Text(
                        work.titleTranslation!,
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                    ] else if (_titleTranslation != null) ...[
                      const SizedBox(height: UiSpacing.xSmall),
                      Text(
                        _titleTranslation!,
                        style: TextStyle(
                            fontSize: 14, color: scheme.primary),
                      ),
                    ],
                    const SizedBox(height: UiSpacing.small),
                    // 社团名可点 → 该社团全部作品（用户需求 2026-09-02）。
                    _InfoLine(
                        icon: Icons.group_outlined,
                        text: work.circleName ?? '未知社团',
                        onTap: work.circleId != null
                            ? () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => Scaffold(
                                      appBar: AppBar(
                                          title: Text(
                                              work.circleName ?? '社团作品')),
                                      body: OnlineWorksScreen(
                                        circleId: work.circleId,
                                        circleTitle: work.circleName,
                                      ),
                                    ),
                                  ),
                                )
                            : null),
                    if (work.vas.isNotEmpty)
                      _InfoLine(
                          icon: Icons.mic_outlined,
                          text: 'CV：${work.vas.join(' / ')}'),
                    _InfoLine(
                        icon: Icons.star_outline,
                        text: '★${work.averageRating?.toStringAsFixed(1) ?? '-'}'
                            '（${work.ratingCount ?? 0} 评价 · ${work.dlCount ?? 0} 销量'
                            '${work.reviewCount != null && work.reviewCount! > 0 ? ' · ${work.reviewCount} 评论' : ''}）'),
                    if (work.release != null)
                      _InfoLine(
                          icon: Icons.calendar_today_outlined,
                          text:
                              '发行：${work.release!.year}-${work.release!.month.toString().padLeft(2, '0')}-${work.release!.day.toString().padLeft(2, '0')}'),
                    if (_subtitleCount > 0)
                      _InfoLine(
                          icon: Icons.subtitles_outlined,
                          text: '含字幕（$_subtitleCount 个字幕文件）'),
                    if (_lyricCount > 0)
                      _InfoLine(
                          icon: Icons.lyrics_outlined, text: '含歌词'),
                    if (work.tags.isNotEmpty) ...[
                      const SizedBox(height: UiSpacing.medium),
                      Wrap(
                        spacing: UiSpacing.xSmall,
                        runSpacing: UiSpacing.xSmall,
                        children: [
                          for (final tag in work.tags.take(12))
                            ActionChip(
                              label: Text(tag,
                                  style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              // 点标签 → asmr.one 标签搜索（用户需求）。
                              onPressed: () =>
                                  Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (context) =>
                                      TagFilterScreen(tag: tag, online: true),
                                ),
                              ),
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
                    // 评论区（默认收起；实机需求 2026-09-02）。
                    CommentSection(workId: work.id),
                    const SizedBox(height: UiSpacing.small),
                    // 文件树（流播入口）+ 文件名翻译切换（kikoflu 同款）。
                    Row(
                      children: [
                        Expanded(
                          child: Text('音轨',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w500)),
                        ),
                        TranslationToggleButton(
                          isTranslated: _fileTreeTranslationVisible,
                          isLoading: _fileTreeTranslating,
                          progress: _fileTreeProgress,
                          onPressed: _toggleFileTreeTranslation,
                        ),
                      ],
                    ),
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
                        displayName: _fileTreeDisplayName,
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
  const _InfoLine({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: UiSpacing.xSmall),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(UiRadii.list),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: UiIconSize.standard,
                color: onTap != null
                    ? scheme.primary
                    : scheme.onSurfaceVariant),
            const SizedBox(width: UiSpacing.small),
            Expanded(
              child: Text(
                text,
                style: UiTextStyles.supporting.copyWith(
                    color: onTap != null
                        ? scheme.primary
                        : scheme.onSurfaceVariant),
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right,
                  size: UiIconSize.standard, color: scheme.primary),
          ],
        ),
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
    this.displayName,
  });

  final List<OnlineFileNode> nodes;
  final void Function(int trackIndex) onTrackTap;

  /// 嵌套深度（缩进用）。
  final int depth;

  /// 整棵树扁平化后的音轨列表（根实例计算，逐层透传；序号与播放队列一致）。
  final List<OnlineFileNode> flatAudioNodes;

  /// 文件名显示函数（外层注入译文切换逻辑；null = 原文）。
  final String Function(String original)? displayName;

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
    // 目录默认收起（与本地文件树一致，用户约定）。
  }

  /// 可预览的字幕/歌词扩展名。
  static bool _isPreviewable(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.srt') ||
        lower.endsWith('.vtt') ||
        lower.endsWith('.lrc');
  }

  /// 在线字幕预览：拉取文件文本后进预览页。
  Future<void> _previewSubtitle(BuildContext context, node) async {
    final mirror = context.read<MirrorProvider>();
    final url = mirror.api.nodeStreamUrl(node);
    try {
      final response = await Dio().get<String>(url,
          options: Options(responseType: ResponseType.plain));
      if (!context.mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SubtitlePreviewScreen(
          source: SubtitlePreviewSource(
            title: node.title,
            textContent: response.data,
          ),
        ),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('字幕加载失败：$e')));
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
              title: Text(
                  widget.displayName?.call(node.title) ?? node.title,
                  maxLines: null,
                  style: const TextStyle(fontSize: 20)),
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
                displayName: widget.displayName,
              ),
          ] else
            // 全部文件类型都显示；非音频保留完整文件名 + 类型徽章（用户反馈：
            // 「歌名.mp3.vtt」截成「歌名.mp3」会被误认为音频）。
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.only(left: 16 + indent, right: 16),
              leading: _fileIcon(context, node),
              title: Text(
                node.isAudio
                    ? (widget.displayName?.call(_stripExt(node.title)) ??
                        _stripExt(node.title))
                    : (widget.displayName?.call(node.title) ?? node.title),
                maxLines: null,
                style: const TextStyle(fontSize: 20),
              ),
              trailing: node.isAudio
                  ? const Icon(Icons.play_circle_outline)
                  : _typeBadge(context, node),
              onTap: node.isAudio
                  ? () => widget.onTrackTap(
                      widget.flatAudioNodes.indexOf(node))
                  : _isPreviewable(node.title)
                      ? () => _previewSubtitle(context, node)
                      : null,
            ),
      ],
    );
  }

  String _stripExt(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// 非音频文件类型徽章（颜色区分，用户建议）。
  Widget _typeBadge(BuildContext context, OnlineFileNode node) {
    final scheme = Theme.of(context).colorScheme;
    final ext = node.title.contains('.')
        ? node.title.substring(node.title.lastIndexOf('.')).toLowerCase()
        : '';
    final (label, color) = switch (ext) {
      '.srt' || '.vtt' => ('字幕', scheme.tertiary),
      '.lrc' => ('歌词', scheme.tertiary),
      '.txt' => ('文本', scheme.onSurfaceVariant),
      '.mp4' || '.mkv' || '.avi' || '.webm' => ('视频', scheme.onSurfaceVariant),
      '.jpg' || '.png' || '.gif' || '.webp' => ('图片', scheme.onSurfaceVariant),
      _ => (ext.replaceFirst('.', ''), scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(UiRadii.tag),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }

  Widget _fileIcon(BuildContext context, OnlineFileNode node) {
    final scheme = Theme.of(context).colorScheme;
    final ext = node.title.contains('.')
        ? node.title.substring(node.title.lastIndexOf('.')).toLowerCase()
        : '';
    final (icon, color) = switch (ext) {
      '.mp3' || '.m4a' || '.flac' || '.wav' || '.ogg' || '.opus' =>
        (Icons.music_note_outlined, scheme.primary),
      '.srt' || '.vtt' => (Icons.subtitles_outlined, scheme.tertiary),
      '.lrc' => (Icons.lyrics_outlined, scheme.tertiary),
      '.mp4' || '.mkv' || '.avi' || '.webm' =>
        (Icons.movie_outlined, scheme.onSurfaceVariant),
      '.jpg' || '.png' || '.gif' || '.webp' =>
        (Icons.image_outlined, scheme.onSurfaceVariant),
      '.pdf' => (Icons.picture_as_pdf_outlined, scheme.onSurfaceVariant),
      _ => (Icons.insert_drive_file_outlined, scheme.onSurfaceVariant),
    };
    return Icon(icon, size: UiIconSize.large, color: color);
  }
}


/// 标题翻译小按钮（在线详情页）。
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
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: scheme.primary),
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
