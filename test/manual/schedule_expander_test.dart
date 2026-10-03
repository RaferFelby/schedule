import 'package:celechron/manual/data/local_data_error.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/model/session_rule.dart';
import 'package:celechron/manual/model/session_extra_occurrence.dart';
import 'package:celechron/manual/model/session_reschedule.dart';
import 'package:celechron/manual/model/time_slot.dart';
import 'package:celechron/manual/service/schedule_expander.dart';
import 'package:celechron/model/period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScheduleExpander', () {
    final semester = LocalSemester(
      id: '10000000-0000-4000-8000-000000000001',
      name: '秋季学期',
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2027, 1, 31),
      weekOneStart: DateTime(2026, 9, 14),
    );
    final course = LocalCourse(
      id: '20000000-0000-4000-8000-000000000001',
      semesterId: semester.id,
      name: '数据结构',
      teacher: '张老师',
    );

    test('expands explicit weeks to dates and combines the slot range', () {
      final rule = SessionRule(
        id: '30000000-0000-4000-8000-000000000001',
        courseId: course.id,
        weekday: DateTime.tuesday,
        weekNumbers: [1, 2],
        startSlotOrdinal: 1,
        endSlotOrdinal: 2,
        location: '教学楼 101',
      );
      final periods = ScheduleExpander.expandRule(
        semester: semester,
        course: course,
        rule: rule,
        timeSlots: [
          TimeSlot(
            id: '40000000-0000-4000-8000-000000000001',
            ordinal: 1,
            startMinute: 480,
            endMinute: 525,
          ),
          TimeSlot(
            id: '40000000-0000-4000-8000-000000000002',
            ordinal: 2,
            startMinute: 530,
            endMinute: 575,
          ),
        ],
      );

      expect(periods, hasLength(2));
      expect(
        periods.map((period) => DateTime(
              period.startTime.year,
              period.startTime.month,
              period.startTime.day,
            )),
        [DateTime(2026, 9, 15), DateTime(2026, 9, 22)],
      );
      expect(periods.map((period) => period.type),
          everyElement(PeriodType.classes));
      expect(periods.first.fromUid, course.id);
      expect(periods.first.summary, course.name);
      expect(periods.first.description, '教师：张老师');
      expect(periods.first.location, '教学楼 101');
      expect(periods.first.startTime.hour, 8);
      expect(periods.first.startTime.minute, 0);
      expect(periods.first.endTime.hour, 9);
      expect(periods.first.endTime.minute, 35);
    });

    test('uses rule-specific teacher before the course-level teacher', () {
      final rule = SessionRule(
        id: '30000000-0000-4000-8000-000000000099',
        courseId: course.id,
        weekday: DateTime.tuesday,
        weekNumbers: [1],
        startSlotOrdinal: 1,
        endSlotOrdinal: 1,
        teacher: '分周教师',
      );

      final periods = ScheduleExpander.expandRule(
        semester: semester,
        course: course,
        rule: rule,
        timeSlots: TimeSlot.defaultTemplate(),
      );

      expect(periods.single.description, '教师：分周教师');
    });

    test('omits only the cancelled occurrence date', () {
      final rule = SessionRule(
        id: '30000000-0000-4000-8000-000000000006',
        courseId: course.id,
        weekday: DateTime.tuesday,
        weekNumbers: [1, 2],
        startSlotOrdinal: 1,
        endSlotOrdinal: 1,
        cancelledDates: [DateTime(2026, 9, 22)],
      );
      final periods = ScheduleExpander.expandRule(
        semester: semester,
        course: course,
        rule: rule,
        timeSlots: TimeSlot.defaultTemplate(),
      );

      expect(periods, hasLength(1));
      expect(periods.single.startTime, DateTime(2026, 9, 15, 8));
      expect(periods.single.uid, contains('20260915'));
    });

    test('moves an occurrence but keeps its original stable event ID', () {
      final rule = SessionRule(
        id: '30000000-0000-4000-8000-000000000007',
        courseId: course.id,
        weekday: DateTime.tuesday,
        weekNumbers: [1, 2],
        startSlotOrdinal: 1,
        endSlotOrdinal: 1,
        reschedules: [
          SessionReschedule(
            originalDate: DateTime(2026, 9, 22),
            targetDate: DateTime(2026, 9, 23),
            startMinute: 540,
            endMinute: 585,
          )
        ],
      );
      final periods = ScheduleExpander.expandRule(
        semester: semester,
        course: course,
        rule: rule,
        timeSlots: TimeSlot.defaultTemplate(),
      );
      expect(periods, hasLength(2));
      final moved = periods.last;
      expect(moved.startTime, DateTime(2026, 9, 23, 9));
      expect(moved.endTime, DateTime(2026, 9, 23, 9, 45));
      expect(moved.uid, contains('20260922'));
    });

    test('adds an extra occurrence without changing weekly sessions', () {
      final rule = SessionRule(
        id: '30000000-0000-4000-8000-000000000008',
        courseId: course.id,
        weekday: DateTime.tuesday,
        weekNumbers: [1],
        startSlotOrdinal: 1,
        endSlotOrdinal: 1,
        extraOccurrences: [
          SessionExtraOccurrence(
            id: 'extra-1',
            date: DateTime(2026, 9, 26),
            startSlotOrdinal: 2,
            endSlotOrdinal: 2,
          )
        ],
      );
      final periods = ScheduleExpander.expandRule(
        semester: semester,
        course: course,
        rule: rule,
        timeSlots: TimeSlot.defaultTemplate(),
      );
      expect(periods, hasLength(2));
      expect(periods.first.startTime, DateTime(2026, 9, 15, 8));
      expect(periods.last.startTime, DateTime(2026, 9, 26, 8, 50));
      expect(periods.last.uid, contains('extra-extra-1'));
    });

    test('rejects a rule whose course does not match the supplied course', () {
      final rule = SessionRule(
        id: '30000000-0000-4000-8000-000000000002',
        courseId: '20000000-0000-4000-8000-000000000099',
        weekday: DateTime.tuesday,
        weekNumbers: [1],
        startSlotOrdinal: 1,
        endSlotOrdinal: 1,
      );
      expect(
        () => ScheduleExpander.expandRule(
          semester: semester,
          course: course,
          rule: rule,
          timeSlots: TimeSlot.defaultTemplate(),
        ),
        throwsA(isA<LocalDataValidationError>()),
      );
    });

    test('rejects missing section definitions instead of silently dropping',
        () {
      final rule = SessionRule(
        id: '30000000-0000-4000-8000-000000000003',
        courseId: course.id,
        weekday: DateTime.tuesday,
        weekNumbers: [1],
        startSlotOrdinal: 1,
        endSlotOrdinal: 2,
      );
      expect(
        () => ScheduleExpander.expandRule(
          semester: semester,
          course: course,
          rule: rule,
          timeSlots: TimeSlot.defaultTemplate().take(1),
        ),
        throwsA(isA<LocalDataValidationError>()),
      );
    });

    test('filters dates outside semester while keeping the end date inclusive',
        () {
      final limitedSemester = LocalSemester(
        id: semester.id,
        name: semester.name,
        startDate: DateTime(2026, 9, 16),
        endDate: DateTime(2026, 9, 22),
        weekOneStart: semester.weekOneStart,
      );
      final rule = SessionRule(
        id: '30000000-0000-4000-8000-000000000004',
        courseId: course.id,
        weekday: DateTime.tuesday,
        weekNumbers: [1, 2],
        startSlotOrdinal: 1,
        endSlotOrdinal: 1,
      );
      final periods = ScheduleExpander.expandRule(
        semester: limitedSemester,
        course: course,
        rule: rule,
        timeSlots: TimeSlot.defaultTemplate(),
      );

      expect(periods, hasLength(1));
      expect(periods.single.startTime, DateTime(2026, 9, 22, 8));
    });

    test('event IDs depend on rule and date, not course text or location', () {
      final originalRule = SessionRule(
        id: '30000000-0000-4000-8000-000000000005',
        courseId: course.id,
        weekday: DateTime.tuesday,
        weekNumbers: [1, 2],
        startSlotOrdinal: 1,
        endSlotOrdinal: 1,
        location: '教室 A',
      );
      final changedRule = SessionRule(
        id: originalRule.id,
        courseId: course.id,
        weekday: originalRule.weekday,
        weekNumbers: originalRule.weekNumbers,
        startSlotOrdinal: originalRule.startSlotOrdinal,
        endSlotOrdinal: originalRule.endSlotOrdinal,
        location: '教室 B',
      );
      final renamedCourse = LocalCourse(
        id: course.id,
        semesterId: course.semesterId,
        name: '新课程名',
        teacher: '新教师',
      );
      final original = ScheduleExpander.expandRule(
        semester: semester,
        course: course,
        rule: originalRule,
        timeSlots: TimeSlot.defaultTemplate(),
      );
      final changed = ScheduleExpander.expandRule(
        semester: semester,
        course: renamedCourse,
        rule: changedRule,
        timeSlots: TimeSlot.defaultTemplate(),
      );

      expect(
        changed.map((period) => period.uid),
        original.map((period) => period.uid),
      );
    });
  });
}
