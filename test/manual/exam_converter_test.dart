import 'package:celechron/manual/migration/course_converter.dart';
import 'package:celechron/manual/migration/exam_converter.dart';
import 'package:celechron/manual/migration/semester_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves timed and explicitly unknown exams with stable IDs', () {
    final timed = <String, Object?>{
      'id': 'source-course-a',
      'name': '期末考试',
      'type': 1,
      'time': ['2026-12-20T09:00:00.000', '2026-12-20T11:00:00.000'],
      'location': '考场 A',
      'seat': '12',
    };
    final unknown = <String, Object?>{
      'id': 'source-course-a',
      'name': '期中考试',
      'type': 0,
      'time': <String>[],
      'dateLabel': '日期待定',
    };
    final scholar = _scholar(exams: [timed, unknown]);
    final first = _convert(scholar);
    final repeated = _convert(scholar);

    expect(first.exams, hasLength(2));
    expect(first.exams[0].type, 'finalExam');
    expect(first.exams[0].start, DateTime(2026, 12, 20, 9));
    expect(first.exams[0].end, DateTime(2026, 12, 20, 11));
    expect(first.exams[0].location, '考场 A');
    expect(first.exams[0].seat, '12');
    expect(first.exams[1].type, 'midterm');
    expect(first.exams[1].start, isNull);
    expect(first.exams[1].end, isNull);
    expect(first.exams.map((exam) => exam.id).toList(),
        repeated.exams.map((exam) => exam.id).toList());
    expect(first.reviewItems, contains(contains('日期/时间仍未定')));
  });

  test('reports exam/course ID conflicts and invalid time ranges', () {
    final scholar = _scholar(exams: [
      {
        'id': 'another-course',
        'name': 'ID 冲突',
        'type': 0,
        'time': <String>[],
      },
      {
        'id': 'source-course-a',
        'name': '时间逆序',
        'type': 1,
        'time': ['2026-12-20T11:00:00.000', '2026-12-20T09:00:00.000'],
      },
      {
        'id': 'source-course-a',
        'name': '缺少时间字段',
        'type': 0,
      },
    ]);
    final result = _convert(scholar);

    expect(result.exams, isEmpty);
    expect(result.unresolvedExams, hasLength(3));
    expect(result.unresolvedExams[0]['reason'], '考试 ID 与所属课程 ID 不一致');
    expect(result.unresolvedExams[1]['reason'], '考试时间无效或结束不晚于开始');
    expect(result.unresolvedExams[2]['reason'], '考试时间必须是两个有效端点或明确未定');
  });

  test('retains top-level exams without a parent course association', () {
    final orphan = <String, Object?>{
      'id': 'unknown-course',
      'name': '无关联考试',
      'type': 1,
      'time': <String>[],
    };
    final scholar = _scholar(exams: const [], semesterExams: [orphan]);
    final result = _convert(scholar);

    expect(result.exams, isEmpty);
    expect(result.unresolvedExams.single['reason'], '学期级考试未能对应到明确课程记录');
    expect(result.unresolvedExams.single['name'], '无关联考试');
  });
}

Map<String, Object?> _scholar({
  required List<Object?> exams,
  List<Object?>? semesterExams,
}) =>
    {
      'semesters': [
        {
          'name': 'S',
          'startDate': '2026-09-01',
          'endDate': '2027-01-31',
          'weekOneStart': '2026-08-31',
          'exams': semesterExams ?? exams,
          'courses': {
            'source-course-a': {
              'id': 'source-course-a',
              'name': '课程甲',
              'exams': exams,
            },
          },
        },
      ],
    };

LegacyExamConversionResult _convert(Map<String, Object?> scholar) {
  final semesterResult = const LegacySemesterConverter().convert(scholar);
  final courseResult = const LegacyCourseConverter().convert(
    scholar: scholar,
    convertedSemesterIds:
        semesterResult.semesters.map((semester) => semester.id).toSet(),
  );
  return const LegacyExamConverter().convert(
    scholar: scholar,
    courseMappings: courseResult.idMappings,
  );
}
