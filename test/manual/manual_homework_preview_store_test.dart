import 'dart:convert';
import 'dart:io';

import 'package:celechron/debug/manual_preview_sample_loader.dart';
import 'package:celechron/debug/manual_preview_storage.dart';
import 'package:celechron/debug/manual_preview_task_store.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/page/manual_homework_preview_page.dart';
import 'package:celechron/manual/service/manual_homework_adapter.dart';
import 'package:celechron/manual/service/reminder_planner.dart';
import 'package:celechron/manual/service/reminder_scheduler.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

final class _ReminderGateway implements ReminderNotificationGateway {
  _ReminderGateway({this.granted = true});

  final bool granted;
  final scheduled = <ReminderPlanEntry>[];
  final cancelled = <int>[];
  final pending = <PendingReminderNotification>[];
  int requests = 0;

  @override
  Future<bool> requestPermissions() async {
    requests++;
    return granted;
  }

  @override
  Future<void> schedule(ReminderPlanEntry entry,
      {required String title}) async {
    scheduled.add(entry);
    pending.removeWhere((request) => request.id == entry.notificationId);
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
  Future<bool?> notificationsEnabled() async => granted;

  @override
  Future<List<PendingReminderNotification>> pendingNotifications() async =>
      List.of(pending);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp(
      'celechron-homework-preview-',
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await documentsDirectory.exists()) {
      await documentsDirectory.delete(recursive: true);
    }
  });

  test(
      'preview tasks persist in the isolated box and completed items disappear',
      () async {
    final box = await ManualPreviewStorage.openAt(documentsDirectory.path);
    await ManualPreviewSampleLoader.load(box);
    final store = ManualPreviewTaskStore(box);
    final tasks = await store.readTasks();
    expect(tasks, hasLength(1));
    expect(tasks.single.isCoursework, isTrue);
    expect(tasks.single.isTimeEstimated, isFalse);
    final loadedRevision = store.taskPlanningRevision;
    expect(loadedRevision, 1);

    final sample = jsonDecode(box.get(ManualPreviewSampleLoader.sampleKey)!)
        as Map<String, dynamic>;
    final courses = (sample['courses'] as List)
        .map((value) => Map<String, dynamic>.from(value as Map))
        .map(
          (course) => LocalCourse(
            id: course['id'] as String,
            semesterId: course['semesterId'] as String,
            name: course['name'] as String,
          ),
        )
        .toList();
    expect(
      ManualHomeworkAdapter.pending(
        tasks: tasks,
        courses: courses,
      ).single.courseName,
      '示例课程',
    );

    final completed = tasks.single.copyWith(status: TaskStatus.completed);
    await store.saveTasks([completed]);
    expect(store.taskPlanningRevision, loadedRevision + 1);
    final restored = await store.readTasks();
    expect(restored.single.status, TaskStatus.completed);
    expect(
      ManualHomeworkAdapter.pending(
        tasks: restored,
        courses: courses,
      ),
      isEmpty,
    );

    final reminderPreference = restored.single.copyWith(
      reminderEnabled: true,
      reminderOffset: const Duration(days: 1),
    );
    await store.saveTasks([reminderPreference]);
    final reminderReloaded = (await store.readTasks()).single;
    expect(reminderReloaded.reminderEnabled, isTrue);
    expect(reminderReloaded.reminderOffset, const Duration(days: 1));
    expect(store.taskPlanningRevision, loadedRevision + 1);

    await store.saveTasks([reminderReloaded.copyWith(description: '补充说明')]);
    expect(store.taskPlanningRevision, loadedRevision + 1);
  });

  test('new task draft is a regular unlinked task and persists unchanged',
      () async {
    final box = await ManualPreviewStorage.openAt(documentsDirectory.path);
    final store = ManualPreviewTaskStore(box);
    final now = DateTime(2026, 10, 3, 9);
    final draft = ManualHomeworkPreviewPage.createNewTaskDraft(now: now);

    expect(draft.isCoursework, isFalse);
    expect(draft.courseId, isNull);
    expect(draft.isTimeEstimated, isTrue);
    expect(draft.timeNeeded, const Duration(hours: 1));

    await store.saveTasks([draft]);
    final saved = (await store.readTasks()).single;
    expect(saved.isCoursework, isFalse);
    expect(saved.courseId, isNull);
    expect(saved.uid, draft.uid);
  });

  test('course unlink is idempotent and preserves task fields', () async {
    final box = await ManualPreviewStorage.openAt(documentsDirectory.path);
    await ManualPreviewSampleLoader.load(box);
    final store = ManualPreviewTaskStore(box);
    final sample = (await store.readTasks()).single;
    final linked = sample.copyWith(
      summary: '保留标题',
      description: '保留原课程文本',
      timeSpent: const Duration(minutes: 17),
      courseId: '20000000-0000-4000-8000-000000000001',
    );
    final unrelated = sample.copyWith(
      uid: '50000000-0000-4000-8000-000000000002',
      courseId: '20000000-0000-4000-8000-000000000002',
    );
    await store.saveTasks([linked, unrelated]);
    final revision = store.taskPlanningRevision;

    expect(await store.unlinkCourse(linked.courseId!), 1);
    expect(await store.unlinkCourse(linked.courseId!), 0);

    final saved = await store.readTasks();
    final detached = saved.singleWhere((task) => task.uid == linked.uid);
    expect(saved, hasLength(2));
    expect(detached.courseId, isNull);
    expect(detached.summary, '保留标题');
    expect(detached.description, '保留原课程文本');
    expect(detached.endTime, linked.endTime);
    expect(detached.timeSpent, const Duration(minutes: 17));
    expect(saved.singleWhere((task) => task.uid == unrelated.uid).courseId,
        unrelated.courseId);
    expect(store.taskPlanningRevision, revision);
  });

  test('legacy preview task JSON defaults reminder fields safely', () async {
    final box = await ManualPreviewStorage.openAt(documentsDirectory.path);
    await ManualPreviewSampleLoader.load(box);
    final store = ManualPreviewTaskStore(box);
    await store.saveTasks(await store.readTasks());

    final stored =
        (jsonDecode(box.get(ManualPreviewStorage.homeworkKey)!) as List).single
            as Map<String, dynamic>;
    stored.remove('reminderEnabled');
    stored.remove('reminderOffset');
    await box.put(ManualPreviewStorage.homeworkKey, jsonEncode([stored]));

    final restored = (await store.readTasks()).single;
    expect(restored.reminderEnabled, isFalse);
    expect(restored.reminderOffset, const Duration(days: 1));
  });

  test('task edits replace plans once and completion or deletion cancels them',
      () async {
    final box = await ManualPreviewStorage.openAt(documentsDirectory.path);
    final now = DateTime(2030, 1, 1, 9);
    final gateway = _ReminderGateway();
    final store = ManualPreviewTaskStore(
      box,
      reminderScheduler: ReminderScheduler(
        gateway: gateway,
        supportsPlatform: () => true,
      ),
      now: () => now,
    );
    final task = Task(
      uid: 'task-reminder-sync',
      summary: '交报告',
      endTime: DateTime(2030, 1, 4, 17),
      startTime: DateTime(2030, 1, 4, 16),
      repeatEndsTime: DateTime(2030, 1, 4),
      reminderEnabled: true,
    );

    final first = await store.saveTasks([task]);
    final repeated = await store.saveTasks(await store.readTasks());
    expect(first.status, ReminderScheduleStatus.scheduled);
    expect(repeated.status, ReminderScheduleStatus.noReminders);
    expect(gateway.requests, 0);
    expect(gateway.scheduled, hasLength(1));

    final updated = task.copyWith(endTime: DateTime(2030, 1, 5, 17));
    await store.saveTasks([updated]);
    expect(gateway.cancelled, [gateway.scheduled.first.notificationId]);
    expect(gateway.scheduled, hasLength(2));
    expect(gateway.scheduled.last.notificationId,
        gateway.scheduled.first.notificationId);
    expect(gateway.scheduled.last.scheduledAt, DateTime(2030, 1, 4, 17));

    final completed = updated.copyWith(status: TaskStatus.completed);
    await store.saveTasks([completed]);
    expect(gateway.cancelled, hasLength(2));
    expect(gateway.cancelled.last, gateway.scheduled.last.notificationId);

    final toDelete = updated.copyWith(uid: 'task-reminder-delete');
    await store.saveTasks([toDelete]);
    final deleteId = gateway.scheduled.last.notificationId;
    await store.saveTasks(const []);
    expect(gateway.cancelled.last, deleteId);
  });

  test('permission denial does not roll back the saved task', () async {
    final box = await ManualPreviewStorage.openAt(documentsDirectory.path);
    final gateway = _ReminderGateway(granted: false);
    final store = ManualPreviewTaskStore(
      box,
      reminderScheduler: ReminderScheduler(
        gateway: gateway,
        supportsPlatform: () => true,
      ),
      now: () => DateTime(2030, 1, 1),
    );
    final task = Task(
      uid: 'task-permission-denied',
      summary: '保存仍成功',
      endTime: DateTime(2030, 1, 4),
      startTime: DateTime(2030, 1, 3),
      repeatEndsTime: DateTime(2030, 1, 4),
      reminderEnabled: true,
    );

    final result = await store.saveTasks([task]);

    expect(result.status, ReminderScheduleStatus.permissionDenied);
    expect((await store.readTasks()).single.summary, '保存仍成功');
    expect(gateway.scheduled, isEmpty);
  });

  test('startup reconciliation restores missing reminders without duplicates',
      () async {
    final box = await ManualPreviewStorage.openAt(documentsDirectory.path);
    final now = DateTime(2030, 1, 1, 9);
    final gateway = _ReminderGateway();
    final store = ManualPreviewTaskStore(
      box,
      reminderScheduler: ReminderScheduler(
        gateway: gateway,
        supportsPlatform: () => true,
      ),
      now: () => now,
    );
    final task = Task(
      uid: 'task-reconcile',
      summary: '重启后恢复',
      endTime: DateTime(2030, 1, 4, 17),
      startTime: DateTime(2030, 1, 4, 16),
      repeatEndsTime: DateTime(2030, 1, 4),
      reminderEnabled: true,
    );
    await store.saveTasks([task]);
    gateway.pending.clear(); // simulate a notification missing from iOS

    final restored = await store.reconcileReminders();
    final unchanged = await store.reconcileReminders();

    expect(restored.status, ReminderScheduleStatus.scheduled);
    expect(restored.scheduledCount, 1);
    expect(unchanged.status, ReminderScheduleStatus.noReminders);
    expect(gateway.scheduled, hasLength(2));
    expect(gateway.pending, hasLength(1));
  });
}
