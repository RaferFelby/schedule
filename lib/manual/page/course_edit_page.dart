import 'dart:math';

import 'package:flutter/cupertino.dart';

import '../controller/academic_controller.dart';
import '../model/academic_profile.dart';
import '../model/local_course.dart';
import '../model/local_semester.dart';
import '../model/retake_selection_strategy.dart';

/// Adds one course to a fixed semester using private form draft fields.
final class CourseEditPage extends StatefulWidget {
  const CourseEditPage({
    super.key,
    required this.controller,
    required this.semester,
    this.course,
  });

  final AcademicController controller;
  final LocalSemester semester;
  final LocalCourse? course;

  @override
  State<CourseEditPage> createState() => _CourseEditPageState();
}

final class _CourseEditPageState extends State<CourseEditPage> {
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _credits = TextEditingController();
  final _gpaWeight = TextEditingController(text: '1');
  final _teacher = TextEditingController();
  bool _isMajor = false;
  String? _retakeGroupId;
  RetakeSelectionStrategy _retakeStrategy = RetakeSelectionStrategy.highestGpa;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final course = widget.course;
    if (course != null) {
      _name.text = course.name;
      _number.text = course.courseNumber ?? '';
      _credits.text = course.credits?.toString() ?? '';
      _gpaWeight.text = course.gpaWeight.toString();
      _teacher.text = course.teacher ?? '';
      _isMajor = course.isMajor;
      _retakeGroupId = course.retakeGroupId;
      _retakeStrategy = course.retakeStrategy;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _credits.dispose();
    _gpaWeight.dispose();
    _teacher.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final rawCredits = _credits.text.trim();
      final credits = rawCredits.isEmpty ? null : double.parse(rawCredits);
      final rawWeight = _gpaWeight.text.trim();
      final weight = rawWeight.isEmpty ? 1.0 : double.parse(rawWeight);
      final course = LocalCourse(
        id: widget.course?.id ?? _newUuid(),
        semesterId: widget.semester.id,
        name: _name.text.trim(),
        courseNumber: _optional(_number.text),
        credits: credits,
        teacher: _optional(_teacher.text),
        isMajor: _isMajor,
        selectedForGpa: widget.course?.selectedForGpa ?? true,
        gpaWeight: weight,
        retakeGroupId: _retakeGroupId,
        retakeStrategy: _retakeStrategy,
      );
      await widget.controller.applyUpdate(
        (current) => _saveCourse(
          current,
          course,
          widget.semester.id,
          widget.course?.id,
        ),
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
          previousPageTitle: '课程',
          middle: Text(widget.course == null ? '新增课程' : '编辑课程'),
          leading: CupertinoButton(
            key: const ValueKey('course-cancel'),
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
              Text('所属学期：${widget.semester.name}'),
              const SizedBox(height: 16),
              _field('课程名称', _name, 'course-name', required: true),
              _field('课程号（可选）', _number, 'course-number'),
              _field('学分（可选）', _credits, 'course-credits',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  )),
              _field('GPA 权重', _gpaWeight, 'course-gpa-weight',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  )),
              _field('教师（可选）', _teacher, 'course-teacher'),
              const SizedBox(height: 8),
              CupertinoListTile(
                title: const Text('主修课程'),
                trailing: CupertinoSwitch(
                  key: const ValueKey('course-major'),
                  value: _isMajor,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _isMajor = value),
                ),
              ),
              CupertinoListTile(
                key: const ValueKey('course-retake-group'),
                title: const Text('重修关联'),
                subtitle: Text(_retakeGroupLabel),
                trailing: const CupertinoListTileChevron(),
                onTap: _saving ? null : _chooseRetakeGroup,
              ),
              if (_retakeGroupId != null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('重修成绩统计方式'),
                ),
                CupertinoSlidingSegmentedControl<RetakeSelectionStrategy>(
                  key: const ValueKey('course-retake-strategy'),
                  groupValue: _retakeStrategy,
                  children: const {
                    RetakeSelectionStrategy.firstAttempt: Text('首次修读'),
                    RetakeSelectionStrategy.highestGpa: Text('最高绩点'),
                  },
                  onValueChanged: (value) {
                    if (!_saving && value != null) {
                      setState(() => _retakeStrategy = value);
                    }
                  },
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: const TextStyle(color: CupertinoColors.systemRed),
                ),
              ],
              const SizedBox(height: 20),
              CupertinoButton.filled(
                key: const ValueKey('course-save'),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '正在保存…' : '保存'),
              ),
            ],
          ),
        ),
      );

  String get _retakeGroupLabel {
    final id = _retakeGroupId;
    if (id == null) return '未关联';
    final names = widget.controller.profile.value.courses
        .where((course) => course.retakeGroupId == id)
        .map((course) => course.name)
        .toSet();
    return names.isEmpty ? '新建重修组' : names.join('、');
  }

  Future<void> _chooseRetakeGroup() async {
    final groups = <String, Set<String>>{};
    for (final course in widget.controller.profile.value.courses) {
      final id = course.retakeGroupId;
      if (id == null || id == widget.course?.retakeGroupId) continue;
      groups.putIfAbsent(id, () => <String>{}).add(course.name);
    }
    final selected = await showCupertinoModalPopup<String?>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选择重修关联'),
        actions: [
          CupertinoActionSheetAction(
            key: const ValueKey('retake-group-create'),
            onPressed: () => Navigator.pop(context, _newUuid()),
            child: const Text('新建重修组'),
          ),
          ...groups.entries.map((entry) => CupertinoActionSheetAction(
                key: ValueKey('retake-group-${entry.key}'),
                onPressed: () => Navigator.pop(context, entry.key),
                child: Text(entry.value.join('、')),
              )),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('取消重修关联'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回'),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _retakeGroupId = selected.isEmpty ? null : selected;
      if (_retakeGroupId != null) {
        final existing = widget.controller.profile.value.courses.where(
          (course) => course.retakeGroupId == _retakeGroupId,
        );
        if (existing.isNotEmpty) {
          _retakeStrategy = existing.first.retakeStrategy;
        }
      }
    });
  }

  Widget _field(
    String label,
    TextEditingController controller,
    String key, {
    bool required = false,
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
              placeholder: required ? '必填' : '未填写',
              keyboardType: keyboardType,
            ),
          ],
        ),
      );

  static String? _optional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static AcademicProfile _saveCourse(
    AcademicProfile current,
    LocalCourse course,
    String semesterId,
    String? originalId,
  ) {
    if (!current.semesters.any((semester) => semester.id == semesterId)) {
      throw StateError('所属学期已不存在');
    }
    final courses = [...current.courses];
    if (originalId == null) {
      courses.add(course);
    } else {
      final index = courses.indexWhere((value) => value.id == originalId);
      if (index < 0) throw StateError('要编辑的课程已不存在');
      if (courses[index].semesterId != semesterId) {
        throw StateError('课程所属学期已发生变化');
      }
      courses[index] = course;
    }
    if (course.retakeGroupId case final groupId?) {
      for (var index = 0; index < courses.length; index++) {
        final member = courses[index];
        if (member.retakeGroupId == groupId && member.id != course.id) {
          courses[index] = LocalCourse(
            id: member.id,
            semesterId: member.semesterId,
            name: member.name,
            courseNumber: member.courseNumber,
            credits: member.credits,
            teacher: member.teacher,
            isMajor: member.isMajor,
            selectedForGpa: member.selectedForGpa,
            gpaWeight: member.gpaWeight,
            retakeGroupId: member.retakeGroupId,
            retakeStrategy: course.retakeStrategy,
          );
        }
      }
    }
    return AcademicProfile(
      schemaVersion: current.schemaVersion,
      revision: current.revision,
      currentSemesterId: current.currentSemesterId,
      semesters: current.semesters,
      timeSlots: current.timeSlots,
      courses: courses,
      sessionRules: current.sessionRules,
      exams: current.exams,
      grades: current.grades,
      practiceRecords: current.practiceRecords,
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
