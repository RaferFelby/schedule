import 'package:celechron/manual/migration/practice_converter.dart';
import 'package:celechron/manual/model/practice_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const converter = LegacyPracticeConverter();

  test('converts explicit detail and retains fields in sidecar', () {
    final result = converter.convert(_scholar(items: [_item()]));

    expect(result.records, hasLength(1));
    final record = result.records.single;
    expect(record.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(record.category, '第二课堂');
    expect(record.projectName, '志愿服务');
    expect(record.date, DateTime(2025, 3, 2));
    expect(record.points, 2.5);
    expect(record.status, PracticeReviewStatus.approved);
    expect(record.note, '社区服务');
    expect(result.recordMetadata.single.categoryId, 1);
    expect(result.recordMetadata.single.projectType, '志愿活动');
    expect(result.recordMetadata.single.role, '组织者');
    expect(result.unresolvedRecords, isEmpty);
  });

  test(
      'same projection has stable record ID and duplicate source is not accumulated',
      () {
    final item = _item();
    final result = converter.convert(_scholar(items: [item, item]));

    expect(result.records, hasLength(1));
    expect(
      converter.convert(_scholar(items: [item])).records.single.id,
      result.records.single.id,
    );
  });

  test('summary only preserves totals without inventing practice records', () {
    final result = converter.convert(_scholar(
      items: null,
      summarySource: 'networkMyInfo',
    ));

    expect(result.records, isEmpty);
    expect(
        result.historicalSummary!.pointsByCategory, {1: 1.0, 2: 0.0, 3: 4.25});
    expect(result.historicalSummary!.scope, contains('全局'));
    expect(result.reviewItems, contains(contains('没有足够项目资料')));
  });

  test('derived summary stays separate from detail total', () {
    final result = converter.convert(_scholar(
      items: [_item()],
      summarySource: 'calculatedFromSqjl',
    ));

    expect(result.records, hasLength(1));
    expect(result.historicalSummary!.derivedFromDetails, isTrue);
    expect(result.historicalSummary!.pointsByCategory[1], 2.5);
    expect(result.reviewItems, contains(contains('不重复导入为额外记录')));
  });

  test(
      'default totals without summary source do not fabricate a historical summary',
      () {
    final result = converter.convert(_scholar(items: null));

    expect(result.historicalSummary, isNull);
  });

  test('missing activity date remains unresolved instead of using update time',
      () {
    final result = converter.convert(_scholar(items: [
      _item()..remove('activityStart'),
    ]));

    expect(result.records, isEmpty);
    expect(result.unresolvedRecords.single['reason'], '缺少明确活动开始日期');
  });
}

Map<String, Object?> _scholar({
  required List<Map<String, Object?>>? items,
  String? summarySource,
}) =>
    {
      if (items != null) 'practiceScoreItems': items,
      'practiceSummarySource': summarySource ?? 'unavailable',
      'isPracticeScoresGet': summarySource != null,
      'pt2': 1.0,
      'pt3': 0.0,
      'pt4': 4.25,
      if (summarySource == 'calculatedFromSqjl') ...{
        'pt2': 2.5,
        'pt3': 0.0,
        'pt4': 0.0,
      },
    };

Map<String, Object?> _item() => {
      'id': 17,
      'categoryId': 1,
      'categoryName': '第二课堂',
      'projectName': '志愿服务',
      'projectType': '志愿活动',
      'qualityType': '实践育人',
      'score': 2.5,
      'approved': true,
      'deleted': false,
      'remark': '社区服务',
      'role': '组织者',
      'statusValue': 1,
      'statusLabel': '已通过',
      'activityStart': '2025-03-02T09:00:00',
      'activityEnd': '2025-03-02T11:00:00',
      'updatedAt': '2025-03-04T10:00:00',
    };
