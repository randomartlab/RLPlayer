/// DLsite/asmr.one 评论区（详情页「评论」标题行 → 底部抽屉全列表）。
///
/// 2026-09-02 用户需求：评论多时不要撑长主页面——评论区改为
/// DraggableScrollableSheet 底部抽屉（上拉展开/下拉收起），主页面
/// 相关推荐等内容不再被长评论列表挤到很远。评论可单条翻译为中文
/// （译/原切换，抽屉内独立滚动，不影响主页布局）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/mirror_provider.dart';
import '../services/net_meta_service.dart';
import '../services/translation_service.dart';
import '../utils/ui_tokens.dart';

class CommentSection extends StatefulWidget {
  const CommentSection({super.key, required this.workId, this.rjCode});

  /// asmr.one 作品数字 id（RJ 号数字部分）。
  final int workId;

  /// DLsite RJ 号（本地/在线 sourceId；DLsite 评论直抓用）。
  final String? rjCode;

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  List<Map<String, dynamic>>? _cached;
  String? _status; // 空态/错误描述。

  /// 拉取评论（asmr.one → DLsite；结果缓存到打开抽屉）。
  Future<List<Map<String, dynamic>>?> _fetch() async {
    try {
      final mirror = context.read<MirrorProvider>();
      final reviews = await mirror.fetchWorkReviews(widget.workId);
      if (reviews != null && reviews.isNotEmpty) return reviews;
      final rj = widget.rjCode;
      if (rj != null && rj.isNotEmpty) {
        final meta = context.read<NetMetaService>();
        final dlsite = await meta.fetchDlsiteReviews(rj);
        if (dlsite.isNotEmpty) {
          return [
            for (final r in dlsite)
              <String, dynamic>{
                'name': r.name,
                'rating': r.rating,
                'comment': r.comment,
                'date': r.date,
                'title': r.title,
                'source': 'DLsite',
              },
          ];
        }
        final diag = NetMetaService.lastReviewDiag;
        _status = 'DLsite 未抓到评论（诊断: $diag）';
        return const [];
      }
      _status = '暂无评论';
      return const [];
    } catch (e) {
      _status = '加载失败：$e';
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = _cached?.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行：点击打开抽屉。
        InkWell(
          onTap: () => _openSheet(),
          borderRadius: BorderRadius.circular(UiRadii.list),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: UiSpacing.small),
            child: Row(
              children: [
                Icon(Icons.reviews_outlined,
                    size: 18, color: scheme.primary),
                const SizedBox(width: UiSpacing.small),
                Text('评论',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w500, fontSize: 18)),
                if (count != null) ...[
                  const SizedBox(width: UiSpacing.xSmall),
                  Text('$count',
                      style: TextStyle(
                          fontSize: 13, color: scheme.primary)),
                ],
                const Spacer(),
                Icon(Icons.unfold_more, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        // 已加载摘要（首条评论预览，帮助用户判断是否要看）。
        if (_cached != null && _cached!.isNotEmpty)
          Padding(
            padding:
                const EdgeInsets.only(left: 2, bottom: UiSpacing.small),
            child: Text(
              '${_cached!.first['name'] ?? ''}'
              '${(_cached!.first['rating'] as int?) != null ? ' ★${_cached!.first['rating']}' : ''}'
              '：${(_cached!.first['comment'] as String? ?? '').replaceAll('\n', ' ')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ),
        if (_status != null && (_cached == null || _cached!.isEmpty))
          Padding(
            padding:
                const EdgeInsets.only(left: 2, bottom: UiSpacing.small),
            child: Text('$_status · 点击重试',
                style:
                    TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ),
      ],
    );
  }

  Future<void> _openSheet() async {
    final data = _cached ?? await _fetch();
    if (!mounted) return;
    setState(() {
      _cached = data;
      _status = _status;
    });
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (context, scrollController) => _CommentSheetBody(
          reviews: _cached ?? const [],
          status: _status,
          scrollController: scrollController,
        ),
      ),
    );
    // 抽屉关闭后若有摘要变化刷新标题行计数。
    if (mounted) setState(() {});
  }
}

/// 抽屉内的完整评论列表（内部滚动 + 每条译/原切换）。
class _CommentSheetBody extends StatefulWidget {
  const _CommentSheetBody({
    required this.reviews,
    required this.status,
    required this.scrollController,
  });

  final List<Map<String, dynamic>> reviews;
  final String? status;
  final ScrollController scrollController;

  @override
  State<_CommentSheetBody> createState() => _CommentSheetBodyState();
}

class _CommentSheetBodyState extends State<_CommentSheetBody> {
  final Map<String, String> _translations = {};

  Future<void> _translate(Map<String, dynamic> review) async {
    final key = '${review['date'] ?? ''}_${(review['comment'] as String?)?.length}';
    final comment = (review['comment'] as String?) ?? '';
    if (comment.isEmpty || _translations.containsKey(key)) return;
    final result = await TranslationService.translate(comment);
    if (mounted && result != null) {
      setState(() => _translations[key] = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              UiSpacing.large, 0, UiSpacing.large, UiSpacing.small),
          child: Row(
            children: [
              Text('评论（${widget.reviews.length}）',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                tooltip: '收起',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.reviews.isEmpty
              ? Center(
                  child: Text(widget.status ?? '暂无评论',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 13)),
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: UiSpacing.large, vertical: UiSpacing.small),
                  itemCount: widget.reviews.length,
                  itemBuilder: (context, index) {
                    final review = widget.reviews[index];
                    final key =
                        '${review['date'] ?? ''}_${(review['comment'] as String?)?.length}';
                    final translated = _translations[key];
                    return _SheetReviewTile(
                      review: review,
                      translated: translated,
                      onTranslate: () => _translate(review),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SheetReviewTile extends StatelessWidget {
  const _SheetReviewTile(
      {required this.review, this.translated, required this.onTranslate});

  final Map<String, dynamic> review;
  final String? translated;
  final VoidCallback onTranslate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rating = (review['rating'] as num?)?.toInt();
    final name = (review['name'] as String?) ?? '匿名';
    final comment = (review['comment'] as String?) ?? '';
    final title = (review['title'] as String?) ?? '';
    final date = (review['date'] as String?) ?? '';
    final source = (review['source'] as String?) ?? '';
    final isChinese = TranslationService.isMostlyChinese(comment);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(UiRadii.list),
        border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    if (rating != null) ...[
                      const SizedBox(width: UiSpacing.xSmall),
                      Text('★$rating',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade700,
                              fontWeight: FontWeight.w600)),
                    ],
                    if (source.isNotEmpty) ...[
                      const SizedBox(width: UiSpacing.xSmall),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(source,
                            style: TextStyle(
                                fontSize: 9,
                                color: scheme.onSecondaryContainer)),
                      ),
                    ],
                  ],
                ),
              ),
              if (comment.isNotEmpty && !isChinese)
                IconButton(
                  onPressed: translated != null ? () {} : onTranslate,
                  icon: Icon(
                      translated != null
                          ? Icons.translate
                          : Icons.g_translate,
                      size: 16,
                      color: translated != null
                          ? scheme.primary
                          : scheme.onSurfaceVariant),
                  tooltip: '翻译评论',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (title.isNotEmpty)
            Text('「$title」',
                style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    height: 1.45)),
          // 原文（翻译后收起为 4 行，保留上下文）。
          if (comment.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                comment,
                style: const TextStyle(
                    fontSize: 14, height: 1.6, letterSpacing: 0.1),
                maxLines: translated != null ? 4 : null,
                overflow: translated != null
                    ? TextOverflow.ellipsis
                    : TextOverflow.visible,
              ),
            ),
          // 译文块：独立底色卡片样式，突出显示。
          if (translated != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(UiRadii.control),
              ),
              child: Text(
                translated!,
                style: const TextStyle(
                    fontSize: 14, height: 1.65, letterSpacing: 0.1),
                maxLines: null,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              if (date.isNotEmpty)
                Text(date,
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              const Spacer(),
              if (translated != null)
                Text('译文',
                    style: TextStyle(
                        fontSize: 11,
                        color: scheme.tertiary,
                        fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}
