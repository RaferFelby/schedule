import 'package:celechron/manual/migration/grade_converter.dart';
import 'package:celechron/manual/migration/grade_preference_converter.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/retake_selection_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const converter = LegacyGradePreferenceConverter();

  test('maps explicit Grade.id selection, weight, and strategy consistently',
      () {
    final courses = [_course('a'), _course('b')];
    final mappings = [
      _gradeMapping(
          'source-grade-a', courses[0], '30000000-0000-4000-8000-000000000001'),
    ];
    final result = converter.convert(
      courses: courses,
      gradeIdMappings: mappings,
      legacyOptions: {'gpaStrategy': 1},
      legacyCustomGpa: {
        'selectList': {'source-grade-a': false},
        'weightedGpa': {'source-grade-a': 0.5},
      },
    );
    final repeated = converter.convert(
      courses: courses,
      gradeIdMappings: mappings,
      legacyOptions: {'gpaStrategy': 1},
      legacyCustomGpa: {
        'selectList': {'source-grade-a': false},
        'weightedGpa': {'source-grade-a': 0.5},
      },
    );

    expect(result.courses[0].selectedForGpa, isFalse);
    expect(result.courses[0].gpaWeight, 0.5);
    expect(result.courses[1].selectedForGpa, isTrue);
    expect(result.courses[1].gpaWeight, 1.0);
    expect(
        result.courses.every((course) =>
            course.retakeStrategy == RetakeSelectionStrategy.firstAttempt),
        isTrue);
    expect(
      result.courses.map((course) => course.toJson()).toList(),
      repeated.courses.map((course) => course.toJson()).toList(),
    );
    expect(result.unresolvedPreferences, isEmpty);
  });

  test('leaves a course unchanged when its old grade preferences conflict', () {
    final course = _course('a');
    final result = converter.convert(
      courses: [course],
      gradeIdMappings: [
        _gradeMapping(
            'grade-a', course, '30000000-0000-4000-8000-000000000001'),
        _gradeMapping(
            'grade-b', course, '30000000-0000-4000-8000-000000000002'),
      ],
      legacyOptions: {},
      legacyCustomGpa: {
        'selectList': {'grade-a': false, 'grade-b': true},
        'weightedGpa': {'grade-a': 0.5, 'grade-b': 0.75},
      },
    );

    expect(result.courses.single.selectedForGpa, isTrue);
    expect(result.courses.single.gpaWeight, 1.0);
    expect(result.reviewItems, contains(contains('自选状态冲突')));
    expect(result.reviewItems, contains(contains('权重冲突')));
  });

  test('reports orphan, invalid, and ambiguous Grade.id preferences', () {
    final course = _course('a');
    final result = converter.convert(
      courses: [course],
      gradeIdMappings: [
        _gradeMapping(
            'duplicate-id', course, '30000000-0000-4000-8000-000000000001'),
        _gradeMapping(
            'duplicate-id', course, '30000000-0000-4000-8000-000000000002'),
      ],
      legacyOptions: {'gpaStrategy': 99},
      legacyCustomGpa: {
        'selectList': {
          'duplicate-id': false,
          'missing-id': true,
          'bad-value': 'yes',
        },
        'weightedGpa': {'negative': -1},
      },
    );

    expect(result.courses.single.selectedForGpa, isTrue);
    expect(result.courses.single.retakeStrategy,
        RetakeSelectionStrategy.highestGpa);
    expect(result.unresolvedPreferences.length, 5);
  });

  test('decodes only string keys from copied legacy custom GPA values', () {
    final decoded = decodeLegacyCustomGpaProjection({
      'selectList': {'grade-a': true},
      'weightedGpa': {'grade-a': 0.5},
      123: 'ignored non-string key',
    });

    expect(decoded['selectList'], {'grade-a': true});
    expect(decoded['weightedGpa'], {'grade-a': 0.5});
    expect(decoded.containsKey('123'), isFalse);
    expect(legacyGradePreferenceKey(2, 'source-grade'), '[2,"source-grade"]');
  });
}

LocalCourse _course(String idSuffix) => LocalCourse(
      id: '20000000-0000-4000-8000-00000000000$idSuffix',
      semesterId: '10000000-0000-4000-8000-000000000001',
      name: '课程 $idSuffix',
      credits: 3,
    );

LegacyGradeIdMapping _gradeMapping(
  String legacyId,
  LocalCourse course,
  String newGradeId,
) =>
    LegacyGradeIdMapping(
      semesterIndex: 0,
      legacyGradeId: legacyId,
      courseId: course.id,
      gradeId: newGradeId,
    );
