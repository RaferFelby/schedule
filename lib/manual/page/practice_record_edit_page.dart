import 'dart:math';

import 'package:flutter/cupertino.dart';

import '../data/academic_repository.dart';
import '../model/academic_profile.dart';
import '../model/practice_record.dart';

final class PracticeRecordEditPage extends StatefulWidget {
  const PracticeRecordEditPage({
    super.key,
    required this.repository,
    this.record,
  });

  final AcademicRepository repository;
  final PracticeRecord? record;

  @override
  State<PracticeRecordEditPage> createState() => _PracticeRecordEditPageState();
}

final class _PracticeRecordEditPageState extends State<PracticeRecordEditPage> {
  final _category = TextEditingController();
  final _project = TextEditingController();
  final _date = TextEditingController(text: _today());
  final _points = TextEditingController();
  final _note = TextEditingController();
  PracticeReviewStatus _status = PracticeReviewStatus.pending;
  RequirementStatus _artsStatus = RequirementStatus.unknown;
  RequirementStatus _laborStatus = RequirementStatus.unknown;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    if (record != null) {
      _category.text = record.category;
      _project.text = record.projectName;
      _date.text = _formatDate(record.date);
      _points.text = record.points.toString();
      _note.text = record.note ?? '';
      _status = record.status;
      _artsStatus = record.artsStatus;
      _laborStatus = record.laborStatus;
    }
  }

  @override
  void dispose() {
    _category.dispose();
    _project.dispose();
    _date.dispose();
    _points.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final parsedDate = _parseDate(_date.text.trim());
      final rawPoints = _points.text.trim();
      if (rawPoints.isEmpty) throw const FormatException('实践记点不能为空');
      final points = double.parse(rawPoints);
      final note = _note.text.trim();
      final record = PracticeRecord(
        id: widget.record?.id ?? _newUuid(),
        category: _category.text.trim(),
        projectName: _project.text.trim(),
        date: parsedDate,
        points: points,
        status: _status,
        note: note.isEmpty ? null : note,
        artsStatus: _artsStatus,
        laborStatus: _laborStatus,
      );
      await widget.repository.update((current) => AcademicProfile(
            schemaVersion: current.schemaVersion,
            revision: current.revision,
            currentSemesterId: current.currentSemesterId,
            semesters: current.semesters,
            timeSlots: current.timeSlots,
            courses: current.courses,
            sessionRules: current.sessionRules,
            exams: current.exams,
            grades: current.grades,
            practiceRecords: _updatedRecords(current.practiceRecords, record),
          ));
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
          previousPageTitle: '实践记录',
          middle: Text(widget.record == null ? '新增实践记录' : '编辑实践记录'),
          leading: CupertinoButton(
            key: const ValueKey('practice-cancel'),
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
              _field('类别', _category, 'practice-category'),
              _field('项目名称', _project, 'practice-project'),
              _field('日期（YYYY-MM-DD）', _date, 'practice-date'),
              _field('记点', _points, 'practice-points',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  )),
              _field('备注（可选）', _note, 'practice-note'),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('审核状态'),
              ),
              CupertinoSlidingSegmentedControl<PracticeReviewStatus>(
                key: const ValueKey('practice-status'),
                groupValue: _status,
                children: const {
                  PracticeReviewStatus.pending: Text('待审核'),
                  PracticeReviewStatus.approved: Text('通过'),
                  PracticeReviewStatus.rejected: Text('未通过'),
                },
                onValueChanged: (value) {
                  if (!_saving && value != null) {
                    setState(() => _status = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text('美育要求状态'),
              CupertinoSlidingSegmentedControl<RequirementStatus>(
                key: const ValueKey('practice-arts-status'),
                groupValue: _artsStatus,
                children: const {
                  RequirementStatus.unknown: Text('未知'),
                  RequirementStatus.notPassed: Text('未通过'),
                  RequirementStatus.passed: Text('通过'),
                },
                onValueChanged: (value) {
                  if (!_saving && value != null) {
                    setState(() => _artsStatus = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              const Text('劳育要求状态'),
              CupertinoSlidingSegmentedControl<RequirementStatus>(
                key: const ValueKey('practice-labor-status'),
                groupValue: _laborStatus,
                children: const {
                  RequirementStatus.unknown: Text('未知'),
                  RequirementStatus.notPassed: Text('未通过'),
                  RequirementStatus.passed: Text('通过'),
                },
                onValueChanged: (value) {
                  if (!_saving && value != null) {
                    setState(() => _laborStatus = value);
                  }
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(color: CupertinoColors.systemRed)),
              ],
              const SizedBox(height: 20),
              CupertinoButton.filled(
                key: const ValueKey('practice-save'),
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
    TextInputType? keyboardType,
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
              keyboardType: keyboardType,
            ),
          ],
        ),
      );

  List<PracticeRecord> _updatedRecords(
    List<PracticeRecord> records,
    PracticeRecord updated,
  ) {
    final existingId = widget.record?.id;
    if (existingId == null) return [...records, updated];
    final index = records.indexWhere((record) => record.id == existingId);
    if (index < 0) throw StateError('实践记录已不存在');
    final result = List<PracticeRecord>.of(records);
    result[index] = updated;
    return result;
  }

  static DateTime _parseDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) throw const FormatException('日期格式须为 YYYY-MM-DD');
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      throw const FormatException('日期不是有效日历日期');
    }
    return date;
  }

  static String _today() {
    final date = DateTime.now();
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

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
