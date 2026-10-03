import 'dart:math';

import 'package:flutter/cupertino.dart';

import '../controller/academic_controller.dart';
import '../data/local_data_error.dart';
import '../model/academic_profile.dart';
import '../model/local_course.dart';
import '../model/local_semester.dart';
import '../model/session_extra_occurrence.dart';
import '../model/session_rule.dart';
import '../model/time_slot.dart';

/// Adds one meeting on an explicit date and section range.
final class SessionExtraOccurrenceEditPage extends StatefulWidget {
  const SessionExtraOccurrenceEditPage({
    super.key,
    required this.controller,
    required this.course,
    required this.semester,
    required this.rule,
  });

  final AcademicController controller;
  final LocalCourse course;
  final LocalSemester semester;
  final SessionRule rule;

  @override
  State<SessionExtraOccurrenceEditPage> createState() =>
      _SessionExtraOccurrenceEditPageState();
}

final class _SessionExtraOccurrenceEditPageState
    extends State<SessionExtraOccurrenceEditPage> {
  final _date = TextEditingController(text: '2026-09-26');
  final _startSlot = TextEditingController(text: '1');
  final _endSlot = TextEditingController(text: '1');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _date.dispose();
    _startSlot.dispose();
    _endSlot.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final dateText = _date.text.trim();
      final date = DateTime.parse(dateText);
      if (_dateKey(date) != dateText ||
          date.isBefore(widget.semester.startDate) ||
          date.isAfter(widget.semester.endDate)) {
        throw const FormatException('补课日期格式无效或不在当前学期内');
      }
      final extra = SessionExtraOccurrence(
        id: _newId(),
        date: date,
        startSlotOrdinal: int.parse(_startSlot.text.trim()),
        endSlotOrdinal: int.parse(_endSlot.text.trim()),
      );
      await widget.controller.applyUpdate((current) {
        final slots = current.timeSlots.isEmpty
            ? TimeSlot.defaultTemplate()
            : current.timeSlots;
        final ordinals = slots.map((slot) => slot.ordinal).toSet();
        for (var ordinal = extra.startSlotOrdinal;
            ordinal <= extra.endSlotOrdinal;
            ordinal++) {
          if (!ordinals.contains(ordinal)) {
            throw LocalDataValidationError('补课引用了不存在的第 $ordinal 节');
          }
        }
        final index = current.sessionRules.indexWhere(
          (item) => item.id == widget.rule.id,
        );
        if (index < 0) throw StateError('上课安排已不存在');
        final rule = current.sessionRules[index];
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
            reschedules: rule.reschedules,
            extraOccurrences: [...rule.extraOccurrences, extra],
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
          middle: const Text('新增补课'),
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
              _field('日期（YYYY-MM-DD）', _date, 'extra-date'),
              _field('起始节次', _startSlot, 'extra-start-slot'),
              _field('结束节次', _endSlot, 'extra-end-slot'),
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Text(error,
                    style: const TextStyle(color: CupertinoColors.systemRed)),
              ],
              const SizedBox(height: 20),
              CupertinoButton.filled(
                key: const ValueKey('extra-save'),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '正在保存…' : '保存补课'),
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
              keyboardType: TextInputType.text,
            ),
          ],
        ),
      );

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _newId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final value =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-${value.substring(20)}';
  }
}
