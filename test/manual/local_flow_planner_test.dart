import 'package:celechron/model/period.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/manual/service/local_upcoming_schedule_planner.dart';
import 'package:flutter_test/flutter_test.dart';

Task _task(
  DateTime deadline, {
  bool estimated = true,
  Duration timeNeeded = const Duration(minutes: 30),
  Duration timeSpent = Duration.zero,
  TaskType type = TaskType.deadline,
  TaskStatus status = TaskStatus.running,
  bool coursework = false,
}) =>
    Task(
      uid: 'task-plan-1',
      type: type,
      status: status,
      isCoursework: coursework,
      summary: '完成报告',
      endTime: deadline,
      startTime: deadline.subtract(const Duration(days: 1)),
      repeatEndsTime: DateTime(deadline.year, deadline.month, deadline.day),
      timeNeeded: timeNeeded,
      timeSpent: timeSpent,
      isTimeEstimated: estimated,
      isBreakable: false,
    );

Period _period(PeriodType type, DateTime start, DateTime end) => Period(
      type: type,
      startTime: start,
      endTime: end,
    );

void main() {
  const planner = LocalUpcomingSchedulePlanner();
  final day = DateTime(2026, 10, 5);

  for (final type in [PeriodType.classes, PeriodType.test]) {
    test('task allocation skips a local ${type.name} period', () {
      final task = _task(day.add(const Duration(hours: 11)));
      final result = planner.planTasks(
        workTime: Duration.zero,
        restTime: Duration.zero,
        tasks: [task],
        availablePeriods: [
          _period(
            PeriodType.virtual,
            day.add(const Duration(hours: 9)),
            day.add(const Duration(hours: 11)),
          ),
        ],
        occupiedPeriods: [
          _period(
            type,
            day.add(const Duration(hours: 9)),
            day.add(const Duration(hours: 10)),
          ),
        ],
      );

      expect(result.isValid, isTrue);
      expect(result.assignSet, hasLength(1));
      expect(result.assignSet.single.startTime,
          day.add(const Duration(hours: 10)));
      expect(result.assignSet.single.endTime,
          day.add(const Duration(hours: 10, minutes: 30)));
    });
  }

  test('unestimated coursework stays pending and produces no assignment', () {
    final task = _task(
      day.add(const Duration(hours: 11)),
      estimated: false,
      coursework: true,
      timeNeeded: Duration.zero,
    );
    final result = planner.planTasks(
      workTime: Duration.zero,
      restTime: Duration.zero,
      tasks: [task],
      availablePeriods: [
        _period(
          PeriodType.virtual,
          day.add(const Duration(hours: 9)),
          day.add(const Duration(hours: 11)),
        ),
      ],
      occupiedPeriods: const [],
    );

    expect(result.isValid, isTrue);
    expect(result.assignSet, isEmpty);
    expect(task.status, TaskStatus.running);
  });

  test('estimated remaining coursework is allocated', () {
    final task = _task(
      day.add(const Duration(hours: 11)),
      timeNeeded: const Duration(minutes: 45),
      timeSpent: const Duration(minutes: 15),
      coursework: true,
    );
    final result = planner.planTasks(
      workTime: Duration.zero,
      restTime: Duration.zero,
      tasks: [task],
      availablePeriods: [
        _period(
          PeriodType.virtual,
          day.add(const Duration(hours: 9)),
          day.add(const Duration(hours: 11)),
        ),
      ],
      occupiedPeriods: const [],
    );

    expect(result.isValid, isTrue);
    expect(result.assignSet, hasLength(1));
    expect(
      result.assignSet.single.endTime.difference(
        result.assignSet.single.startTime,
      ),
      const Duration(minutes: 30),
    );
  });

  test('completed and already expired tasks are not scheduled', () {
    final completed = _task(
      day.add(const Duration(hours: 11)),
      status: TaskStatus.completed,
    );
    final expired = _task(
      day.add(const Duration(hours: 8)),
    );
    final result = planner.planTasks(
      workTime: Duration.zero,
      restTime: Duration.zero,
      tasks: [completed, expired],
      availablePeriods: [
        _period(
          PeriodType.virtual,
          day.add(const Duration(hours: 9)),
          day.add(const Duration(hours: 11)),
        ),
      ],
      occupiedPeriods: const [],
    );

    expect(result.isValid, isTrue);
    expect(result.assignSet, isEmpty);
  });
}
