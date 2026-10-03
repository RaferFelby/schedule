import '../../model/task.dart';

const reminderNotificationIdBase = 0x40000000;
const reminderNotificationIdMask = 0x3fffffff;

/// A notification candidate calculated without scheduling a platform event.
final class ReminderPlanEntry {
  const ReminderPlanEntry({
    required this.taskId,
    required this.notificationId,
    required this.scheduledAt,
    required this.deadlineAt,
    required this.timeZoneOffset,
  });

  final String taskId;
  final int notificationId;
  final DateTime scheduledAt;
  final DateTime deadlineAt;
  final Duration timeZoneOffset;
}

/// Creates deterministic future reminder candidates from local Task values.
final class ReminderPlanner {
  const ReminderPlanner();

  List<ReminderPlanEntry> plan({
    required Iterable<Task> tasks,
    required DateTime now,
  }) {
    final eligible = tasks.where(_isEligible).toList(growable: false)
      ..sort((a, b) => a.uid.compareTo(b.uid));
    final usedIds = <int>{};
    final entries = <ReminderPlanEntry>[];

    for (final task in eligible) {
      final scheduledAt = task.endTime.subtract(task.reminderOffset);
      if (!task.endTime.isAfter(now) || !scheduledAt.isAfter(now)) continue;

      var notificationId = _stableId(task.uid);
      while (!usedIds.add(notificationId)) {
        notificationId = reminderNotificationIdBase |
            (((notificationId & reminderNotificationIdMask) + 1) &
                reminderNotificationIdMask);
      }
      entries.add(
        ReminderPlanEntry(
          taskId: task.uid,
          notificationId: notificationId,
          scheduledAt: scheduledAt,
          deadlineAt: task.endTime,
          timeZoneOffset: scheduledAt.timeZoneOffset,
        ),
      );
    }

    entries.sort((a, b) {
      final byTime = a.scheduledAt.compareTo(b.scheduledAt);
      return byTime != 0 ? byTime : a.taskId.compareTo(b.taskId);
    });
    return List.unmodifiable(entries);
  }

  bool _isEligible(Task task) =>
      task.type == TaskType.deadline &&
      task.reminderEnabled &&
      task.reminderOffset >= Duration.zero &&
      (task.status == TaskStatus.running ||
          task.status == TaskStatus.suspended);

  int _stableId(String taskId) {
    var hash = 0x811c9dc5;
    for (final unit in taskId.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return reminderNotificationIdBase | (hash & reminderNotificationIdMask);
  }
}
