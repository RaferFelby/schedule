import 'dart:convert';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../debug/manual_preview_sample_loader.dart';
import '../../debug/manual_preview_task_store.dart';
import '../../model/task.dart';
import '../../page/task/task_edit_page.dart';
import '../data/academic_repository.dart';
import '../model/local_course.dart';
import '../service/manual_homework_adapter.dart';
import '../service/reminder_scheduler.dart';

/// Coursework list backed by the active local task box and academic profile.
final class ManualHomeworkPreviewPage extends StatefulWidget {
  const ManualHomeworkPreviewPage({
    super.key,
    required this.previewBox,
    required this.repository,
  });

  final Box<String> previewBox;
  final AcademicRepository repository;

  @override
  State<ManualHomeworkPreviewPage> createState() =>
      _ManualHomeworkPreviewPageState();

  static Task createNewTaskDraft({DateTime? now}) {
    final start = now ?? DateTime.now();
    final due = start.add(const Duration(days: 1));
    final task = Task(
      summary: '',
      description: '',
      timeSpent: Duration.zero,
      timeNeeded: const Duration(hours: 1),
      endTime: due,
      startTime: start,
      repeatEndsTime: DateTime(due.year, due.month, due.day),
      location: '',
      isCoursework: false,
      isTimeEstimated: true,
    );
    task.genUid();
    return task;
  }
}

final class _ManualHomeworkPreviewPageState
    extends State<ManualHomeworkPreviewPage> with WidgetsBindingObserver {
  late final ManualPreviewTaskStore _store;
  List<Task> _tasks = const [];
  List<LocalCourse> _courses = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store = ManualPreviewTaskStore(widget.previewBox);
    _reload();
    unawaited(_reconcileReminders());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reconcileReminders());
    }
  }

  Future<void> _reconcileReminders() async {
    try {
      final result = await _store.reconcileReminders();
      if (!mounted) return;
      final message = switch (result.status) {
        ReminderScheduleStatus.permissionDenied => '通知权限未开启，部分任务提醒暂未安排。',
        ReminderScheduleStatus.unsupportedPlatform => '当前平台不支持本地提醒通知。',
        ReminderScheduleStatus.limitExceeded => '系统待处理提醒数量已达上限，部分任务提醒未安排。',
        ReminderScheduleStatus.failed => '提醒恢复失败，请稍后重试。',
        _ => null,
      };
      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提醒恢复失败，请稍后重试。')),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<List<LocalCourse>> _readCourses() async {
    final profile = await widget.repository.read();
    if (profile.courses.isNotEmpty) return profile.courses;
    final sample = widget.previewBox.get(ManualPreviewSampleLoader.sampleKey);
    if (sample == null) return const [];
    final decoded = jsonDecode(sample);
    if (decoded is! Map) return const [];
    final rawCourses = decoded['courses'];
    if (rawCourses is! List) return const [];
    return rawCourses.map((value) {
      if (value is! Map) throw const FormatException('样例课程格式无效');
      final json = Map<String, dynamic>.from(value);
      final id = json['id'];
      final semesterId = json['semesterId'];
      final name = json['name'];
      final credits = json['credits'];
      if (id is! String ||
          semesterId is! String ||
          name is! String ||
          (credits != null && credits is! num)) {
        throw const FormatException('样例课程字段无效');
      }
      return LocalCourse(
        id: id,
        semesterId: semesterId,
        name: name,
        credits: (credits as num?)?.toDouble(),
      );
    }).toList(growable: false);
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tasks = await _store.readTasks();
      final courses = await _readCourses();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _courses = courses;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveAndReportReminders(List<Task> tasks) async {
    final result = await _store.saveTasks(tasks);
    if (!mounted) return;
    final message = switch (result.status) {
      ReminderScheduleStatus.permissionDenied => '作业已保存，但通知权限未开启，提醒暂未安排。',
      ReminderScheduleStatus.unsupportedPlatform => '作业已保存；当前平台不支持本地提醒通知。',
      ReminderScheduleStatus.limitExceeded => '作业已保存；系统待处理提醒数量已达上限，当前提醒未安排。',
      ReminderScheduleStatus.failed => '作业已保存，但提醒同步失败；下次保存时会重试。',
      _ => null,
    };
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _addTask() async {
    final draft = ManualHomeworkPreviewPage.createNewTaskDraft();
    final task = await Navigator.of(context).push<Task>(
      CupertinoPageRoute(
        builder: (_) => TaskEditPage(draft, courseLoader: _readCourses),
      ),
    );
    if (task == null || task.status == TaskStatus.deleted) return;
    setState(() => _tasks = [..._tasks, task]);
    await _saveAndReportReminders(_tasks);
  }

  Future<void> _editTask(Task original) async {
    final task = await Navigator.of(context).push<Task>(
      CupertinoPageRoute(
        builder: (_) => TaskEditPage(original, courseLoader: _readCourses),
      ),
    );
    if (task == null) return;
    if (task.status == TaskStatus.deleted) {
      setState(() {
        _tasks = _tasks
            .where((entry) => entry.uid != task.uid)
            .toList(growable: false);
      });
      await _saveAndReportReminders(_tasks);
      return;
    }
    setState(() {
      _tasks = _tasks
          .map((entry) => entry.uid == task.uid ? task : entry)
          .toList(growable: false);
    });
    await _saveAndReportReminders(_tasks);
  }

  Future<void> _complete(Task task) async {
    final completed = task.copyWith(status: TaskStatus.completed);
    setState(() {
      _tasks = _tasks
          .map((entry) => entry.uid == task.uid ? completed : entry)
          .toList(growable: false);
    });
    await _saveAndReportReminders(_tasks);
  }

  @override
  Widget build(BuildContext context) {
    final courseNames = {for (final course in _courses) course.id: course.name};
    final pendingTasks = ManualHomeworkAdapter.pendingTasks(tasks: _tasks);
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务'),
        actions: [
          IconButton(
            tooltip: '新增任务',
            onPressed: _loading ? null : _addTask,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('读取任务失败：$_error'))
              : pendingTasks.isEmpty
                  ? const Center(
                      child: Text('还没有待办任务，可以直接添加普通任务；课程作业可稍后关联学期。'),
                    )
                  : ListView.builder(
                      itemCount: pendingTasks.length,
                      itemBuilder: (context, index) {
                        final task = pendingTasks[index];
                        final courseName = task.courseId == null
                            ? null
                            : courseNames[task.courseId] ?? '课程不可用';
                        return ListTile(
                          key: ValueKey(task.uid),
                          title: Text(task.summary),
                          subtitle: Text(
                            '${courseName == null ? '' : '$courseName · '}'
                            '截止 ${task.endTime}',
                          ),
                          leading: Checkbox(
                            value: false,
                            onChanged: (value) {
                              if (value == true) _complete(task);
                            },
                          ),
                          onTap: () => _editTask(task),
                        );
                      },
                    ),
    );
  }
}
