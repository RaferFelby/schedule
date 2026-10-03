import 'dart:math';

import 'package:celechron/model/period.dart';
import 'package:flutter/cupertino.dart';

import '../controller/academic_controller.dart';
import '../data/local_data_error.dart';
import '../model/academic_profile.dart';
import '../model/local_course.dart';
import '../model/session_rule.dart';
import '../model/time_slot.dart';
import '../service/schedule_expander.dart';
import '../service/session_conflict_detector.dart';

/// Adds a weekly rule to one explicitly identified course.
final class SessionRuleEditPage extends StatefulWidget {
  const SessionRuleEditPage({
    super.key,
    required this.controller,
    required this.course,
    this.rule,
  });

  final AcademicController controller;
  final LocalCourse course;
  final SessionRule? rule;

  @override
  State<SessionRuleEditPage> createState() => _SessionRuleEditPageState();
}

final class _SessionRuleEditPageState extends State<SessionRuleEditPage> {
  late final _weekday = TextEditingController(
    text: '${widget.rule?.weekday ?? 1}',
  );
  late final _weeks = TextEditingController(
    text: widget.rule?.weekNumbers.join(',') ?? '1',
  );
  late final _startSlot = TextEditingController(
    text: '${widget.rule?.startSlotOrdinal ?? 1}',
  );
  late final _endSlot = TextEditingController(
    text: '${widget.rule?.endSlotOrdinal ?? 1}',
  );
  late final _location = TextEditingController(
    text: widget.rule?.location ?? '',
  );
  late final _teacher = TextEditingController(
    text: widget.rule?.teacher ?? '',
  );
  final _rangeStart = TextEditingController(text: '1');
  final _rangeEnd = TextEditingController(text: '6');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _weekday.dispose();
    _weeks.dispose();
    _startSlot.dispose();
    _endSlot.dispose();
    _location.dispose();
    _teacher.dispose();
    _rangeStart.dispose();
    _rangeEnd.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final rule = SessionRule(
        id: widget.rule?.id ?? _newUuid(),
        courseId: widget.course.id,
        weekday: int.parse(_weekday.text.trim()),
        weekNumbers: _parseWeeks(_weeks.text),
        startSlotOrdinal: int.parse(_startSlot.text.trim()),
        endSlotOrdinal: int.parse(_endSlot.text.trim()),
        location: _optional(_location.text),
        teacher: _optional(_teacher.text),
        cancelledDates: widget.rule?.cancelledDates ?? const [],
        reschedules: widget.rule?.reschedules ?? const [],
        extraOccurrences: widget.rule?.extraOccurrences ?? const [],
      );
      await widget.controller.applyUpdate(
        (current) => widget.rule == null
            ? _appendRule(current, rule)
            : _replaceRule(current, rule),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<SessionConflict> get _conflicts {
    try {
      final profile = widget.controller.profile.value;
      final semester = profile.semesters.firstWhere(
        (item) => item.id == widget.course.semesterId,
      );
      final rule = SessionRule(
        id: widget.rule?.id ?? 'draft-rule',
        courseId: widget.course.id,
        weekday: int.parse(_weekday.text.trim()),
        weekNumbers: _parseWeeks(_weeks.text),
        startSlotOrdinal: int.parse(_startSlot.text.trim()),
        endSlotOrdinal: int.parse(_endSlot.text.trim()),
        location: _optional(_location.text),
        teacher: _optional(_teacher.text),
        cancelledDates: widget.rule?.cancelledDates ?? const [],
        reschedules: widget.rule?.reschedules ?? const [],
        extraOccurrences: widget.rule?.extraOccurrences ?? const [],
      );
      final slots = profile.timeSlots.isEmpty
          ? TimeSlot.defaultTemplate()
          : profile.timeSlots;
      final proposed = ScheduleExpander.expandRule(
        semester: semester,
        course: widget.course,
        rule: rule,
        timeSlots: slots,
      );
      final coursesById = {
        for (final course in profile.courses) course.id: course,
      };
      final semestersById = {
        for (final item in profile.semesters) item.id: item,
      };
      final existing = <Period>[];
      for (final scheduledRule in profile.sessionRules) {
        if (scheduledRule.id == widget.rule?.id) continue;
        final course = coursesById[scheduledRule.courseId];
        final scheduledSemester =
            course == null ? null : semestersById[course.semesterId];
        if (course == null || scheduledSemester?.id != semester.id) continue;
        existing.addAll(ScheduleExpander.expandRule(
          semester: semester,
          course: course,
          rule: scheduledRule,
          timeSlots: slots,
        ));
      }
      final conflicts = SessionConflictDetector.findConflicts(
        proposed: proposed,
        existing: existing,
      );
      return conflicts;
    } catch (error) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          previousPageTitle: '课程详情',
          middle: Text(widget.rule == null ? '新增上课安排' : '编辑上课安排'),
          leading: CupertinoButton(
            key: const ValueKey('rule-cancel'),
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
              const SizedBox(height: 16),
              _field('星期（1=周一，7=周日）', _weekday, 'rule-weekday',
                  onChanged: _refreshConflicts),
              _field(
                '上课周次（逗号分隔）',
                _weeks,
                'rule-weeks',
                numeric: false,
                onChanged: _refreshConflicts,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _weekButton('全选', 'rule-weeks-all', _allWeeks),
                  _weekButton('单周', 'rule-weeks-odd', () => _parityWeeks(1)),
                  _weekButton('双周', 'rule-weeks-even', () => _parityWeeks(0)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                      child: _field('范围起始周', _rangeStart, 'rule-range-start')),
                  const SizedBox(width: 12),
                  Expanded(child: _field('范围结束周', _rangeEnd, 'rule-range-end')),
                ],
              ),
              CupertinoButton(
                key: const ValueKey('rule-weeks-range'),
                padding: EdgeInsets.zero,
                onPressed: _selectRange,
                child: const Text('应用周次范围'),
              ),
              _field('起始节次', _startSlot, 'rule-start-slot',
                  onChanged: _refreshConflicts),
              _field('结束节次', _endSlot, 'rule-end-slot',
                  onChanged: _refreshConflicts),
              _field('地点（可选）', _location, 'rule-location', numeric: false),
              _field('本次安排教师（可选）', _teacher, 'rule-teacher', numeric: false),
              if (_conflicts case final conflicts when conflicts.isNotEmpty)
                Container(
                  key: const ValueKey('session-conflicts'),
                  padding: const EdgeInsets.all(10),
                  color: CupertinoColors.systemYellow.withValues(alpha: 0.18),
                  child: Text(
                    '时间冲突提醒：与'
                    '${conflicts.map((item) => item.scheduled.summary).toSet().join('、')}'
                    '安排重叠。仍可保存。',
                    style: const TextStyle(color: CupertinoColors.systemOrange),
                  ),
                ),
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: const TextStyle(color: CupertinoColors.systemRed),
                ),
              ],
              const SizedBox(height: 20),
              CupertinoButton.filled(
                key: const ValueKey('rule-save'),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '正在保存…' : '保存'),
              ),
            ],
          ),
        ),
      );

  Widget _weekButton(String label, String key, VoidCallback onPressed) =>
      CupertinoButton(
        key: ValueKey(key),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        onPressed: onPressed,
        child: Text(label),
      );

  int get _semesterWeekCount {
    final profile = widget.controller.profile.value;
    final semester = profile.semesters.where(
      (item) => item.id == widget.course.semesterId,
    );
    if (semester.length != 1) return 1;
    final days =
        semester.single.endDate.difference(semester.single.weekOneStart).inDays;
    return days < 0 ? 1 : days ~/ 7 + 1;
  }

  void _allWeeks() =>
      _setWeeks(List.generate(_semesterWeekCount, (i) => i + 1));

  void _parityWeeks(int remainder) {
    final selected = _parseWeeks(_weeks.text);
    final scope = selected.length > 1
        ? selected
        : List.generate(_semesterWeekCount, (i) => i + 1);
    _setWeeks(scope.where((week) => week % 2 == remainder).toList());
  }

  void _selectRange() {
    try {
      final start = int.parse(_rangeStart.text.trim());
      final end = int.parse(_rangeEnd.text.trim());
      if (start < 1 || end < start || end > _semesterWeekCount) {
        throw const FormatException('周次范围超出当前学期');
      }
      _setWeeks(List.generate(end - start + 1, (i) => start + i));
      setState(() => _error = null);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  void _setWeeks(List<int> weeks) {
    _weeks.text = weeks.join(',');
    setState(() => _error = null);
  }

  Widget _field(
    String label,
    TextEditingController controller,
    String key, {
    bool numeric = true,
    VoidCallback? onChanged,
  }) =>
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
              keyboardType: numeric ? TextInputType.number : TextInputType.text,
              onChanged: onChanged == null ? null : (_) => onChanged(),
            ),
          ],
        ),
      );

  void _refreshConflicts() => setState(() {});

  static List<int> _parseWeeks(String value) {
    final weeks = value.split(',').map((part) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) throw const FormatException('周次不能为空');
      return int.parse(trimmed);
    }).toList();
    if (weeks.isEmpty) throw const FormatException('周次不能为空');
    return weeks;
  }

  static String? _optional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static AcademicProfile _replaceRule(
    AcademicProfile current,
    SessionRule rule,
  ) {
    final index = current.sessionRules.indexWhere((item) => item.id == rule.id);
    if (index < 0) throw StateError('上课安排已不存在');
    final rules = List<SessionRule>.of(current.sessionRules)..[index] = rule;
    return _withRules(current, rules);
  }

  static AcademicProfile _appendRule(
    AcademicProfile current,
    SessionRule rule,
  ) {
    if (!current.courses.any((course) => course.id == rule.courseId)) {
      throw StateError('关联课程已不存在');
    }
    final slots = current.timeSlots.isEmpty
        ? TimeSlot.defaultTemplate()
        : current.timeSlots;
    final ordinals = slots.map((slot) => slot.ordinal).toSet();
    for (var ordinal = rule.startSlotOrdinal;
        ordinal <= rule.endSlotOrdinal;
        ordinal++) {
      if (!ordinals.contains(ordinal)) {
        throw LocalDataValidationError('规则引用了不存在的第 $ordinal 节');
      }
    }
    return _withRules(current, [...current.sessionRules, rule]);
  }

  static AcademicProfile _withRules(
    AcademicProfile current,
    List<SessionRule> rules,
  ) =>
      AcademicProfile(
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

  static String _newUuid() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final value =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
}
