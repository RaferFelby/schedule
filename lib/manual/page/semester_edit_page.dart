import 'dart:math';

import 'package:flutter/cupertino.dart';

import '../controller/academic_controller.dart';
import '../data/local_data_error.dart';
import '../model/academic_profile.dart';
import '../model/local_semester.dart';

/// Creates a semester using an isolated form draft.
final class SemesterEditPage extends StatefulWidget {
  const SemesterEditPage({
    super.key,
    required this.controller,
    this.semester,
  });

  final AcademicController controller;
  final LocalSemester? semester;

  @override
  State<SemesterEditPage> createState() => _SemesterEditPageState();
}

final class _SemesterEditPageState extends State<SemesterEditPage> {
  final _name = TextEditingController();
  final _startDate = TextEditingController();
  final _endDate = TextEditingController();
  final _weekOneStart = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final semester = widget.semester;
    if (semester != null) {
      _name.text = semester.name;
      _startDate.text = _formatDate(semester.startDate);
      _endDate.text = _formatDate(semester.endDate);
      _weekOneStart.text = _formatDate(semester.weekOneStart);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _startDate.dispose();
    _endDate.dispose();
    _weekOneStart.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final semester = LocalSemester(
        id: widget.semester?.id ?? _newUuid(),
        name: _name.text.trim(),
        startDate: _parseDate(_startDate.text, '开始日期'),
        endDate: _parseDate(_endDate.text, '结束日期'),
        weekOneStart: _parseDate(_weekOneStart.text, '第一周周一'),
        timeZone: widget.semester?.timeZone ?? 'Asia/Shanghai',
      );
      await widget.controller.applyUpdate(
        (current) => _saveSemester(current, semester, widget.semester?.id),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        previousPageTitle: '学期',
        middle: Text(widget.semester == null ? '新增学期' : '编辑学期'),
        leading: CupertinoButton(
          key: const ValueKey('semester-cancel'),
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
            const Text('学期名称'),
            const SizedBox(height: 6),
            CupertinoTextField(
              key: const ValueKey('semester-name'),
              controller: _name,
              placeholder: '例如：暑期班',
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            _dateInput('开始日期', _startDate, 'semester-start-date'),
            const SizedBox(height: 16),
            _dateInput('结束日期', _endDate, 'semester-end-date'),
            const SizedBox(height: 16),
            _dateInput('第一周周一', _weekOneStart, 'semester-week-one'),
            const SizedBox(height: 8),
            const Text('日期格式：YYYY-MM-DD；第一周起点必须是周一。'),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Text(
                error,
                style: const TextStyle(color: CupertinoColors.systemRed),
              ),
            ],
            const SizedBox(height: 20),
            CupertinoButton.filled(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '正在保存…' : '保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateInput(
      String label, TextEditingController controller, String key) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 6),
        CupertinoTextField(
          key: ValueKey(key),
          controller: controller,
          placeholder: 'YYYY-MM-DD',
          keyboardType: TextInputType.datetime,
          textInputAction: TextInputAction.next,
        ),
      ],
    );
  }

  static DateTime _parseDate(String value, String label) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) {
      throw FormatException('$label 格式必须为 YYYY-MM-DD');
    }
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      throw FormatException('$label 不是有效日期');
    }
    return date;
  }

  static AcademicProfile _saveSemester(
    AcademicProfile current,
    LocalSemester semester,
    String? originalId,
  ) {
    final semesters = [...current.semesters];
    if (originalId == null) {
      semesters.add(semester);
    } else {
      final index = semesters.indexWhere((value) => value.id == originalId);
      if (index < 0) {
        throw const LocalDataValidationError('要编辑的学期已不存在');
      }
      semesters[index] = semester;
    }
    return AcademicProfile(
      schemaVersion: current.schemaVersion,
      revision: current.revision,
      currentSemesterId: current.currentSemesterId,
      semesters: semesters,
      timeSlots: current.timeSlots,
      courses: current.courses,
      sessionRules: current.sessionRules,
      exams: current.exams,
      grades: current.grades,
      practiceRecords: current.practiceRecords,
    );
  }

  static String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _newUuid() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
}
