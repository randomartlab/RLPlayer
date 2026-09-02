/// DLsite/asmr.one 作品评论区（详情页，默认收起，2026-09-02 用户需求）。
///
/// 数据源：asmr.one /api/review/{workId}（需登录；游客显示登录提示）。
/// 评论可单条翻译为中文（免费翻译服务）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/mirror_provider.dart';
import '../services/translation_service.dart';
import '../utils/ui_tokens.dart';

class CommentSection extends StatefulWidget {
  const CommentSection({super.key, required this.workId});

  /// asmr.one 作品数字 id（RJ 号数字部分）。
  final int workId;

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  bool _expanded = false;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _reviews = const [];
  final Map<String, String> _translations = {};

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final mirror = context.read<MirrorProvider>();
      final reviews = await mirror.api.getWorkReviews(widget.workId);
      if (!mounted) return;
      setState(() {
        _reviews = reviews ?? const [];
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _translate(Map<String, dynamic> review) async {
    final key = '${review['id'] ?? review['time']}';
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
    final mirror = context.watch<MirrorProvider>();
    final loggedIn = mirror.currentUser != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 收起态标题行（点击展开）。
        InkWell(
          onTap: () {
            setState(() => _expanded = !_expanded);
            if (_expanded && _reviews.isEmpty && _error == null) {
              _load();
            }
          },
          borderRadius: BorderRadius.circular(UiRadii.list),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: UiSpacing.small),
            child: Row(
              children: [
                Icon(Icons.reviews_outlined,
                    size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: UiSpacing.small),
                Text('评论',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w500, fontSize: 18)),
                if (_reviews.isNotEmpty) ...[
                  const SizedBox(width: UiSpacing.xSmall),
                  Text('${_reviews.length}',
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
                ],
                const Spacer(),
                Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        if (_expanded)
          _loading
              ? const Padding(
                  padding: EdgeInsets.all(UiSpacing.medium),
                  child: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))),
                )
              : !loggedIn
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: UiSpacing.small),
                      child: Text(
                        '登录后可查看评论（设置 → 服务器与账号）',
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                    )
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: UiSpacing.small),
                          child: Text('评论加载失败：$_error',
                              style: TextStyle(
                                  fontSize: 13, color: scheme.error)),
                        )
                      : _reviews.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: UiSpacing.small),
                              child: Text('暂无评论',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: scheme.onSurfaceVariant)),
                            )
                          : Column(
                              children: [
                                for (final review in _reviews.take(20))
                                  _ReviewTile(
                                    review: review,
                                    translated: _translations[
                                        '${review['id'] ?? review['time']}'],
                                    onTranslate: () => _translate(review),
                                  ),
                              ],
                            ),
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile(
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: UiSpacing.small),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500))),
                    if (rating != null) ...[
                      const SizedBox(width: UiSpacing.xSmall),
                      Text('★$rating',
                          style: TextStyle(
                              fontSize: 12,
                              color: scheme.primary,
                              fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
              if (comment.isNotEmpty &&
                  !TranslationService.isMostlyChinese(comment))
                IconButton(
                  onPressed: onTranslate,
                  icon: translated != null
                      ? Icon(Icons.g_translate,
                          size: 16, color: scheme.primary)
                      : Icon(Icons.g_translate,
                          size: 16, color: scheme.onSurfaceVariant),
                  tooltip: '翻译评论',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (comment.isNotEmpty)
            Text(
              comment,
              style: const TextStyle(fontSize: 14, height: 1.45),
              maxLines: null,
            ),
          if (translated != null) ...[
            const SizedBox(height: UiSpacing.xSmall),
            Text(
              translated!,
              style: TextStyle(
                  fontSize: 13, height: 1.45, color: scheme.primary),
              maxLines: null,
            ),
          ],
          const Divider(height: UiSpacing.small),
        ],
      ),
    );
  }
}
