import 'package:celechron/manual/migration/course_converter.dart';
import 'package:celechron/manual/migration/semester_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const semesterConverter = LegacySemesterConverter();
  const courseConverter = LegacyCourseConverter();

  test('maps same-named courses with distinct legacy IDs independently', () {
    final scholar = <String, Object?>{
      'semesters': [
        {
          'name': 'S',
          'startDate': '2026-09-01',
          'endDate': '2027-01-31',
          'weekOneStart': '2026-08-31',
          'courses': {
            'a': {
              'id': 'source-course-a',
              'name': '同名示例课',
              'credit': 2.0,
              'teacher': '教师甲',
            },
            'b': {
              'id': 'source-course-b',
              'name': '同名示例课',
              'credit': 3.0,
            },
          },
        },
      ],
    };
    final semesterId = semesterConverter.convert(scholar).semesters.single.id;
    final first = courseConverter.convert(
      scholar: scholar,
      convertedSemesterIds: {semesterId},
    );
    final repeated = courseConverter.convert(
      scholar: scholar,
      convertedSemesterIds: {semesterId},
    );

    expect(first.courses, hasLength(2));
    expect(first.courses.map((course) => course.name).toSet(), {'同名示例课'});
    expect(first.courses.map((course) => course.id).toSet(), hasLength(2));
    expect(first.courses.map((course) => course.credits).toSet(), {2.0, 3.0});
    expect(first.idMappings, hasLength(2));
    expect(first.idMappings.map((mapping) => mapping.legacyKey).toSet(),
        hasLength(2));
    expect(first.idMappings.map((mapping) => mapping.courseId).toList(),
        repeated.idMappings.map((mapping) => mapping.courseId).toList());
    expect(first.unresolvedCourses, isEmpty);
  });

  test('does not generate associations from course names when IDs are absent',
      () {
    final scholar = <String, Object?>{
      'semesters': [
        {
          'name': 'S',
          'startDate': '2026-09-01',
          'endDate': '2027-01-31',
          'weekOneStart': '2026-08-31',
          'courses': {
            'legacy-map-key': {'name': '无来源 ID 课程', 'credit': 0.0},
          },
        },
      ],
    };
    final semesterId = semesterConverter.convert(scholar).semesters.single.id;
    final result = courseConverter.convert(
      scholar: scholar,
      convertedSemesterIds: {semesterId},
    );

    expect(result.courses, isEmpty);
    expect(result.idMappings, isEmpty);
    expect(result.unresolvedCourses.single['reason'], '缺少明确的旧课程 ID');
    expect(result.unresolvedCourses.single['sourceMapKey'], 'legacy-map-key');
  });

  test('leaves courses pending when their semester was not converted', () {
    final scholar = <String, Object?>{
      'semesters': [
        {
          'name': 'S',
          'courses': {
            'a': {'id': 'source-a', 'name': '课程甲'},
          },
        },
      ],
    };
    final result = courseConverter.convert(
      scholar: scholar,
      convertedSemesterIds: {},
    );

    expect(result.courses, isEmpty);
    expect(result.unresolvedCourses.single['reason'], '所属学期未能确定日期');
    expect(result.reviewItems, hasLength(1));
  });
}
