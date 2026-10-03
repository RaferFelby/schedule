import 'package:flutter/cupertino.dart';

import '../controller/academic_controller.dart';
import '../model/academic_profile.dart';
import '../model/local_course.dart';
import '../model/session_reschedule.dart';
import '../model/session_rule.dart';

/// Edits the target date and time for one stable occurrence identity.
final class SessionRescheduleEditPage extends StatefulWidget {
  const SessionRescheduleEditPage({
    super.key,
    required this.controller,
    required this.course,
    required this.rule,
    required this.originalDate,
    this.existing,
  });

  final AcademicController controller;
  final LocalCourse course;
  final SessionRule rule;
  final DateTime originalDate;
  final SessionReschedule? existing;

  @override
  State<SessionRescheduleEditPage> createState() =>
      _SessionRescheduleEditPageState();
}

final class _SessionRescheduleEditPageState
    extends State<SessionRescheduleEditPage> {
  late final _date = TextEditingController(
    text: _dateText(widget.existing?.targetDate ?? widget.originalDate),
  );
  late final _start = TextEditingController(
    text: _timeText(widget.existing?.startMinute ?? 480),
  );
  late final _end = TextEditingController(
    text: _timeText(widget.existing?.endMinute ?? 525),
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _date.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final target = DateTime.parse(_date.text.trim());
      if (_dateText(target) != _date.text.trim()) {
        throw const FormatException('日期格式应为 YYYY-MM-DD');
      }
      final reschedule = SessionReschedule(
        originalDate: widget.originalDate,
        targetDate: target,
        startMinute: _minute(_start.text),
        endMinute: _minute(_end.text),
      );
      await widget.controller.applyUpdate((current) {
        final index = current.sessionRules.indexWhere(
          (item) => item.id == widget.rule.id,
        );
        if (index < 0) throw StateError('上课安排已不存在');
        final rule = current.sessionRules[index];
        final overrides = rule.reschedules
            .where((item) => !_sameDate(item.originalDate, widget.originalDate))
            .toList()
          ..add(reschedule);
        final rules = List<SessionRule>.of(current.sessionRules)
          ..[index] = SessionRule(
            id: rule.id,
            courseId: rule.courseId,
            weekday: rule.weekday,
            weekNumbers: rule.weekNumbers,
            startSlotOrdinal: rule.startSlotOrdinal,
            endSlotOrdinal: rule.endSlotOrdinal,
            location: rule.location,
            teacher: rule.teacher,
            cancelledDates: rule.cancelledDates,
            reschedules: overrides,
            extraOccurrences: rule.extraOccurrences,
          );
        return AcademicProfile(
          schemaVersion: current.schemaVersion,
          revision: current.revision,
          currentSemesterId: current.currentSemesterId,
          semesters: current.semesters,
          timeSlots: current.timeSlots,
          courses: current.courses,
          sessionRules: rules,
          exams: current.exams,
          grades: current.grades,
          practiceRecords: current.practiceRecords,
        );
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          previousPageTitle: '课程详情',
          middle: const Text('调课'),
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed:
                _saving ? null : () => Navigator.of(context).maybePop(false),
            child: const Text('取消'),
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('课程：${widget.course.name}'),
              Text('原上课日期：${_dateText(widget.originalDate)}'),
              _field('调课日期（YYYY-MM-DD）', _date, 'reschedule-date'),
              _field('开始时间（HH:mm）', _start, 'reschedule-start'),
              _field('结束时间（HH:mm）', _end, 'reschedule-end'),
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Text(error,
                    style: const TextStyle(color: CupertinoColors.systemRed)),
              ],
              const SizedBox(height: 20),
              CupertinoButton.filled(
                key: const ValueKey('reschedule-save'),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '正在保存…' : '保存调课'),
              ),
            ],
          ),
        ),
      );

  Widget _field(String label, TextEditingController controller, String key) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 6),
            CupertinoTextField(
              key: ValueKey(key),
              controller: controller,
              keyboardType: TextInputType.datetime,
            ),
          ],
        ),
      );

  static int _minute(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) throw const FormatException('时间格式应为 HH:mm');
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) throw const FormatException('时间无效');
    return hour * 60 + minute;
  }

  static String _dateText(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _timeText(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:'
      '${(minute % 60).toString().padLeft(2, '0')}';

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
