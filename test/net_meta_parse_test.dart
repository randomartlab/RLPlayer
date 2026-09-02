import 'package:flutter_test/flutter_test.dart';
import 'package:kiko_local/src/models/net_meta.dart';
import 'package:kiko_local/src/services/translation_service.dart';

void main() {
  test('NetMeta.fromJson 解析 asmr.one snake_case 字段', () {
    final meta = NetMeta.fromJson(416816, {
      'title': 'テスト作品',
      'circle': {'id': 123, 'name': 'サークル'},
      'release': '2022-09-11',
      'rate_average_2dp': 4.86,
      'rate_count': 152,
      'dl_count': 3210,
      'review_count': 12,
    });
    expect(meta.netRateAverage, 4.86);
    expect(meta.netRateCount, 152);
    expect(meta.netDlCount, 3210);
    expect(meta.netReviewCount, 12);
    expect(meta.netCircle, 'サークル');
  });

  test('翻译服务：中文文本不翻译', () {
    expect(TranslationService.isMostlyChinese('这是一个中文标题'), isTrue);
    expect(TranslationService.isMostlyChinese('日本語のタイトル'), isFalse);
    expect(TranslationService.isMostlyChinese('English Title'), isFalse);
  });
}
