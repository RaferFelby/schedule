import 'dart:math';

import 'package:flutter/cupertino.dart';

import '../controller/academic_controller.dart';
import '../model/academic_profile.dart';
import '../model/grade_record.dart';
import '../model/local_course.dart';
import '../service/grade_calculator.dart';

/// Adds one grade to a course using private form draft fields.
final class GradeEditPage extends StatefulWidget {
  const GradeEditPage({
    super.key,
    required this.controller,
    required this.course,
    this.record,
  });

  final AcademicController controller;
  final LocalCourse course;
  final GradeRecord? record;

  @override
  State<GradeEditPage> createState() => _GradeEditPageState();
}

final class _GradeEditPageState extends State<GradeEditPage> {
  final _value = TextEditingController();
  bool _notRecorded = true;
  LocalGradingMethod _method = LocalGradingMethod.percentage;
  bool _countsTowardGpa = true;
  bool _countsTowardCredits = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    if (record != null) {
      _notRecorded = record.status == LocalGradeStatus.notRecorded;
      _method = record.method;
      _countsTowardGpa = record.countsTowardGpa;
      _countsTowardCredits = record.countsTowardCredits;
      _value.text = switch (record.method) {
        LocalGradingMethod.percentage => record.rawScore?.toString() ?? '',
        LocalGradingMethod.letter ||
        LocalGradingMethod.passFail =>
          record.gradeLabel ?? '',
        LocalGradingMethod.directGpa => record.gradePoint?.toString() ?? '',
      };
    }
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final record = _createRecord();
      GradeCalculator.calculate(record: record, course: widget.course);
      await widget.controller.applyUpdate(
        (current) {
          if (!current.courses.any((course) => course.id == record.courseId)) {
            throw StateError('关联课程已不存在');
          }
          final grades = List<GradeRecord>.of(current.grades);
          final existingId = widget.record?.id;
          if (existingId == null) {
            if (grades.any((grade) => grade.courseId == record.courseId)) {
              throw StateError('该课程已有成绩记录');
            }
            grades.add(record);
          } else {
            final index = grades.indexWhere((grade) => grade.id == existingId);
            if (index < 0) throw StateError('成绩记录已不存在');
            grades[index] = record;
          }
          return AcademicProfile(
            schemaVersion: current.schemaVersion,
            revision: current.revision,
            currentSemesterId: current.currentSemesterId,
            semesters: current.semesters,
            timeSlots: current.timeSlots,
            courses: current.courses,
            sessionRules: current.sessionRules,
            exams: current.exams,
            grades: grades,
            practiceRecords: current.practiceRecords,
          );
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  GradeRecord _createRecord() {
    final status =
        _notRecorded ? LocalGradeStatus.notRecorded : LocalGradeStatus.recorded;
    final parsed = _notRecorded ? null : _parseValue();
    return GradeRecord(
      id: widget.record?.id ?? _newUuid(),
      courseId: widget.course.id,
      status: status,
      method: _method,
      rawScore:
          _method == LocalGradingMethod.percentage ? parsed as double? : null,
      gradeLabel: switch (_method) {
        LocalGradingMethod.letter => parsed as String?,
        LocalGradingMethod.passFail => parsed as String?,
        _ => null,
      },
      gradePoint:
          _method == LocalGradingMethod.directGpa ? parsed as double? : null,
      calculationRuleId: null,
      isMajor: widget.record?.isMajor ?? widget.course.isMajor,
      countsTowardGpa: _countsTowardGpa,
      countsTowardCredits: _countsTowardCredits,
    );
  }

  Object? _parseValue() {
    final value = _value.text.trim();
    switch (_method) {
      case LocalGradingMethod.percentage:
      case LocalGradingMethod.directGpa:
        if (value.isEmpty) throw const FormatException('成绩不能为空');
        final number = double.parse(value);
        if (!number.isFinite) throw const FormatException('成绩必须是有限数值');
        return number;
      case LocalGradingMethod.letter:
        if (value.isEmpty) throw const FormatException('等级不能为空');
        return value;
      case LocalGradingMethod.passFail:
        return value.isEmpty ? '合格' : value;
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          previousPageTitle: '课程详情',
          middle: Text(widget.record == null ? '新增成绩' : '编辑成绩'),
          leading: CupertinoButton(
            key: const ValueKey('grade-cancel'),
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
              CupertinoListTile(
                title: const Text('成绩尚未录入'),
                trailing: CupertinoSwitch(
                  key: const ValueKey('grade-not-recorded'),
                  value: _notRecorded,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _notRecorded = value),
                ),
              ),
              if (!_notRecorded) ...[
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('计分方式'),
                ),
                CupertinoSlidingSegmentedControl<LocalGradingMethod>(
                  key: const ValueKey('grade-method'),
                  groupValue: _method,
                  children: const {
                    LocalGradingMethod.percentage: Text('百分制'),
                    LocalGradingMethod.letter: Text('等级'),
                    LocalGradingMethod.passFail: Text('通过'),
                    LocalGradingMethod.directGpa: Text('绩点'),
                  },
                  onValueChanged: (method) {
                    if (method != null) {
                      setState(() {
                        _method = method;
                        _value.clear();
                      });
                    }
                  },
                ),
                const SizedBox(height: 14),
                _gradeInput(),
                CupertinoListTile(
                  title: const Text('计入 GPA'),
                  trailing: CupertinoSwitch(
                    key: const ValueKey('grade-count-gpa'),
                    value: _countsTowardGpa,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _countsTowardGpa = value),
                  ),
                ),
                CupertinoListTile(
                  title: const Text('计入学分'),
                  trailing: CupertinoSwitch(
                    key: const ValueKey('grade-count-credits'),
                    value: _countsTowardCredits,
                    onChanged: _saving
                        ? null
                        : (value) =>
                            setState(() => _countsTowardCredits = value),
                  ),
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Text(error,
                    style: const TextStyle(color: CupertinoColors.systemRed)),
              ],
              const SizedBox(height: 20),
              CupertinoButton.filled(
                key: const ValueKey('grade-save'),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '正在保存…' : '保存'),
              ),
            ],
          ),
        ),
      );

  Widget _gradeInput() {
    if (_method == LocalGradingMethod.passFail) {
      return CupertinoSlidingSegmentedControl<String>(
        key: const ValueKey('grade-pass-result'),
        groupValue: _value.text.isEmpty ? '合格' : _value.text,
        children: const {
          '合格': Text('合格'),
          '不合格': Text('不合格'),
        },
        onValueChanged: (value) {
          if (value != null) setState(() => _value.text = value);
        },
      );
    }
    final percentage = _method == LocalGradingMethod.percentage;
    final directGpa = _method == LocalGradingMethod.directGpa;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(percentage
            ? '百分制成绩（0–100）'
            : directGpa
                ? '手填绩点'
                : '等级/结果'),
        const SizedBox(height: 6),
        CupertinoTextField(
          key: const ValueKey('grade-value'),
          controller: _value,
          placeholder: percentage
              ? '如 89.5'
              : directGpa
                  ? '如 4.0'
                  : '如 A-、优秀',
          keyboardType: percentage || directGpa
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
        ),
      ],
    );
  }

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
