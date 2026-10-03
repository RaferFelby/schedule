import 'package:celechron/model/period.dart';

import '../model/local_course.dart';
import '../model/local_exam.dart';

/// Converts one explicitly timed exam into a calendar period.
final class ExamPeriodAdapter {
  const ExamPeriodAdapter._();

  static Period? toPeriod({
    required LocalExam exam,
    required LocalCourse course,
  }) {
    final start = exam.start;
    final end = exam.end;
    if (start == null || end == null) return null;
    return Period(
      uid: 'exam-${exam.id}',
      fromUid: course.id,
      type: PeriodType.test,
      description: '考试：${course.name}',
      startTime: start,
      endTime: end,
      location: exam.location ?? '',
      summary: '${course.name} · ${exam.type}',
    );
  }
}
