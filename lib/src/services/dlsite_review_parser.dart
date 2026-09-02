/// DLsite 作品评论 HTML 解析（2026-09-02 实机 DOM 采样编写）。
///
/// 评论区结构（实测 sample）：
/// ```html
/// <div class="review_inner">
///   <div class="review_star"><span class="rate type_review rate50"></span></div>
///   <div class="reveiw_title"><span class="reveiw_title_item">标题</span></div>
///   <div class="reveiw_date_item">2024年08月21日</div>
///   <div class="reveiw_author_item">…<span itemprop="name">用户<a href="/maniax/reviewlist/=/reviewer/REV..">作者名</a></span></div>
///   <p itemprop="reviewBody" class="review_desc">正文</p>
/// </div>
/// ```
library;

import 'package:html/parser.dart' as htmlparser;


class DlsiteReview {
  const DlsiteReview({
    required this.name,
    required this.rating,
    required this.date,
    required this.comment,
    this.title,
  });

  final String name;
  final int? rating; // 1-5
  final String? date;
  final String comment;
  final String? title;
}

/// 解析 DLsite 作品页 HTML 中的评论区，返回评论列表（空 = 无/解析失败）。
List<DlsiteReview> parseDlsiteReviewsHtml(String html) {
  final reviews = <DlsiteReview>[];
  // review_inner 块切分（惰性：以块标记切分，块内正则取字段）。
  final parts = html.split('<div class="review_inner">');
  for (final part in parts.skip(1)) {
    final ratingMatch =
        RegExp(r'rate type_review rate(\d+)').firstMatch(part);
    final titleMatch =
        RegExp(r'reveiw_title_item[^>]*>([^<]*)<').firstMatch(part);
    final dateMatch =
        RegExp(r'reveiw_date_item[^>]*>([^<]*)<').firstMatch(part);
    // 作者名：reviewer 链接优先（作者名在 <a>…</a>），否则 author_item 内
    // 文本去掉「用户」前缀。
    String? author;
    final linkMatch = RegExp(
            r'/maniax/reviewlist/=/reviewer/REV\d+/[^>]*>([^<]+)</a>')
        .firstMatch(part);
    if (linkMatch != null) {
      author = _clean(linkMatch.group(1)!);
    } else {
      final authorMatch = RegExp(
              r'reveiw_author_item[^>]*>([\s\S]*?)</span>')
          .firstMatch(part);
      if (authorMatch != null) {
        author = _clean(authorMatch.group(1)!)
            .replaceFirst(RegExp(r'^用户'), '');
      }
    }
    // 正文：itemprop="reviewBody" 的 p。
    final bodyMatch = RegExp(
            r'itemprop="reviewBody"[^>]*>([\s\S]*?)</p>')
        .firstMatch(part);
    if (author == null && bodyMatch == null) continue;
    final body = bodyMatch != null
        ? _cleanWithBreaks(bodyMatch.group(1)!)
        : '';
    if (body.isEmpty && titleMatch == null) continue;

    final ratingRaw = ratingMatch?.group(1);
    final rating = ratingRaw != null ? (int.tryParse(ratingRaw) ?? 0) ~/ 10 : null;
    reviews.add(DlsiteReview(
      name: author ?? '',
      rating: (rating != null && rating >= 1 && rating <= 5) ? rating : null,
      date: dateMatch != null ? _clean(dateMatch.group(1)!) : null,
      comment: body,
      title: titleMatch != null ? _clean(titleMatch.group(1)!) : null,
    ));
  }
  return reviews;
}

String _clean(String s) {
  final noTags = s.replaceAll(RegExp(r'<[^>]+>'), '');
  return _decodeEntities(noTags).trim();
}

String _cleanWithBreaks(String s) {
  // <br> 转行，其余标签去除。
  final withNl = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  final noTags = withNl.replaceAll(RegExp(r'<[^>]+>'), '');
  return _decodeEntities(noTags).trim();
}

String _decodeEntities(String s) {
  // 用 html 包的实体解码（解析 fragment 取文本）。
  return htmlparser.parseFragment(s).text!;
}
