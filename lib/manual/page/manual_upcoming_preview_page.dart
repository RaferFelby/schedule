import 'package:flutter/material.dart';

import '../../model/period.dart';
import '../../model/task.dart';
import '../service/local_upcoming_schedule_planner.dart';
import '../data/academic_repository.dart';
import '../model/manual_user_preferences.dart';

/// Read-only upcoming schedule preview sourced from manual local periods.
final class ManualUpcomingPreviewPage extends StatefulWidget {
  const ManualUpcomingPreviewPage({
    super.key,
    required this.repository,
    this.preferences = const ManualUserPreferences(),
    this.taskLoader,
    this.onOpenSemesters,
    this.onOpenTasks,
    this.now,
    this.horizon = const Duration(days: 7),
  });

  final AcademicRepository repository;
  final ManualUserPreferences preferences;
  final Future<List<Task>> Function()? taskLoader;
  final VoidCallback? onOpenSemesters;
  final VoidCallback? onOpenTasks;
  final DateTime Function()? now;
  final Duration horizon;

  @override
  State<ManualUpcomingPreviewPage> createState() =>
      _ManualUpcomingPreviewPageState();
}

final class _ManualUpcomingPreviewPageState
    extends State<ManualUpcomingPreviewPage> {
  List<Period> _periods = const [];
  List<Task> _tasks = const [];
  List<Period> _assignments = const [];
  final _planner = const LocalUpcomingSchedulePlanner();
  bool _loading = true;
  String? _error;
  bool _hasSemesters = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant ManualUpcomingPreviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences != widget.preferences) _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await widget.repository.read();
      final periods = await _planner.readPeriods(widget.repository);
      final tasks = await (widget.taskLoader?.call() ?? Future.value(<Task>[]));
      final now = (widget.now ?? DateTime.now)();
      final until = now.add(widget.horizon);
      final upcoming = periods
          .where((period) =>
              period.endTime.isAfter(now) && !period.startTime.isAfter(until))
          .toList()
        ..sort((left, right) {
          final byStart = left.startTime.compareTo(right.startTime);
          return byStart != 0 ? byStart : left.uid.compareTo(right.uid);
        });
      final occupied = periods
          .where((period) =>
              period.endTime.isAfter(now) && period.startTime.isBefore(until))
          .toList(growable: false);
      final available = _availablePeriods(
        now,
        until,
        widget.preferences.availableWindows,
      );
      final plan = _planner.planTasks(
        workTime: Duration(minutes: widget.preferences.workMinutes),
        restTime: Duration(minutes: widget.preferences.restMinutes),
        tasks: tasks,
        availablePeriods: available,
        occupiedPeriods: occupied,
      );
      if (mounted) {
        setState(() {
          _periods = upcoming;
          _hasSemesters = profile.semesters.isNotEmpty;
          _tasks = tasks
              .where((task) =>
                  task.type == TaskType.deadline &&
                  task.status != TaskStatus.completed &&
                  task.status != TaskStatus.deleted)
              .toList(growable: false);
          _assignments = plan.assignSet;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static List<Period> _availablePeriods(
    DateTime from,
    DateTime until,
    List<List<int>> windows,
  ) {
    final periods = <Period>[];
    for (var day = DateTime(from.year, from.month, from.day);
        day.isBefore(DateTime(until.year, until.month, until.day + 1));
        day = day.add(const Duration(days: 1))) {
      for (final window in windows) {
        final midnight = DateTime(day.year, day.month, day.day);
        final windowStart = midnight.add(Duration(minutes: window[0]));
        final windowEnd = midnight.add(Duration(minutes: window[1]));
        final start = windowStart.isAfter(from) ? windowStart : from;
        final end = windowEnd.isBefore(until) ? windowEnd : until;
        if (!end.isAfter(start)) continue;
        periods.add(
            Period(type: PeriodType.virtual, startTime: start, endTime: end));
      }
    }
    return periods;
  }

  String _dateTime(DateTime value) {
    final date = '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    final time = '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('接下来'),
          actions: [
            IconButton(
              tooltip: '刷新日程',
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text('读取本地日程失败：$_error'))
                : _periods.isEmpty && _tasks.isEmpty && _hasSemesters
                    ? const Center(child: Text('近期没有课程、考试或待办任务'))
                    : ListView(
                        children: [
                          if (!_hasSemesters)
                            Card(
                              key: const ValueKey('first-use-empty-academics'),
                              margin: const EdgeInsets.all(16),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '先创建学期，也可以稍后再建',
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text('创建学期后可以管理课程和课表；现在也可以跳过，直接使用普通任务。'),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        FilledButton(
                                          key: const ValueKey('first-use-create-semester'),
                                          onPressed: widget.onOpenSemesters,
                                          child: const Text('创建学期'),
                                        ),
                                        TextButton(
                                          key: const ValueKey('first-use-skip-to-tasks'),
                                          onPressed: widget.onOpenTasks,
                                          child: const Text('跳过，先添加任务'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (_periods.isEmpty && _tasks.isEmpty && !_hasSemesters)
                            const ListTile(title: Text('还没有任务或日程')),
                          if (_assignments.isNotEmpty) ...[
                            ListTile(
                              title: Text(
                                  '建议安排（${widget.preferences.workMinutes} 分钟专注 / ${widget.preferences.restMinutes} 分钟休息）'),
                            ),
                            ..._assignments.map((period) => ListTile(
                                  key: ValueKey('plan-${period.uid}'),
                                  leading: const Icon(Icons.auto_awesome),
                                  title: Text(period.summary),
                                  subtitle: Text(
                                    '${_dateTime(period.startTime)}–'
                                    '${_dateTime(period.endTime).substring(11)}',
                                  ),
                                )),
                          ],
                          if (_tasks.isNotEmpty) ...[
                            const ListTile(title: Text('待办任务')),
                            ..._tasks.map((task) => ListTile(
                                  key: ValueKey('task-${task.uid}'),
                                  leading:
                                      const Icon(Icons.assignment_outlined),
                                  title: Text(task.summary),
                                  subtitle: Text(
                                    '截止 ${_dateTime(task.endTime)}'
                                    '${task.isTimeEstimated ? ' · 预计 ${task.timeNeeded.inMinutes} 分钟' : ' · 未估算用时'}',
                                  ),
                                )),
                          ],
                          if (_periods.isNotEmpty) ...[
                            const ListTile(title: Text('近期课程和考试')),
                            ..._periods.map((period) {
                              final location = period.location.trim();
                              return ListTile(
                                key: ValueKey(period.uid),
                                title: Text(period.summary),
                                subtitle: Text(
                                  '${_dateTime(period.startTime)}–'
                                  '${_dateTime(period.endTime).substring(11)}'
                                  '${location.isEmpty ? '' : ' · $location'}',
                                ),
                                leading: Icon(
                                  period.type == PeriodType.test
                                      ? Icons.assignment
                                      : Icons.class_outlined,
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
      );
}
