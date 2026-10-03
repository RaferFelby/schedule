import 'package:celechron/manual/migration/course_converter.dart';
import 'package:celechron/manual/migration/grade_converter.dart';
import 'package:celechron/manual/migration/semester_converter.dart';
import 'package:celechron/manual/model/grade_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps numeric zero distinct from an explicitly pending grade', () {
    final zero = _grade('0', fivePoint: 0.0);
    final pending = _grade('待录', fivePoint: 0.0)
      ..['gpaIncluded'] = false
      ..['creditIncluded'] = false;
    final scholar = _scholar(
      grades: [zero, pending],
      overallGrades: [zero, pending],
    );
    final result = _convert(scholar);

    expect(result.grades, hasLength(2));
    expect(result.grades[0].status, LocalGradeStatus.recorded);
    expect(result.grades[0].rawScore, 0);
    expect(result.grades[0].gradePoint, 0);
    expect(result.grades[1].status, LocalGradeStatus.notRecorded);
    expect(result.grades[1].rawScore, isNull);
    expect(result.grades[1].gradeLabel, isNull);
    expect(result.grades[1].countsTowardGpa, isFalse);
    expect(result.grades[1].countsTowardCredits, isFalse);
    expect(result.grades.map((grade) => grade.id).toSet(), hasLength(2));
    expect(result.gradeIdMappings, hasLength(2));
    expect(
      result.gradeIdMappings.first.legacyGradeId,
      'legacy-course-a',
    );
    expect(result.reviewItems, contains(contains('未保存逐科主修标记')));
  });

  test('preserves letter/pass-fail values and explicit calculation flags', () {
    final letter = _grade('A-', fivePoint: 4.2)..['major'] = true;
    final pass = _grade('合格', fivePoint: 0.0)
      ..['gpaIncluded'] = false
      ..['major'] = false;
    final scholar = _scholar(grades: [letter, pass]);
    final result = _convert(scholar);

    expect(result.grades, hasLength(2));
    expect(result.grades[0].method.name, 'letter');
    expect(result.grades[0].gradeLabel, 'A-');
    expect(result.grades[0].gradePoint, 4.2);
    expect(result.grades[0].isMajor, isTrue);
    expect(result.grades[1].method.name, 'passFail');
    expect(result.grades[1].gradeLabel, '合格');
    expect(result.grades[1].countsTowardGpa, isFalse);
    expect(result.grades[1].isMajor, isFalse);
  });

  test('does not infer a retake group from repeated course names', () {
    final grade = _grade('88', fivePoint: 3.5);
    final scholar = _scholar(
      grades: [grade],
      secondCourse: {
        'id': 'legacy-course-b',
        'name': '同名课程',
        'credit': 3.0,
      },
    );
    final result = _convert(scholar);

    expect(result.grades, hasLength(1));
    expect(
      result.reviewItems,
      contains(contains('未保存明确的重修组关系')),
    );
  });

  test('reports grades whose course ID cannot be mapped exactly', () {
    final malformedScholar = <String, Object?>{
      'semesters': [
        {
          'name': 'S',
          'startDate': '2026-09-01',
          'endDate': '2027-01-31',
          'weekOneStart': '2026-08-31',
          'courses': {
            'legacy-key': {
              'name': '课程甲',
              'credit': 3.0,
              'grade': _grade('90', fivePoint: 4.0),
            },
          },
        },
      ],
    };
    final result = _convert(malformedScholar);

    expect(result.grades, isEmpty);
    expect(result.unresolvedGrades, isNotEmpty);
    expect(result.unresolvedGrades.first['reason'], '缺少明确的旧课程 ID 映射');
  });

  test(
      'reports invalid score and missing major marker without inventing values',
      () {
    final scholar = _scholar(grades: [_grade('101', fivePoint: 5.0)]);
    final result = _convert(scholar);

    expect(result.grades, isEmpty);
    expect(result.unresolvedGrades.single['reason'], '数值成绩超出 0 至 100 范围');
  });
}

Map<String, Object?> _grade(String original, {required double fivePoint}) => {
      'id': 'legacy-course-a',
      'name': '课程甲',
      'credit': 3.0,
      'original': original,
      'fivePoint': fivePoint,
      'fourPoint': fivePoint,
      'fourPointLegacy': fivePoint,
      'hundredPoint': 0,
      'gpaIncluded': true,
      'creditIncluded': true,
    };

Map<String, Object?> _scholar({
  required List<Map<String, Object?>> grades,
  List<Map<String, Object?>>? overallGrades,
  Map<String, Object?>? secondCourse,
}) =>
    {
      'semesters': [
        {
          'name': 'S',
          'startDate': '2026-09-01',
          'endDate': '2027-01-31',
          'weekOneStart': '2026-08-31',
          'courses': {
            'legacy-course-a': {
              'id': 'legacy-course-a',
              'name': '课程甲',
              'credit': 3.0,
              if (grades.isNotEmpty) 'grade': grades.first,
            },
            if (secondCourse != null) 'legacy-course-b': secondCourse,
          },
          'grades': grades,
        },
      ],
      if (overallGrades != null) 'grades': {'course-group': overallGrades},
    };

LegacyGradeConversionResult _convert(Map<String, Object?> scholar) {
  final semesterResult = const LegacySemesterConverter().convert(scholar);
  final courseResult = const LegacyCourseConverter().convert(
    scholar: scholar,
    convertedSemesterIds:
        semesterResult.semesters.map((semester) => semester.id).toSet(),
  );
  return const LegacyGradeConverter().convert(
    scholar: scholar,
    courseMappings: courseResult.idMappings,
    courses: courseResult.courses,
  );
}
