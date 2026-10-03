import 'package:celechron/manual/migration/course_converter.dart';
import 'package:celechron/manual/migration/semester_converter.dart';
import 'package:celechron/manual/migration/session_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converts explicit custom weeks and keeps section ordinals', () {
    final scholar = _scholar(
      session: {
        'id': 'source-course-a',
        'day': 2,
        'time': [1, 2],
        'customRepeat': true,
        'customRepeatWeeks': [1, 3],
        'location': '教室 A',
      },
    );
    final result = _convert(scholar);

    expect(result.sessionRules, hasLength(1));
    final rule = result.sessionRules.single;
    expect(rule.weekday, 2);
    expect(rule.weekNumbers, [1, 3]);
    expect(rule.startSlotOrdinal, 1);
    expect(rule.endSlotOrdinal, 2);
    expect(rule.location, '教室 A');
    expect(rule.courseId, isNotEmpty);
    expect(result.unresolvedSessions, isEmpty);
    expect(_convert(scholar).sessionRules.single.id, rule.id);
  });

  test('derives weekly occurrences only from explicit cached dates', () {
    final calendar = _emptyCalendar();
    calendar[0][0][2] = [
      '2026-09-01T00:00:00.000',
      '2026-09-15T00:00:00.000',
    ];
    final scholar = _scholar(
      session: {
        'id': 'source-course-a',
        'day': 2,
        'time': [1],
        'customRepeat': false,
        'firstHalf': true,
        'secondHalf': false,
        'oddWeek': true,
        'evenWeek': false,
      },
      calendar: calendar,
    );
    final result = _convert(scholar);

    expect(result.sessionRules.single.weekNumbers, [1, 3]);
    expect(result.unresolvedSessions, isEmpty);
  });

  test('keeps sessions pending when date cache or course mapping is missing',
      () {
    final scholar = _scholar(
      session: {
        'id': 'source-course-a',
        'day': 2,
        'time': [1],
        'customRepeat': false,
        'firstHalf': true,
        'secondHalf': false,
        'oddWeek': true,
        'evenWeek': false,
      },
    );
    final semesterResult = const LegacySemesterConverter().convert(scholar);
    final courseResult = const LegacyCourseConverter().convert(
      scholar: scholar,
      convertedSemesterIds:
          semesterResult.semesters.map((value) => value.id).toSet(),
    );
    final noCacheResult = const LegacySessionConverter().convert(
      scholar: scholar,
      semesters: semesterResult.semesters,
      timeSlots: semesterResult.timeSlots,
      courseMappings: courseResult.idMappings,
    );
    final noMappingResult = const LegacySessionConverter().convert(
      scholar: scholar,
      semesters: semesterResult.semesters,
      timeSlots: semesterResult.timeSlots,
      courseMappings: const [],
    );

    expect(noCacheResult.sessionRules, isEmpty);
    expect(
        noCacheResult.unresolvedSessions.single['reason'], '旧学期逐日缓存缺失，无法确定周次');
    expect(noMappingResult.sessionRules, isEmpty);
    expect(
        noMappingResult.unresolvedSessions.single['reason'], '课程缺少可用的旧 ID 映射');
  });

  test('does not collapse non-contiguous section numbers into a range', () {
    final scholar = _scholar(
      session: {
        'id': 'source-course-a',
        'day': 2,
        'time': [1, 3],
        'customRepeat': true,
        'customRepeatWeeks': [1],
      },
    );
    final result = _convert(scholar);

    expect(result.sessionRules, isEmpty);
    expect(result.unresolvedSessions.single['reason'], '节次不连续，无法表示为单条节次范围');
  });

  test('does not reuse a conflicting semester time template', () {
    final first = _scholar(
      session: {
        'id': 'source-course-a',
        'day': 2,
        'time': [1],
        'customRepeat': true,
        'customRepeatWeeks': [1],
      },
    )['semesters']! as List;
    final firstSemester = Map<String, Object?>.from(first.single as Map);
    final secondSemester = Map<String, Object?>.from(firstSemester)
      ..['name'] = 'T'
      ..['sessionToTime'] = [
        <int>[],
        [500, 545],
      ]
      ..['courses'] = {
        'source-course-b': {
          'id': 'source-course-b',
          'name': '课程乙',
          'sessions': [
            {
              'id': 'source-course-b',
              'day': 2,
              'time': [1],
              'customRepeat': true,
              'customRepeatWeeks': [1],
            },
          ],
        },
      };
    final scholar = <String, Object?>{
      'semesters': [firstSemester, secondSemester],
    };
    final result = _convert(scholar);

    expect(result.sessionRules, hasLength(1));
    expect(result.unresolvedSessions, hasLength(1));
    expect(result.unresolvedSessions.single['semesterIndex'], 1);
    expect(result.unresolvedSessions.single['reason'], '旧学期节次时间与已迁移模板不一致');
  });
}

Map<String, Object?> _scholar({
  required Map<String, Object?> session,
  List<List<List<List<String>>>>? calendar,
}) =>
    {
      'semesters': [
        {
          'name': 'S',
          'startDate': '2026-08-31',
          'endDate': '2026-09-30',
          'weekOneStart': '2026-08-31',
          'sessionToTime': [
            <int>[],
            [480, 525],
            [530, 575],
          ],
          if (calendar != null) 'dayOfWeekToDays': calendar,
          'courses': {
            'source-course-a': {
              'id': 'source-course-a',
              'name': '课程甲',
              'credit': 2.0,
              'sessions': [session],
            },
          },
        },
      ],
    };

List<List<List<List<String>>>> _emptyCalendar() => List.generate(
      2,
      (_) => List.generate(
        2,
        (_) => List.generate(8, (_) => <String>[]),
      ),
    );

LegacySessionConversionResult _convert(Map<String, Object?> scholar) {
  final semesters = const LegacySemesterConverter().convert(scholar);
  final courses = const LegacyCourseConverter().convert(
    scholar: scholar,
    convertedSemesterIds: semesters.semesters.map((value) => value.id).toSet(),
  );
  return const LegacySessionConverter().convert(
    scholar: scholar,
    semesters: semesters.semesters,
    timeSlots: semesters.timeSlots,
    courseMappings: courses.idMappings,
  );
}
