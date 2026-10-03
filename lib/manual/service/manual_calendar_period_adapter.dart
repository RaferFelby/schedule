import 'package:celechron/model/period.dart';

import '../data/academic_repository.dart';
import '../model/academic_profile.dart';
import '../model/time_slot.dart';
import 'exam_period_adapter.dart';
import 'schedule_expander.dart';

/// Bridges the manual-entry snapshot to the app's existing Period calendar.
final class ManualCalendarPeriodAdapter {
  const ManualCalendarPeriodAdapter(this._repository);

  final AcademicRepository _repository;

  Future<List<Period>> readPeriods([AcademicProfile? snapshot]) async {
    final profile = snapshot ?? await _repository.read();
    final slots = profile.timeSlots.isEmpty
        ? TimeSlot.defaultTemplate()
        : profile.timeSlots;
    final semestersById = {
      for (final semester in profile.semesters) semester.id: semester,
    };
    final coursesById = {
      for (final course in profile.courses) course.id: course
    };
    final periods = <Period>[];
    for (final rule in profile.sessionRules) {
      final course = coursesById[rule.courseId];
      final semester = course == null ? null : semestersById[course.semesterId];
      if (course == null || semester == null) continue;
      periods.addAll(ScheduleExpander.expandRule(
        semester: semester,
        course: course,
        rule: rule,
        timeSlots: slots,
      ));
    }
    for (final exam in profile.exams) {
      final course = coursesById[exam.courseId];
      if (course == null) continue;
      final period = ExamPeriodAdapter.toPeriod(exam: exam, course: course);
      if (period != null) periods.add(period);
    }
    periods.sort(comparePeriod);
    return List.unmodifiable(periods);
  }
}
