import 'package:flutter_test/flutter_test.dart';
import 'package:kiko_local/src/models/work.dart';
import 'package:kiko_local/src/models/search_query.dart';

void main() {
  Work work({String? rj = 'RJ123456', String title = '测试作品',
      String? circle, List<String> vas = const [],
      List<String> tags = const []}) => Work(
    id: 1, rjCode: rj, title: title, circleName: circle,
    vasNames: vas, tags: tags, addedAt: DateTime.now(),
    trackCount: 1, hasLyric: false, hasSubtitle: false,
    rootPath: '/x', coverSource: CoverSource.placeholder);

  test('AND：多条件全部满足', () {
    final q = SearchQuery(conditions: const [
      SearchCondition(type: SearchConditionType.va, value: '井上'),
      SearchCondition(type: SearchConditionType.tag, value: 'ASMR'),
    ]);
    expect(q.matches(work(vas: ['井上ほの花'], tags: ['ASMR'])), isTrue);
    expect(q.matches(work(vas: ['井上ほの花'], tags: ['治愈'])), isFalse);
  });

  test('OR：任一满足即可', () {
    final q = SearchQuery(
      combine: SearchCombine.or,
      conditions: const [
        SearchCondition(type: SearchConditionType.tag, value: '治愈'),
        SearchCondition(type: SearchConditionType.circle, value: 'アトリエ'),
      ],
    );
    expect(q.matches(work(tags: ['治愈'])), isTrue);
    expect(q.matches(work(circle: 'アトリエメール')), isTrue);
    expect(q.matches(work(tags: ['ASMR'])), isFalse);
  });

  test('排除：命中即剔除（后置硬过滤）', () {
    final q = SearchQuery(conditions: const [
      SearchCondition(type: SearchConditionType.keyword, value: 'ASMR'),
      SearchCondition(type: SearchConditionType.tag, value: 'NTR', exclude: true),
    ]);
    expect(q.matches(work(title: 'ASMR 作品', tags: ['治愈'])), isTrue);
    expect(q.matches(work(title: 'ASMR 作品', tags: ['NTR'])), isFalse);
  });

  test('RJ 数字自动补前缀匹配', () {
    final q = SearchQuery(conditions: const [
      SearchCondition(type: SearchConditionType.rj, value: '416816'),
    ]);
    expect(q.matches(work(rj: 'RJ416816')), isTrue);
    expect(q.matches(work(rj: 'RJ111111')), isFalse);
  });
}
