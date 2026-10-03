import 'dart:convert';

import 'package:hive/hive.dart';

import '../model/task.dart';
import '../manual/service/manual_planning_revision.dart';
import '../manual/service/reminder_planner.dart';
import '../manual/service/reminder_scheduler.dart';
import 'manual_preview_storage.dart';

/// Task records stored in the active generation's task box.
final class ManualPreviewTaskStore {
  ManualPreviewTaskStore(
    this._box, {
    ReminderScheduler? reminderScheduler,
    ReminderPlanner planner = const ReminderPlanner(),
    DateTime Function()? now,
  })  : _reminderScheduler = reminderScheduler ?? ReminderScheduler(),
        _planner = planner,
        _now = now ?? DateTime.now;

  final Box<String> _box;
  final ReminderScheduler _reminderScheduler;
  final ReminderPlanner _planner;
  final DateTime Function() _now;

  Future<List<Task>> readTasks() async {
    final stored = _box.get(ManualPreviewStorage.homeworkKey);
    if (stored != null) return _decodeStored(stored);

    final sample = _box.get(ManualPreviewStorage.sampleKey);
    if (sample == null) return const [];
    final decoded = jsonDecode(sample);
    if (decoded is! Map || decoded['tasks'] is! List) return const [];
    return (decoded['tasks'] as List)
        .whereType<Map>()
        .map((value) => _fromSample(Map<String, dynamic>.from(value)))
        .whereType<Task>()
        .toList(growable: false);
  }

  /// Whitelisted task fields for the versioned manual preview backup.
  Future<List<Map<String, Object?>>> exportTasksForBackup() async =>
      encodeTasksForBackup(await readTasks());

  static List<Map<String, Object?>> encodeTasksForBackup(
    Iterable<Task> tasks,
  ) =>
      tasks.map(_toJson).toList(growable: false);

  Future<ReminderScheduleResult> saveTasks(Iterable<Task> tasks) async {
    final before = await readTasks();
    final next = tasks.toList(growable: false);
    await _box.put(
      ManualPreviewStorage.homeworkKey,
      jsonEncode(next.map(_toJson).toList(growable: false)),
    );
    await noteTaskChange(before, next);
    return _syncReminders(next);
  }

  Future<ReminderScheduleResult> _syncReminders(
    List<Task> after,
  ) async {
    try {
      return await _reminderScheduler.reconcile(
        _planner.plan(tasks: after, now: _now()),
        taskTitles: {for (final task in after) task.uid: task.summary},
      );
    } on Object {
      return const ReminderScheduleResult(ReminderScheduleStatus.failed);
    }
  }

  /// Clears the stable course reference without changing task content.
  Future<int> unlinkCourse(String courseId) async {
    final tasks = await readTasks();
    var unlinkedCount = 0;
    final updated = tasks.map((task) {
      if (task.courseId != courseId) return task;
      unlinkedCount++;
      return task.copyWith(clearCourseId: true);
    }).toList(growable: false);
    if (unlinkedCount > 0) await saveTasks(updated);
    return unlinkedCount;
  }

  int get taskPlanningRevision =>
      int.tryParse(
        _box.get(ManualPreviewStorage.taskPlanningRevisionKey) ?? '',
      ) ??
      0;

  Future<ReminderScheduleResult> reconcileReminders() async {
    try {
      final tasks = await readTasks();
      final entries = _planner.plan(tasks: tasks, now: _now());
      return await _reminderScheduler.reconcile(
        entries,
        taskTitles: {for (final task in tasks) task.uid: task.summary},
      );
    } on Object {
      return const ReminderScheduleResult(ReminderScheduleStatus.failed);
    }
  }

  Future<void> noteTaskChange(
    Iterable<Task> before,
    Iterable<Task> after,
  ) async {
    if (!ManualPlanningRevision.tasksChanged(before, after)) return;
    await _box.put(
      ManualPreviewStorage.taskPlanningRevisionKey,
      '${taskPlanningRevision + 1}',
    );
  }

  static List<Task> _decodeStored(String encoded) {
    return decodeTasksForBackup(jsonDecode(encoded));
  }

  /// Strictly decodes the task records embedded in a manual backup.
  static List<Task> decodeTasksForBackup(Object? decoded) {
    if (decoded is! List) throw const FormatException('预览作业必须是数组');
    return decoded.map((value) {
      if (value is! Map) throw const FormatException('预览作业格式无效');
      final json = Map<String, dynamic>.from(value);
      final statusIndex = json['status'] as int;
      final typeIndex = json['type'] as int;
      final repeatIndex = json['repeatType'] as int;
      return Task(
        uid: json['uid'] as String,
        status: TaskStatus.values[statusIndex],
        description: json['description'] as String,
        timeSpent: Duration(microseconds: json['timeSpent'] as int),
        timeNeeded: Duration(microseconds: json['timeNeeded'] as int),
        endTime: DateTime.parse(json['endTime'] as String),
        location: json['location'] as String,
        summary: json['summary'] as String,
        isBreakable: json['isBreakable'] as bool,
        type: TaskType.values[typeIndex],
        startTime: DateTime.parse(json['startTime'] as String),
        repeatType: TaskRepeatType.values[repeatIndex],
        repeatPeriod: json['repeatPeriod'] as int,
        repeatEndsTime: DateTime.parse(json['repeatEndsTime'] as String),
        blockArrangements: json['blockArrangements'] as bool,
        fromUid: json['fromUid'] as String?,
        courseId: json['courseId'] as String?,
        isCoursework: json['isCoursework'] as bool,
        isTimeEstimated: json['isTimeEstimated'] as bool,
        reminderEnabled: json['reminderEnabled'] as bool? ?? false,
        reminderOffset: Duration(
          microseconds: json['reminderOffset'] as int? ??
              const Duration(days: 1).inMicroseconds,
        ),
      );
    }).toList(growable: false);
  }

  static Task? _fromSample(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final dueAt = json['dueAt'];
    if (json['type'] != 'coursework' ||
        id is! String ||
        title is! String ||
        dueAt is! String) {
      return null;
    }
    final end = DateTime.tryParse(dueAt);
    if (end == null) return null;
    final rawTimeNeeded = json['timeNeeded'];
    final estimated = rawTimeNeeded is num;
    final timeNeeded =
        estimated ? Duration(minutes: rawTimeNeeded.toInt()) : Duration.zero;
    return Task(
      uid: id,
      summary: title,
      endTime: end,
      startTime: end.subtract(const Duration(hours: 1)),
      repeatEndsTime: DateTime(end.year, end.month, end.day),
      timeNeeded: timeNeeded,
      courseId: json['courseId'] as String?,
      isCoursework: true,
      isTimeEstimated: estimated,
    );
  }

  static Map<String, Object?> _toJson(Task task) => {
        'uid': task.uid,
        'status': task.status.index,
        'description': task.description,
        'timeSpent': task.timeSpent.inMicroseconds,
        'timeNeeded': task.timeNeeded.inMicroseconds,
        'endTime': task.endTime.toIso8601String(),
        'location': task.location,
        'summary': task.summary,
        'isBreakable': task.isBreakable,
        'type': task.type.index,
        'startTime': task.startTime.toIso8601String(),
        'repeatType': task.repeatType.index,
        'repeatPeriod': task.repeatPeriod,
        'repeatEndsTime': task.repeatEndsTime.toIso8601String(),
        'blockArrangements': task.blockArrangements,
        'fromUid': task.fromUid,
        'courseId': task.courseId,
        'isCoursework': task.isCoursework,
        'isTimeEstimated': task.isTimeEstimated,
        'reminderEnabled': task.reminderEnabled,
        'reminderOffset': task.reminderOffset.inMicroseconds,
      };
}
