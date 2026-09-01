import 'package:flutter/material.dart';

import '../models/work.dart';
import '../utils/ui_tokens.dart';

/// 可折叠文件树（PRD §5.5 ⑩ / UI 规范 §5.2）。
///
/// - 每级缩进 20dp，文件名 14sp，层级图标 20dp；
/// - 音轨行：名称（两行自适应换行，§4.7）+ 时长 + 已关联歌词/字幕小图标；
/// - 点击音轨 → 播放并进入全屏播放器；
/// - 目录默认收起，点按展开。
class FileTreeView extends StatefulWidget {
  const FileTreeView({
    super.key,
    required this.nodes,
    required this.onTrackTap,
  });

  /// 已排序的节点列表（目录在前）。
  final List<FileNode> nodes;

  /// 点击音轨回调（参数：节点在列表中的音轨序号 + 节点）。
  final void Function(int trackIndex, FileNode node) onTrackTap;

  @override
  State<FileTreeView> createState() => _FileTreeViewState();
}

class _FileTreeViewState extends State<FileTreeView> {
  final Set<String> _expandedDirs = <String>{};

  @override
  void initState() {
    super.initState();
    // 目录默认收起（用户约定：文件树直接可见，目录点按展开）。
  }

  /// 渲染 parentPath 下的直属节点（目录需展开才渲染子级）。
  List<FileNode> _visibleNodes() {
    final result = <FileNode>[];
    for (final node in widget.nodes) {
      if (node.isDirectory) {
        // 目录显示条件：自身父链全部展开。
        if (!_isChainExpanded(node.parentPath)) continue;
        result.add(node);
      } else {
        if (!_isChainExpanded(node.parentPath)) continue;
        result.add(node);
      }
    }
    return result;
  }

  bool _isChainExpanded(String parentPath) {
    // 历史数据兼容：parent_path '.'（M2-M5 期间扫描）等价于根。
    if (parentPath.isEmpty || parentPath == '.') return true;
    final segments = parentPath.split('/');
    var prefix = '';
    for (final segment in segments) {
      prefix = prefix.isEmpty ? segment : '$prefix/$segment';
      if (!_expandedDirs.contains(prefix)) return false;
    }
    return true;
  }

  int _depthOf(FileNode node) =>
      (node.parentPath.isEmpty || node.parentPath == '.')
          ? 0
          : node.parentPath.split('/').length;

  @override
  Widget build(BuildContext context) {
    final visible = _visibleNodes();

    var trackOrdinal = 0; // 音轨序号（跨目录连续编号）。

    return Column(
      children: [
        for (final node in visible)
          if (node.isDirectory)
            _DirectoryRow(
              node: node,
              depth: _depthOf(node),
              expanded: _expandedDirs.contains(node.relativePath),
              onToggle: () => setState(() {
                if (_expandedDirs.contains(node.relativePath)) {
                  _expandedDirs.remove(node.relativePath);
                } else {
                  _expandedDirs.add(node.relativePath);
                }
              }),
            )
          else
            _TrackRow(
              node: node,
              depth: _depthOf(node),
              ordinal: ++trackOrdinal,
              onTap: () => widget.onTrackTap(trackOrdinal - 1, node),
            ),
      ],
    );
  }
}

class _DirectoryRow extends StatelessWidget {
  const _DirectoryRow({
    required this.node,
    required this.depth,
    required this.expanded,
    required this.onToggle,
  });

  final FileNode node;
  final int depth;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(UiRadii.list),
      child: Padding(
        padding: EdgeInsets.only(
          left: UiSpacing.large + depth * 20.0,
          right: UiSpacing.medium,
          top: UiSpacing.small + 2,
          bottom: UiSpacing.small + 2,
        ),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.folder_open : Icons.folder_outlined,
              size: UiIconSize.large,
              color: scheme.primary,
            ),
            const SizedBox(width: UiSpacing.medium),
            Expanded(
              child: Text(
                node.name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500, fontSize: 20),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.node,
    required this.depth,
    required this.ordinal,
    required this.onTap,
  });

  final FileNode node;
  final int depth;
  final int ordinal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(UiRadii.list),
      child: Padding(
        padding: EdgeInsets.only(
          left: UiSpacing.large + depth * 20.0,
          right: UiSpacing.medium,
          top: UiSpacing.small,
          bottom: UiSpacing.small,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$ordinal',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: UiSpacing.medium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 文件名：两行自适应换行（§4.7 完整名称保障）。
                  Text(
                    node.displayName,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontSize: 20),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (node.durationSeconds != null)
                        Text(
                          _formatDuration(node.durationSeconds!),
                          style: TextStyle(
                              fontSize: 15, color: scheme.onSurfaceVariant),
                        ),
                      if (node.durationSeconds != null &&
                          (node.lyricPath != null || node.subtitlePath != null))
                        const SizedBox(width: UiSpacing.medium),
                      // 已关联歌词/字幕小图标（PRD §5.5 文件树）。
                      if (node.lyricPath != null)
                        Icon(
                          Icons.lyrics_outlined,
                          size: UiIconSize.small,
                          color: scheme.onSurfaceVariant,
                        ),
                      if (node.subtitlePath != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.subtitles_outlined,
                            size: UiIconSize.small,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
