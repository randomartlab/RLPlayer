import 'dart:io';

import 'package:flutter/material.dart';

import '../models/work.dart';
import '../utils/ui_tokens.dart';

/// 作品卡片三变体（KikoFlu `enhanced_work_card.dart` 移植 + 本地化改造，
/// PRD §5.4 / UI 规范 §4.1）。
///
/// - 中卡（大网格/封面墙）：封面 AspectRatio 1.3 + 信息区；
/// - 紧凑卡（小网格）：封面 1.0 正方形 + 单行标题（§4.7 例外条款）；
/// - 全卡（列表模式）：80×80 封面 + 右侧两行信息。
///
/// 信息区字段本地优先（PRD §5.4）：标题必有；社团名有则显示；
/// 总时长 + 音轨数必有；评分/CV/标签行仅 NetMeta 已缓存时显示（M4 引入，
/// 未缓存时整行隐藏，卡片自动收拢不留空白）。
class WorkCardVariant {
  const WorkCardVariant._();

  /// 实测 asmr.one 封面 24/24 为 560×420（4:3 横版，2026-09-01 采集）。
  static const double compactCoverRatio = 4 / 3;
  static const double mediumCoverRatio = 4 / 3;
  static const double listCoverSize = 80;
}

enum WorkCardSize { compact, medium, list }

class EnhancedWorkCard extends StatelessWidget {
  const EnhancedWorkCard({
    super.key,
    required this.work,
    required this.onTap,
    this.size = WorkCardSize.medium,
    this.onLongPress,
  });

  final Work work;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final WorkCardSize size;

  @override
  Widget build(BuildContext context) {
    // 卡片宽度-字号联动（PRD §4.7）：字体缩放 ≥1.5× 时网格模式隐藏
    // 文字只留封面（紧凑卡/中卡），点入详情必见完整名称；列表模式不受影响。
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final hideText = textScale >= 1.5 && size != WorkCardSize.list;

    return switch (size) {
      WorkCardSize.compact => _CompactCard(
          work: work, onTap: onTap, hideText: hideText),
      WorkCardSize.list => _ListCard(
          work: work,
          onTap: onTap,
          onLongPress: onLongPress,
        ),
      WorkCardSize.medium => _MediumCard(
          work: work, onTap: onTap, onLongPress: onLongPress,
          hideText: hideText),
    };
  }
}

/// 封面（本地文件直读；占位 = primaryContainer 渐变 + RJ 号文字）。
class WorkCover extends StatelessWidget {
  const WorkCover({
    super.key,
    required this.work,
    this.borderRadius = 8,
    this.fit = BoxFit.cover,
  });

  final Work work;
  final double borderRadius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coverPath = work.coverPath;

    if (coverPath != null && work.coverSource != CoverSource.placeholder) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.file(
          File(coverPath),
          fit: fit,
          cacheWidth: 640,
          errorBuilder: (context, error, stackTrace) =>
              _placeholder(scheme),
        ),
      );
    }
    return _placeholder(scheme);
  }

  Widget _placeholder(ColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.secondaryContainer,
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        work.rjCode ?? work.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontSize: UiTextStyles.supporting.fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 时长角标：右下角，tag 圆角 4dp，黑色半透明背景（UI 规范 §4.1）。
class _DurationBadge extends StatelessWidget {
  const _DurationBadge({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    return Positioned(
      right: UiSpacing.xSmall,
      bottom: UiSpacing.xSmall,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(UiRadii.tag),
        ),
        child: Text(
          text!,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// RJ 号标签：左下角，tag 圆角 4dp。
class _RjBadge extends StatelessWidget {
  const _RjBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: UiSpacing.xSmall,
      bottom: UiSpacing.xSmall,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(UiRadii.tag),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            height: 1.2,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

String? _formatDuration(int? seconds) {
  if (seconds == null) return null;
  if (seconds < 3600) {
    return '${seconds ~/ 60}分钟';
  }
  return '${seconds ~/ 3600}小时${(seconds % 3600) ~/ 60}分';
}

// ---- 中卡（大网格 / 封面墙）----

class _MediumCard extends StatelessWidget {
  const _MediumCard(
      {required this.work, required this.onTap, this.onLongPress, this.hideText = false});

  final Work work;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool hideText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(UiRadii.control),
      child: Padding(
        padding: const EdgeInsets.all(UiSpacing.xSmall + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hideText)
              Expanded(child: _coverOnly(context))
            else ...[
            // 封面 AspectRatio 1.3 + Hero 转场（tag 与详情页一致）。
            Hero(
              tag: 'work_cover_${work.id}',
              child: AspectRatio(
                aspectRatio: WorkCardVariant.mediumCoverRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    WorkCover(work: work),
                    _RjBadge(text: work.rjCode ?? '本地'),
                    _DurationBadge(text: _formatDuration(work.durationSeconds)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: UiSpacing.xSmall),
            // 标题：本地值（metadata.json > 文件夹名）。
            // 完整显示（用户要求 2026-09-01：不限行数，masonry 高度自适应）。
            Text(
              work.title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
            // 社团名：本地有则显示；均无隐藏该行（不留空白）。
            if (work.circleName != null) ...[
              const SizedBox(height: 2),
              Text(
                work.circleName!,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            // CV 行（本地 metadata.json / 网络回填，用户决策 2026-09-01）。
            if (work.vasNames.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'CV：${work.vasNames.join(' / ')}',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_formatDuration(work.durationSeconds) ?? '时长未知'} · ${work.trackCount} 轨',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (work.hasSubtitle) _SubtitleBadge(scheme: scheme),
                if (work.hasLyric) _LyricBadge(scheme: scheme),
              ],
            ),
            // 评分/CV/标签行：NetMeta 未缓存整行隐藏（M4 引入）。
            ],
          ],
        ),
      ),
    );
  }

  /// 大字体缩放模式：仅封面撑满卡片。
  Widget _coverOnly(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Hero(
      tag: 'work_cover_${work.id}',
      child: Stack(
        fit: StackFit.expand,
        children: [
          WorkCover(work: work),
          Positioned(
            left: UiSpacing.xSmall,
            bottom: UiSpacing.xSmall,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(UiRadii.tag),
              ),
              child: Text(work.rjCode ?? '本地',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- 紧凑卡（小网格）----

class _CompactCard extends StatelessWidget {
  const _CompactCard({required this.work, required this.onTap, this.hideText = false});

  final Work work;
  final VoidCallback onTap;
  final bool hideText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(UiRadii.control),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: WorkCardVariant.compactCoverRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    WorkCover(work: work),
                    _RjBadge(text: work.rjCode ?? '本地'),
                  ],
                ),
              ),
            ),
            if (!hideText) ...[
              const SizedBox(height: UiSpacing.xSmall),
              // 标题 12sp 单行省略（§4.7 卡片例外条款）。
              Text(
                work.title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---- 全卡（列表模式）----

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.work,
    required this.onTap,
    this.onLongPress,
  });

  final Work work;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(UiRadii.list),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: UiSpacing.medium,
          vertical: UiSpacing.small,
        ),
        child: Row(
          children: [
            SizedBox(
              width: WorkCardVariant.listCoverSize,
              height: WorkCardVariant.listCoverSize,
              child: Hero(
                tag: 'work_cover_${work.id}',
                child: WorkCover(work: work),
              ),
            ),
            const SizedBox(width: UiSpacing.medium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题 15sp，三行省略（完整显示优先）。
                  Text(
                    work.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (work.circleName != null) work.circleName!,
                      if (work.vasNames.isNotEmpty)
                        'CV: ${work.vasNames.first}',
                      if (work.rjCode != null) work.rjCode!,
                      '${work.trackCount} 轨',
                      if (work.durationSeconds != null)
                        _formatDuration(work.durationSeconds)!,
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (work.hasSubtitle || work.hasLyric)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (work.hasSubtitle) _SubtitleBadge(scheme: scheme),
                          if (work.hasLyric) _LyricBadge(scheme: scheme),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}


/// 含字幕标签（用户反馈：是否带字幕应明确标注）。
class _SubtitleBadge extends StatelessWidget {
  const _SubtitleBadge({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(UiRadii.tag),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.subtitles_outlined,
              size: 12, color: scheme.onSecondaryContainer),
          const SizedBox(width: 3),
          Text('字幕',
              style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// 含歌词标签。
class _LyricBadge extends StatelessWidget {
  const _LyricBadge({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(UiRadii.tag),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lyrics_outlined,
              size: 12, color: scheme.onSecondaryContainer),
          const SizedBox(width: 3),
          Text('歌词',
              style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
