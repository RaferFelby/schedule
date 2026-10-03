import 'package:celechron/manual/service/reminder_planner.dart';
import 'package:celechron/manual/service/reminder_scheduler.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeGateway implements ReminderNotificationGateway {
  _FakeGateway({this.permissionGranted = true, this.enabled = true});

  final bool permissionGranted;
  final bool? enabled;
  final scheduled = <({ReminderPlanEntry entry, String title})>[];
  final cancelled = <int>[];
  final pending = <PendingReminderNotification>[];
  int permissionRequests = 0;

  @override
  Future<bool> requestPermissions() async {
    permissionRequests++;
    return permissionGranted;
  }

  @override
  Future<void> schedule(ReminderPlanEntry entry,
      {required String title}) async {
    pending.removeWhere((request) => request.id == entry.notificationId);
    scheduled.add((entry: entry, title: title));
    pending.add(PendingReminderNotification(
      id: entry.notificationId,
      title: '任务截止提醒',
      body: title,
      payload: reminderNotificationPayload(entry),
    ));
  }

  @override
  Future<void> cancel(int notificationId) async {
    cancelled.add(notificationId);
    pending.removeWhere((request) => request.id == notificationId);
  }

  @override
  Future<bool?> notificationsEnabled() async => enabled;

  @override
  Future<List<PendingReminderNotification>> pendingNotifications() async =>
      List.of(pending);

  void addPending(int id, {String? payload}) {
    pending.add(PendingReminderNotification(id: id, payload: payload));
  }
}

ReminderPlanEntry _entry() {
  final task = Task(
    uid: 'task-1',
    description: '说明',
    summary: '交报告',
    endTime: DateTime(2030, 1, 2, 12),
    startTime: DateTime(2030, 1, 2, 10),
    repeatEndsTime: DateTime(2030, 1, 2),
    reminderEnabled: true,
  );
  return const ReminderPlanner()
      .plan(tasks: [task], now: DateTime(2030, 1, 1, 8)).single;
}

void main() {
  test('denied permission returns visible status without scheduling', () async {
    final gateway = _FakeGateway(permissionGranted: false, enabled: null);
    final scheduler = ReminderScheduler(
      gateway: gateway,
      supportsPlatform: () => true,
    );

    final result = await scheduler.schedule(
      [_entry()],
      taskTitles: const {'task-1': '交报告'},
    );

    expect(result.status, ReminderScheduleStatus.permissionDenied);
    expect(result.scheduledCount, 0);
    expect(gateway.permissionRequests, 1);
    expect(gateway.scheduled, isEmpty);
  });

  test('granted permission schedules title and plan ID, then cancels by ID',
      () async {
    final gateway = _FakeGateway();
    final scheduler = ReminderScheduler(
      gateway: gateway,
      supportsPlatform: () => true,
    );
    final entry = _entry();

    final scheduled = await scheduler.schedule(
      [entry],
      taskTitles: const {'task-1': '交报告'},
    );
    final cancelled = await scheduler.cancel([entry]);

    expect(scheduled.status, ReminderScheduleStatus.scheduled);
    expect(scheduled.scheduledCount, 1);
    expect(gateway.scheduled.single.entry.notificationId, entry.notificationId);
    expect(gateway.scheduled.single.title, '交报告');
    expect(cancelled.status, ReminderScheduleStatus.cancelled);
    expect(cancelled.cancelledCount, 1);
    expect(gateway.cancelled, [entry.notificationId]);
  });

  test('empty plans and unsupported platforms do not request permission',
      () async {
    final gateway = _FakeGateway();
    final unsupported = ReminderScheduler(
      gateway: gateway,
      supportsPlatform: () => false,
    );
    final empty = await unsupported.schedule(const [], taskTitles: const {});
    final unsupportedResult = await unsupported.schedule(
      [_entry()],
      taskTitles: const {'task-1': '交报告'},
    );

    expect(empty.status, ReminderScheduleStatus.noReminders);
    expect(
        unsupportedResult.status, ReminderScheduleStatus.unsupportedPlatform);
    expect(gateway.permissionRequests, 0);
    expect(gateway.scheduled, isEmpty);
  });

  test('reconcile repairs changed plans and preserves unrelated requests',
      () async {
    final entry = _entry();
    final previous = ReminderPlanEntry(
      taskId: entry.taskId,
      notificationId: entry.notificationId,
      scheduledAt: entry.scheduledAt.add(const Duration(hours: 1)),
      deadlineAt: entry.deadlineAt.add(const Duration(hours: 1)),
      timeZoneOffset: entry.timeZoneOffset,
    );
    final gateway = _FakeGateway()
      ..addPending(0)
      ..addPending(1000)
      ..addPending(
        entry.notificationId,
        payload: reminderNotificationPayload(previous),
      );
    final scheduler = ReminderScheduler(
      gateway: gateway,
      supportsPlatform: () => true,
    );

    final first = await scheduler.reconcile(
      [entry],
      taskTitles: const {'task-1': '交报告'},
    );
    final second = await scheduler.reconcile(
      [entry],
      taskTitles: const {'task-1': '交报告'},
    );

    expect(first.status, ReminderScheduleStatus.scheduled);
    expect(first.cancelledCount, 1);
    expect(second.status, ReminderScheduleStatus.noReminders);
    expect(gateway.scheduled, hasLength(1));
    expect(gateway.cancelled, [entry.notificationId]);
    expect(
      gateway.pending.map((request) => request.id),
      [0, 1000, entry.notificationId],
    );
  });

  test('reconcile reports the platform pending request limit', () async {
    final gateway = _FakeGateway();
    for (var id = 0; id < 64; id++) {
      gateway.addPending(id);
    }
    final scheduler = ReminderScheduler(
      gateway: gateway,
      supportsPlatform: () => true,
    );

    final result = await scheduler.reconcile(
      [_entry()],
      taskTitles: const {'task-1': '交报告'},
    );

    expect(result.status, ReminderScheduleStatus.limitExceeded);
    expect(gateway.scheduled, isEmpty);
    expect(gateway.pending, hasLength(64));
  });

  test('reconcile does not replace an unrelated notification ID collision',
      () async {
    final entry = _entry();
    final gateway = _FakeGateway()
      ..addPending(entry.notificationId, payload: 'another-feature');
    final scheduler = ReminderScheduler(
      gateway: gateway,
      supportsPlatform: () => true,
    );

    final result = await scheduler.reconcile(
      [entry],
      taskTitles: const {'task-1': '交报告'},
    );

    expect(result.status, ReminderScheduleStatus.failed);
    expect(gateway.cancelled, isEmpty);
    expect(gateway.scheduled, isEmpty);
    expect(gateway.pending.single.payload, 'another-feature');
  });

  test('reconcile returns permission denial for a missing plan', () async {
    final gateway = _FakeGateway(permissionGranted: false, enabled: null);
    final scheduler = ReminderScheduler(
      gateway: gateway,
      supportsPlatform: () => true,
    );

    final result = await scheduler.reconcile(
      [_entry()],
      taskTitles: const {'task-1': '交报告'},
    );

    expect(result.status, ReminderScheduleStatus.permissionDenied);
    expect(gateway.scheduled, isEmpty);
  });
}
