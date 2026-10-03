import 'package:celechron/manual/service/reminder_planner.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter_test/flutter_test.dart';

Task _task(
  String uid, {
  DateTime? deadline,
  TaskStatus status = TaskStatus.running,
  bool enabled = true,
  Duration offset = const Duration(hours: 1),
  TaskType type = TaskType.deadline,
}) {
  final end = deadline ?? DateTime(2030, 1, 2, 12);
  return Task(
    uid: uid,
    status: status,
    type: type,
    description: '提醒测试',
    summary: uid,
    endTime: end,
    startTime: end.subtract(const Duration(hours: 2)),
    repeatEndsTime: end,
    reminderEnabled: enabled,
    reminderOffset: offset,
  );
}

void main() {
  const planner = ReminderPlanner();
  final now = DateTime(2030, 1, 1, 8);

  test('same input yields stable IDs and ordered local future reminders', () {
    final tasks = [
      _task('task-b'),
      _task('task-a', deadline: DateTime(2030, 1, 2, 10)),
    ];

    final first = planner.plan(tasks: tasks, now: now);
    final second = planner.plan(tasks: tasks.reversed, now: now);

    expect(first.map((entry) => entry.taskId), ['task-a', 'task-b']);
    expect(
      first.map((entry) => entry.notificationId),
      second.map((entry) => entry.notificationId),
    );
    expect(first.map((entry) => entry.scheduledAt),
        second.map((entry) => entry.scheduledAt));
    expect(first.map((entry) => entry.notificationId).toSet(), hasLength(2));
    expect(
      first
          .every((entry) => entry.notificationId >= reminderNotificationIdBase),
      isTrue,
    );
    expect(
        first.any((entry) =>
            entry.notificationId == 0 || entry.notificationId == 1000),
        isFalse);
    expect(first.every((entry) => entry.scheduledAt.isAfter(now)), isTrue);
    expect(first.every((entry) => !entry.scheduledAt.isUtc), isTrue);
    expect(first.first.timeZoneOffset, first.first.scheduledAt.timeZoneOffset);
  });

  test('disabled, inactive, expired, and elapsed reminders are omitted', () {
    final tasks = [
      _task('enabled'),
      _task('disabled', enabled: false),
      _task('completed', status: TaskStatus.completed),
      _task('failed', status: TaskStatus.failed),
      _task('outdated', status: TaskStatus.outdated),
      _task('deleted', status: TaskStatus.deleted),
      _task('expired', deadline: DateTime(2030, 1, 1, 7)),
      _task(
        'elapsed',
        deadline: DateTime(2030, 1, 1, 8, 30),
        offset: const Duration(hours: 1),
      ),
      _task('negative-offset', offset: const Duration(seconds: -1)),
      _task('fixed', type: TaskType.fixed),
    ];

    final entries = planner.plan(tasks: tasks, now: now);
    expect(entries.map((entry) => entry.taskId), ['enabled']);
  });

  test('suspended tasks keep reminders and UTC inputs remain UTC', () {
    final utcNow = DateTime.utc(2030, 1, 1, 8);
    final entry = planner.plan(
      tasks: [
        _task(
          'suspended',
          status: TaskStatus.suspended,
          deadline: DateTime.utc(2030, 1, 2, 12),
        ),
      ],
      now: utcNow,
    ).single;

    expect(entry.scheduledAt.isUtc, isTrue);
    expect(entry.timeZoneOffset, Duration.zero);
  });
}
