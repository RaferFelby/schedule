import 'package:celechron/model/period.dart';
import 'package:flutter/material.dart';

import '../data/academic_repository.dart';
import '../model/local_semester.dart';
import '../model/time_slot.dart';
import '../service/schedule_expander.dart';

/// A local timetable grid driven by explicit semester weeks and time slots.
final class ManualCourseSchedulePage extends StatefulWidget {
  const ManualCourseSchedulePage({super.key, required this.repository});

  final AcademicRepository repository;

  @override
  State<ManualCourseSchedulePage> createState() =>
      _ManualCourseSchedulePageState();
}

final class _ManualCourseSchedulePageState
    extends State<ManualCourseSchedulePage> {
  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];
  bool _loading = true;
  String? _error;
  List<LocalSemester> _semesters = const [];
  List<TimeSlot> _slots = const [];
  List<Period> _periods = const [];
  String? _semesterId;
  int _selectedWeek = 1;

  LocalSemester? get _semester {
    for (final semester in _semesters) {
      if (semester.id == _semesterId) return semester;
    }
    return _semesters.isEmpty ? null : _semesters.first;
  }

  int get _weekCount {
    final semester = _semester;
    if (semester == null) return 0;
    final difference =
        semester.endDate.difference(semester.weekOneStart).inDays;
    return difference < 0 ? 0 : difference ~/ 7 + 1;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await widget.repository.read();
      final semesters = profile.semesters;
      final slots = profile.timeSlots.isEmpty
          ? TimeSlot.defaultTemplate()
          : profile.timeSlots;
      final byId = {for (final course in profile.courses) course.id: course};
      final semestersById = {for (final item in semesters) item.id: item};
      final periods = <Period>[];
      for (final rule in profile.sessionRules) {
        final course = byId[rule.courseId];
        final semester =
            course == null ? null : semestersById[course.semesterId];
        if (course == null || semester == null) continue;
        periods.addAll(ScheduleExpander.expandRule(
          semester: semester,
          course: course,
          rule: rule,
          timeSlots: slots,
        ));
      }
      periods.sort(comparePeriod);
      if (!mounted) return;
      setState(() {
        _semesters = semesters;
        _slots = slots;
        _periods = List.unmodifiable(periods);
        _semesterId =
            semesters.any((item) => item.id == profile.currentSemesterId)
                ? profile.currentSemesterId
                : semesters.isEmpty
                    ? null
                    : semesters.first.id;
        _selectedWeek = 1;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Period> _periodsFor(int weekday, int ordinal) {
    final semester = _semester;
    if (semester == null) return const [];
    return _periods.where((period) {
      final startDate = DateTime(
        period.startTime.year,
        period.startTime.month,
        period.startTime.day,
      );
      final week = startDate.difference(semester.weekOneStart).inDays ~/ 7 + 1;
      final slot = _slots.cast<TimeSlot?>().firstWhere(
            (item) =>
                item != null &&
                item.startMinute <=
                    period.startTime.hour * 60 + period.startTime.minute &&
                item.endMinute >
                    period.startTime.hour * 60 + period.startTime.minute,
            orElse: () => null,
          );
      return week == _selectedWeek &&
          period.startTime.weekday == weekday &&
          slot?.ordinal == ordinal;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final semester = _semester;
    return Scaffold(
      appBar: AppBar(
        title: Text(semester?.name ?? '课表'),
        actions: [
          IconButton(
            tooltip: '刷新课表',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('读取课表失败：$_error'))
              : semester == null
                  ? const Center(child: Text('尚未添加学期'))
                  : ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            '${semester.name} · 共 $_weekCount 周',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              const Text('周次'),
                              const SizedBox(width: 12),
                              DropdownButton<int>(
                                key: const ValueKey('schedule-week-picker'),
                                value: _selectedWeek <= _weekCount
                                    ? _selectedWeek
                                    : 1,
                                items: [
                                  for (var week = 1; week <= _weekCount; week++)
                                    DropdownMenuItem(
                                      key: ValueKey('schedule-week-$week'),
                                      value: week,
                                      child: Text('第 $week 周'),
                                    ),
                                ],
                                onChanged: (week) {
                                  if (week != null) {
                                    setState(() => _selectedWeek = week);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        if (_slots.isEmpty)
                          const ListTile(title: Text('尚未配置节次'))
                        else
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: 850,
                              child: Table(
                                border: TableBorder.all(
                                  color: Theme.of(context).dividerColor,
                                ),
                                columnWidths: const {
                                  0: FixedColumnWidth(70),
                                },
                                children: [
                                  TableRow(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                    ),
                                    children: [
                                      _cell('节次'),
                                      ..._weekdayLabels.map(_cell),
                                    ],
                                  ),
                                  for (final slot in _slots)
                                    TableRow(children: [
                                      _cell(
                                          '${slot.ordinal}\n${_time(slot.startMinute)}'),
                                      for (var day = 1; day <= 7; day++)
                                        _scheduleCell(
                                            _periodsFor(day, slot.ordinal)),
                                    ]),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
    );
  }

  Widget _scheduleCell(List<Period> periods) => Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.all(3),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final period in periods)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(children: [
                  Text(period.summary,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11)),
                  if (period.description.isNotEmpty &&
                      period.description != period.summary)
                    Text(period.description,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 10)),
                  if (period.location.isNotEmpty)
                    Text(period.location,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 10)),
                ]),
              ),
          ],
        ),
      );

  Widget _cell(String value) => Container(
        constraints: const BoxConstraints(minHeight: 36),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(3),
        child: Text(value, textAlign: TextAlign.center),
      );

  static String _time(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
}
