import 'package:celechron/model/period.dart';

import '../data/local_data_error.dart';
import '../model/local_course.dart';
import '../model/local_semester.dart';
import '../model/session_rule.dart';
import '../model/time_slot.dart';

/// Expands an explicit weekly rule into calendar periods.
final class ScheduleExpander {
  const ScheduleExpander._();

  static List<Period> expandRule({
    required LocalSemester semester,
    required LocalCourse course,
    required SessionRule rule,
    required Iterable<TimeSlot> timeSlots,
  }) {
    if (course.semesterId != semester.id || rule.courseId != course.id) {
      throw const LocalDataValidationError('学期、课程和上课规则关联不一致');
    }

    final slots = timeSlots.toList();
    TimeSlot.validateTemplate(slots);
    final slotsByOrdinal = {for (final slot in slots) slot.ordinal: slot};
    final requiredSlots = <TimeSlot>[];
    for (var ordinal = rule.startSlotOrdinal;
        ordinal <= rule.endSlotOrdinal;
        ordinal++) {
      final slot = slotsByOrdinal[ordinal];
      if (slot == null) {
        throw LocalDataValidationError('上课规则引用了不存在的第 $ordinal 节');
      }
      requiredSlots.add(slot);
    }

    final periods = <Period>[];
    for (final weekNumber in rule.weekNumbers) {
      final dayOffset = (weekNumber - 1) * 7 + rule.weekday - DateTime.monday;
      final date = semester.weekOneStart.add(Duration(days: dayOffset));
      final calendarDate = _dateOnly(date);
      if (rule.cancelledDates
              .any((cancelled) => _dateOnly(cancelled) == calendarDate) ||
          calendarDate.isBefore(semester.startDate) ||
          calendarDate.isAfter(semester.endDate)) {
        continue;
      }
      final overrides = rule.reschedules.where(
        (item) => _dateOnly(item.originalDate) == calendarDate,
      );
      final reschedule = overrides.isEmpty ? null : overrides.single;
      final targetDate = reschedule?.targetDate ?? calendarDate;
      if (targetDate.isBefore(semester.startDate) ||
          targetDate.isAfter(semester.endDate)) {
        throw const LocalDataValidationError('调课目标日期必须位于当前学期内');
      }
      final firstSlot = requiredSlots.first;
      final lastSlot = requiredSlots.last;
      final startMinute = reschedule?.startMinute ?? firstSlot.startMinute;
      final endMinute = reschedule?.endMinute ?? lastSlot.endMinute;
      final start = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
        startMinute ~/ 60,
        startMinute % 60,
      );
      final end = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
        endMinute ~/ 60,
        endMinute % 60,
      );
      periods.add(
        Period(
          uid: _eventId(rule.id, calendarDate),
          fromUid: course.id,
          type: PeriodType.classes,
          description: _description(course, rule),
          startTime: start,
          endTime: end,
          location: rule.location ?? '',
          summary: course.name,
        ),
      );
    }
    for (final extra in rule.extraOccurrences) {
      if (extra.date.isBefore(semester.startDate) ||
          extra.date.isAfter(semester.endDate)) {
        throw const LocalDataValidationError('补课日期必须位于当前学期内');
      }
      final extraSlots = <TimeSlot>[];
      for (var ordinal = extra.startSlotOrdinal;
          ordinal <= extra.endSlotOrdinal;
          ordinal++) {
        final slot = slotsByOrdinal[ordinal];
        if (slot == null) {
          throw LocalDataValidationError('补课引用了不存在的第 $ordinal 节');
        }
        extraSlots.add(slot);
      }
      final first = extraSlots.first;
      final last = extraSlots.last;
      periods.add(Period(
        uid: '${rule.id}-extra-${extra.id}',
        fromUid: course.id,
        type: PeriodType.classes,
        description: _description(course, rule),
        startTime: DateTime(
          extra.date.year,
          extra.date.month,
          extra.date.day,
          first.startMinute ~/ 60,
          first.startMinute % 60,
        ),
        endTime: DateTime(
          extra.date.year,
          extra.date.month,
          extra.date.day,
          last.endMinute ~/ 60,
          last.endMinute % 60,
        ),
        location: rule.location ?? '',
        summary: course.name,
      ));
    }

    periods.sort(comparePeriod);
    return List.unmodifiable(periods);
  }

  static String _eventId(String ruleId, DateTime date) =>
      '$ruleId-${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';

  static String _description(LocalCourse course, SessionRule rule) {
    final teacher = rule.teacher ?? course.teacher;
    return teacher == null ? course.name : '教师：$teacher';
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
