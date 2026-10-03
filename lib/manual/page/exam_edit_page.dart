import 'dart:math';

import 'package:flutter/cupertino.dart';

import '../controller/academic_controller.dart';
import '../model/academic_profile.dart';
import '../model/local_course.dart';
import '../model/local_exam.dart';

/// Adds an exam to one course using an isolated form draft.
final class ExamEditPage extends StatefulWidget {
  const ExamEditPage({
    super.key,
    required this.controller,
    required this.course,
    this.exam,
  });

  final AcademicController controller;
  final LocalCourse course;
  final LocalExam? exam;

  @override
  State<ExamEditPage> createState() => _ExamEditPageState();
}

final class _ExamEditPageState extends State<ExamEditPage> {
  final _type = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _location = TextEditingController();
  final _seat = TextEditingController();
  bool _timeUnknown = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final exam = widget.exam;
    if (exam != null) {
      _type.text = exam.type;
      _timeUnknown = exam.start == null;
      if (exam.start != null) _start.text = _formatDateTime(exam.start!);
      if (exam.end != null) _end.text = _formatDateTime(exam.end!);
      _location.text = exam.location ?? '';
      _seat.text = exam.seat ?? '';
    }
  }

  @override
  void dispose() {
    _type.dispose();
    _start.dispose();
    _end.dispose();
    _location.dispose();
    _seat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final start = _timeUnknown ? null : _parseDateTime(_start.text);
      final end = _timeUnknown ? null : _parseDateTime(_end.text);
      final exam = LocalExam(
        id: widget.exam?.id ?? _newUuid(),
        courseId: widget.course.id,
        type: _type.text.trim(),
        start: start,
        end: end,
        location: _optional(_location.text),
        seat: _optional(_seat.text),
      );
      await widget.controller.applyUpdate(
        (current) => _saveExam(current, exam, widget.exam?.id),
      );
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
          middle: Text(widget.exam == null ? '新增考试' : '编辑考试'),
          leading: CupertinoButton(
            key: const ValueKey('exam-cancel'),
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
              _field('考试类型', _type, 'exam-type', required: true),
              CupertinoListTile(
                title: const Text('时间未定'),
                trailing: CupertinoSwitch(
                  key: const ValueKey('exam-time-unknown'),
                  value: _timeUnknown,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _timeUnknown = value),
                ),
              ),
              if (!_timeUnknown) ...[
                const Text('时间格式：YYYY-MM-DD HH:mm'),
                _field('开始时间', _start, 'exam-start'),
                _field('结束时间', _end, 'exam-end'),
              ],
              _field('地点（可选）', _location, 'exam-location'),
              _field('座位（可选）', _seat, 'exam-seat'),
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Text(error,
                    style: const TextStyle(color: CupertinoColors.systemRed)),
              ],
              const SizedBox(height: 20),
              CupertinoButton.filled(
                key: const ValueKey('exam-save'),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '正在保存…' : '保存'),
              ),
            ],
          ),
        ),
      );

  Widget _field(
    String label,
    TextEditingController controller,
    String key, {
    bool required = false,
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
              placeholder: required ? '必填' : '未填写',
            ),
          ],
        ),
      );

  static AcademicProfile _saveExam(
    AcademicProfile current,
    LocalExam exam,
    String? originalId,
  ) {
    if (!current.courses.any((course) => course.id == exam.courseId)) {
      throw StateError('关联课程已不存在');
    }
    final exams = List<LocalExam>.of(current.exams);
    if (originalId == null) {
      exams.add(exam);
    } else {
      final index = exams.indexWhere((item) => item.id == originalId);
      if (index < 0) throw StateError('考试记录已不存在');
      exams[index] = exam;
    }
    return AcademicProfile(
      schemaVersion: current.schemaVersion,
      revision: current.revision,
      currentSemesterId: current.currentSemesterId,
      semesters: current.semesters,
      timeSlots: current.timeSlots,
      courses: current.courses,
      sessionRules: current.sessionRules,
      exams: exams,
      grades: current.grades,
      practiceRecords: current.practiceRecords,
    );
  }

  static DateTime _parseDateTime(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$')
        .firstMatch(value.trim());
    if (match == null) {
      throw const FormatException('请输入 YYYY-MM-DD HH:mm 格式的时间');
    }
    final parts = [for (var i = 1; i <= 5; i++) int.parse(match[i]!)];
    final result = DateTime(parts[0], parts[1], parts[2], parts[3], parts[4]);
    if (result.year != parts[0] ||
        result.month != parts[1] ||
        result.day != parts[2] ||
        result.hour != parts[3] ||
        result.minute != parts[4]) {
      throw const FormatException('请输入有效的日期和时间');
    }
    return result;
  }

  static String? _optional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _formatDateTime(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

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
