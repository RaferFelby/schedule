import 'package:celechron/algorithm/arrange.dart';
import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/service/manual_calendar_period_adapter.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/task.dart';

/// Reads local academic periods and plans deadline tasks around them.
final class LocalUpcomingSchedulePlanner {
  const LocalUpcomingSchedulePlanner();

  Future<List<Period>> readPeriods(AcademicRepository repository) =>
      ManualCalendarPeriodAdapter(repository).readPeriods();

  TimeAssignSet planTasks({
    required Duration workTime,
    required Duration restTime,
    required List<Task> tasks,
    required List<Period> availablePeriods,
    required List<Period> occupiedPeriods,
  }) =>
      getTimeAssignSet(
        workTime,
        restTime,
        _eligiblePlanningTasks(tasks, availablePeriods),
        _subtractOccupiedPeriods(availablePeriods, occupiedPeriods),
      );

  List<Task> _eligiblePlanningTasks(
    List<Task> tasks,
    List<Period> availablePeriods,
  ) {
    final firstAvailable = availablePeriods.isEmpty
        ? null
        : availablePeriods.map((period) => period.startTime).reduce(
              (left, right) => left.isBefore(right) ? left : right,
            );
    return tasks.where((task) {
      final active = task.status == TaskStatus.running ||
          task.status == TaskStatus.suspended ||
          task.status == TaskStatus.failed;
      final hasRemainingWork = task.timeNeeded > task.timeSpent;
      final deadlineIsValid =
          firstAvailable == null || !task.endTime.isBefore(firstAvailable);
      return task.type == TaskType.deadline &&
          active &&
          task.isTimeEstimated &&
          hasRemainingWork &&
          deadlineIsValid;
    }).toList();
  }

  List<Period> _subtractOccupiedPeriods(
    List<Period> availablePeriods,
    List<Period> occupiedPeriods,
  ) {
    final sortedOccupied = occupiedPeriods.toList()
      ..sort((left, right) => left.startTime.compareTo(right.startTime));
    final available = <Period>[];
    for (final source in availablePeriods) {
      var cursor = source.startTime;
      for (final occupied in sortedOccupied) {
        if (!occupied.endTime.isAfter(cursor) ||
            !occupied.startTime.isBefore(source.endTime)) {
          continue;
        }
        final cutStart =
            occupied.startTime.isAfter(cursor) ? occupied.startTime : cursor;
        if (cutStart.isAfter(cursor)) {
          available.add(Period(
            type: PeriodType.virtual,
            startTime: cursor,
            endTime: cutStart,
          ));
        }
        if (occupied.endTime.isAfter(cursor)) cursor = occupied.endTime;
        if (!cursor.isBefore(source.endTime)) break;
      }
      if (cursor.isBefore(source.endTime)) {
        available.add(Period(
          type: PeriodType.virtual,
          startTime: cursor,
          endTime: source.endTime,
        ));
      }
    }
    return available;
  }
}
