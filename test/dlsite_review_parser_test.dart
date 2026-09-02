import 'package:flutter_test/flutter_test.dart';
import 'package:kiko_local/src/services/dlsite_review_parser.dart';

void main() {
  const sample = '''
  <div id="review_list">
    <div class="review_inner"><div class="review_contents" itemprop="review">
      <div class="review_star"><span class="rate type_review rate50"></span></div>
      <div class="reveiw_title"><span itemprop="name" class="reveiw_title_item">好好好</span></div>
      <div class="reveiw_date_item">2024年08月21日</div>
      <div class="reveiw_author_item"><span itemprop="name">用户<a href="/maniax/reviewlist/=/reviewer/REV0159876/">被羊娘可爱死了</a></span></div>
      <div class="review_main review_contents_inner">
        <div style="display: none;"><div class="review_attention"><p class="review_attention_item"><a href="#">警告，此赏析内容涉及剧透！</a></p></div></div>
        <div><p itemprop="reviewBody" class="review_desc">第一句<br>第二句&amp;测试</p></div>
      </div>
    </div></div>
    <div class="review_inner"><div class="review_contents" itemprop="review">
      <div class="review_star"><span class="rate type_review rate40"></span></div>
      <div class="reveiw_title_item">也不错</div>
      <div class="reveiw_date_item">2023年01月01日</div>
      <div class="reveiw_author_item"><span itemprop="name">匿名用户</span></div>
      <p itemprop="reviewBody" class="review_desc">第二条评论</p>
    </div></div>
  </div>
  ''';

  test('解析 DLsite 评论 DOM', () {
    final reviews = parseDlsiteReviewsHtml(sample);
    expect(reviews.length, 2);
    expect(reviews[0].rating, 5);
    expect(reviews[0].name, '被羊娘可爱死了');
    expect(reviews[0].title, '好好好');
    expect(reviews[0].date, '2024年08月21日');
    expect(reviews[0].comment, contains('第一句'));
    expect(reviews[0].comment, contains('第二句&测试'));
    expect(reviews[1].rating, 4);
    expect(reviews[1].name, '匿名用户');
    expect(reviews[1].comment, '第二条评论');
  });
}
