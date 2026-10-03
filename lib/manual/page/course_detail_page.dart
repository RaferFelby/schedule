import 'package:celechron/model/period.dart';
import 'package:flutter/cupertino.dart';
import 'package:hive/hive.dart';

import '../../debug/manual_preview_task_store.dart';
import '../../manual/service/course_deletion_coordinator.dart';

import '../controller/academic_controller.dart';
import '../data/academic_repository.dart';
import '../model/academic_profile.dart';
import '../model/grade_record.dart';
import '../model/local_course.dart';
import '../model/local_exam.dart';
import '../model/session_rule.dart';
import '../model/local_semester.dart';
import '../model/time_slot.dart';
import '../service/schedule_expander.dart';
import '../service/grade_calculator.dart';
import 'course_edit_page.dart';
import 'session_rule_edit_page.dart';
import 'session_reschedule_edit_page.dart';
import 'session_extra_occurrence_edit_page.dart';
import 'exam_edit_page.dart';
import 'grade_edit_page.dart';

/// Course summary with truthful placeholders for unfinished capabilities.
final class CourseDetailPage extends StatefulWidget {
  const CourseDetailPage({
    super.key,
    required this.repository,
    required this.semester,
    required this.course,
    this.previewBox,
    this.deleteCourse,
  });

  final AcademicRepository repository;
  final LocalSemester semester;
  final LocalCourse course;
  final Box<String>? previewBox;
  final Future<void> Function(String courseId)? deleteCourse;

  @override
  State<CourseDetailPage> createState() => _CourseDetailPageState();
}

final class _CourseDetailPageState extends State<CourseDetailPage> {
  late LocalCourse _course = widget.course;
  late Future<List<_CourseRuleSchedule>> _schedules;
  late Future<List<LocalExam>> _exams;
  late Future<List<GradeRecord>> _grades;
  bool _editing = false;
  bool _addingRule = false;
  bool _addingExam = false;
  bool _addingGrade = false;
  bool _changingGrade = false;
  bool _changingExam = false;
  bool _changingRule = false;
  bool _settingGpaSelection = false;
  bool _deletingCourse = false;
  String? _deleteError;
  String? _gpaSelectionError;

  @override
  void initState() {
    super.initState();
    _schedules = _readSchedules();
    _exams = _readExams();
    _grades = _readGrades();
  }

  Future<List<GradeRecord>> _readGrades() async {
    final profile = await widget.repository.read();
    return List.unmodifiable(
        profile.grades.where((grade) => grade.courseId == _course.id));
  }

  Future<void> _addGrade() async {
    if (_addingGrade) return;
    setState(() => _addingGrade = true);
    try {
      final profile = await widget.repository.read();
      if (!mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        CupertinoPageRoute<bool>(
          builder: (_) => GradeEditPage(
            controller: AcademicController(
              repository: widget.repository,
              initialProfile: profile,
            ),
            course: _course,
          ),
        ),
      );
      if (saved == true && mounted) {
        final refreshed = _readGrades();
        setState(() {
          _grades = refreshed;
        });
      }
    } finally {
      if (mounted) setState(() => _addingGrade = false);
    }
  }

  Future<void> _editGrade(GradeRecord record) async {
    if (_changingGrade) return;
    setState(() => _changingGrade = true);
    try {
      final profile = await widget.repository.read();
      if (!mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        CupertinoPageRoute<bool>(
          builder: (_) => GradeEditPage(
            controller: AcademicController(
              repository: widget.repository,
              initialProfile: profile,
            ),
            course: _course,
            record: record,
          ),
        ),
      );
      if (saved == true && mounted) {
        final refreshed = _readGrades();
        setState(() {
          _grades = refreshed;
        });
      }
    } finally {
      if (mounted) setState(() => _changingGrade = false);
    }
  }

  Future<void> _deleteGrade(GradeRecord record) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('删除成绩记录？'),
        content: const Text('只删除这条成绩记录，不会删除课程。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _changingGrade) return;
    setState(() => _changingGrade = true);
    try {
      await widget.repository.update((current) {
        if (!current.grades.any((item) => item.id == record.id)) {
          throw StateError('成绩记录已不存在');
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
          grades: current.grades.where((item) => item.id != record.id).toList(),
          practiceRecords: current.practiceRecords,
        );
      });
      if (mounted) {
        final refreshed = _readGrades();
        setState(() {
          _grades = refreshed;
        });
      }
    } finally {
      if (mounted) setState(() => _changingGrade = false);
    }
  }

  Future<List<LocalExam>> _readExams() async {
    final profile = await widget.repository.read();
    final exams =
        profile.exams.where((exam) => exam.courseId == _course.id).toList()
          ..sort((a, b) {
            if (a.start == null) return b.start == null ? 0 : 1;
            if (b.start == null) return -1;
            return a.start!.compareTo(b.start!);
          });
    return List.unmodifiable(exams);
  }

  Future<void> _addExam() async {
    if (_addingExam) return;
    setState(() => _addingExam = true);
    try {
      final profile = await widget.repository.read();
      if (!mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        CupertinoPageRoute<bool>(
          builder: (_) => ExamEditPage(
            controller: AcademicController(
              repository: widget.repository,
              initialProfile: profile,
            ),
            course: _course,
          ),
        ),
      );
      if (saved == true && mounted) {
        final refreshed = _readExams();
        setState(() {
          _exams = refreshed;
        });
      }
    } finally {
      if (mounted) setState(() => _addingExam = false);
    }
  }

  Future<void> _editExam(LocalExam exam) async {
    if (_changingExam) return;
    setState(() => _changingExam = true);
    try {
      final profile = await widget.repository.read();
      if (!mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        CupertinoPageRoute<bool>(
          builder: (_) => ExamEditPage(
            controller: AcademicController(
              repository: widget.repository,
              initialProfile: profile,
            ),
            course: _course,
            exam: exam,
          ),
        ),
      );
      if (saved == true && mounted) {
        final refreshed = _readExams();
        setState(() {
          _exams = refreshed;
        });
      }
    } finally {
      if (mounted) setState(() => _changingExam = false);
    }
  }

  Future<void> _deleteExam(LocalExam exam) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('删除考试记录？'),
        content: const Text('只删除这条考试记录，不会删除课程。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _changingExam) return;
    setState(() => _changingExam = true);
    try {
      await widget.repository.update((current) {
        if (!current.exams.any((item) => item.id == exam.id)) {
          throw StateError('考试记录已不存在');
        }
        return AcademicProfile(
          schemaVersion: current.schemaVersion,
          revision: current.revision,
          currentSemesterId: current.currentSemesterId,
          semesters: current.semesters,
          timeSlots: current.timeSlots,
          courses: current.courses,
          sessionRules: current.sessionRules,
          exams: current.exams.where((item) => item.id != exam.id).toList(),
          grades: current.grades,
          practiceRecords: current.practiceRecords,
        );
      });
      if (mounted) {
        final refreshed = _readExams();
        setState(() {
          _exams = refreshed;
        });
      }
    } finally {
      if (mounted) setState(() => _changingExam = false);
    }
  }

  Future<List<_CourseRuleSchedule>> _readSchedules() async {
    final profile = await widget.repository.read();
    final schedules = <_CourseRuleSchedule>[];
    for (final rule in profile.sessionRules.where(
      (value) => value.courseId == _course.id,
    )) {
      final periods = ScheduleExpander.expandRule(
        semester: widget.semester,
        course: _course,
        rule: rule,
        timeSlots: profile.timeSlots.isEmpty
            ? TimeSlot.defaultTemplate()
            : profile.timeSlots,
      );
      schedules.add(_CourseRuleSchedule(rule, periods));
    }
    schedules.sort((a, b) {
      final weekdayOrder = a.rule.weekday.compareTo(b.rule.weekday);
      return weekdayOrder != 0
          ? weekdayOrder
          : a.rule.weekNumbers.first.compareTo(b.rule.weekNumbers.first);
    });
    return List.unmodifiable(schedules);
  }

  Future<void> _edit() async {
    if (_editing) return;
    setState(() => _editing = true);
    try {
      final profile = await widget.repository.read();
      if (!mounted) return;
      final controller = AcademicController(
        repository: widget.repository,
        initialProfile: profile,
      );
      final saved = await Navigator.of(context).push<bool>(
        CupertinoPageRoute<bool>(
          builder: (_) => CourseEditPage(
            controller: controller,
            semester: widget.semester,
            course: _course,
          ),
        ),
      );
      if (saved == true && mounted) {
        final updated = await widget.repository.read();
        final courses =
            updated.courses.where((value) => value.id == _course.id).toList();
        if (courses.isNotEmpty) {
          setState(() {
            _course = courses.first;
            _schedules = _readSchedules();
          });
        }
      }
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _setGpaSelection(bool selected) async {
    if (_settingGpaSelection) return;
    setState(() {
      _settingGpaSelection = true;
      _gpaSelectionError = null;
    });
    try {
      final saved = await widget.repository.update((current) {
        final index =
            current.courses.indexWhere((item) => item.id == _course.id);
        if (index < 0) throw StateError('课程已不存在');
        final courses = List<LocalCourse>.of(current.courses);
        final old = courses[index];
        courses[index] = LocalCourse(
          id: old.id,
          semesterId: old.semesterId,
          name: old.name,
          courseNumber: old.courseNumber,
          credits: old.credits,
          teacher: old.teacher,
          isMajor: old.isMajor,
          selectedForGpa: selected,
          gpaWeight: old.gpaWeight,
          retakeGroupId: old.retakeGroupId,
          retakeStrategy: old.retakeStrategy,
        );
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
      });
      if (mounted) {
        setState(() {
          _course = saved.courses.firstWhere((item) => item.id == _course.id);
        });
      }
    } catch (error) {
      if (mounted) setState(() => _gpaSelectionError = error.toString());
    } finally {
      if (mounted) setState(() => _settingGpaSelection = false);
    }
  }

  Future<void> _deleteCourse() async {
    final previewBox = widget.previewBox;
    if (_deletingCourse || previewBox == null) return;
    setState(() {
      _deletingCourse = true;
      _deleteError = null;
    });
    try {
      final profile = await widget.repository.read();
      final tasks = await ManualPreviewTaskStore(previewBox).readTasks();
      if (!mounted) return;
      final ruleCount = profile.sessionRules
          .where((rule) => rule.courseId == _course.id)
          .length;
      final examCount =
          profile.exams.where((exam) => exam.courseId == _course.id).length;
      final gradeCount =
          profile.grades.where((grade) => grade.courseId == _course.id).length;
      final taskCount =
          tasks.where((task) => task.courseId == _course.id).length;
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('删除课程？'),
          content: Text(
            '将删除 $ruleCount 条上课安排、$examCount 场考试和 $gradeCount 条成绩，'
            '并解除 $taskCount 个作业的课程关联。作业及已用时间会保留。',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除课程'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final deleteCourse = widget.deleteCourse;
      if (deleteCourse == null) {
        await CourseDeletionCoordinator(
          repository: widget.repository,
          previewBox: previewBox,
        ).removeCourse(_course.id);
      } else {
        await deleteCourse(_course.id);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _deleteError = '删除未完成，可重试：$error');
    } finally {
      if (mounted) setState(() => _deletingCourse = false);
    }
  }

  Future<void> _addRule() async {
    if (_addingRule) return;
    setState(() => _addingRule = true);
    try {
      final profile = await widget.repository.read();
      if (!mounted) return;
      final controller = AcademicController(
        repository: widget.repository,
        initialProfile: profile,
      );
      final saved = await Navigator.of(context).push<bool>(
        CupertinoPageRoute<bool>(
          builder: (_) => SessionRuleEditPage(
            controller: controller,
            course: _course,
          ),
        ),
      );
      if (saved == true && mounted) {
        final refreshed = _readSchedules();
        setState(() {
          _schedules = refreshed;
        });
      }
    } finally {
      if (mounted) setState(() => _addingRule = false);
    }
  }

  Future<void> _addExtra(SessionRule rule) async {
    if (_changingRule) return;
    setState(() => _changingRule = true);
    try {
      final profile = await widget.repository.read();
      if (!mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        CupertinoPageRoute<bool>(
          builder: (_) => SessionExtraOccurrenceEditPage(
            controller: AcademicController(
              repository: widget.repository,
              initialProfile: profile,
            ),
            course: _course,
            semester: widget.semester,
            rule: rule,
          ),
        ),
      );
      if (saved == true && mounted) {
        final refreshed = _readSchedules();
        setState(() {
          _schedules = refreshed;
        });
      }
    } finally {
      if (mounted) setState(() => _changingRule = false);
    }
  }

  Future<void> _deleteExtra(SessionRule rule, String extraId) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('删除这次补课？'),
        content: const Text('只删除选中的补课，不影响周期上课安排。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _changingRule) return;
    setState(() => _changingRule = true);
    try {
      await widget.repository.update((current) {
        final index =
            current.sessionRules.indexWhere((item) => item.id == rule.id);
        if (index < 0) throw StateError('上课安排已不存在');
        final existing = current.sessionRules[index];
        final rules = List<SessionRule>.of(current.sessionRules)
          ..[index] = SessionRule(
            id: existing.id,
            courseId: existing.courseId,
            weekday: existing.weekday,
            weekNumbers: existing.weekNumbers,
            startSlotOrdinal: existing.startSlotOrdinal,
            endSlotOrdinal: existing.endSlotOrdinal,
            location: existing.location,
            teacher: existing.teacher,
            cancelledDates: existing.cancelledDates,
            reschedules: existing.reschedules,
            extraOccurrences: existing.extraOccurrences
                .where((item) => item.id != extraId)
                .toList(),
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
      if (mounted) {
        final refreshed = _readSchedules();
        setState(() {
          _schedules = refreshed;
        });
      }
    } finally {
      if (mounted) setState(() => _changingRule = false);
    }
  }

  String? _extraId(Period period) {
    final marker = period.uid.indexOf('-extra-');
    return marker < 0 ? null : period.uid.substring(marker + 7);
  }

  DateTime _originalDate(Period period) {
    final date = period.uid.substring(period.uid.length - 8);
    return DateTime(
      int.parse(date.substring(0, 4)),
      int.parse(date.substring(4, 6)),
      int.parse(date.substring(6, 8)),
    );
  }

  Future<void> _editReschedule(SessionRule rule, DateTime originalDate) async {
    if (_changingRule) return;
    setState(() => _changingRule = true);
    try {
      final profile = await widget.repository.read();
      if (!mounted) return;
      final matches = rule.reschedules.where(
        (item) => _sameDate(item.originalDate, originalDate),
      );
      final saved = await Navigator.of(context).push<bool>(
        CupertinoPageRoute<bool>(
          builder: (_) => SessionRescheduleEditPage(
            controller: AcademicController(
              repository: widget.repository,
              initialProfile: profile,
            ),
            course: _course,
            rule: rule,
            originalDate: originalDate,
            existing: matches.isEmpty ? null : matches.single,
          ),
        ),
      );
      if (saved == true && mounted) {
        final refreshed = _readSchedules();
        setState(() {
          _schedules = refreshed;
        });
      }
    } finally {
      if (mounted) setState(() => _changingRule = false);
    }
  }

  Future<void> _restoreReschedule(
      SessionRule rule, DateTime originalDate) async {
    if (_changingRule) return;
    setState(() => _changingRule = true);
    try {
      await widget.repository.update((current) {
        final index =
            current.sessionRules.indexWhere((item) => item.id == rule.id);
        if (index < 0) throw StateError('上课安排已不存在');
        final existing = current.sessionRules[index];
        final rules = List<SessionRule>.of(current.sessionRules)
          ..[index] = SessionRule(
            id: existing.id,
            courseId: existing.courseId,
            weekday: existing.weekday,
            weekNumbers: existing.weekNumbers,
            startSlotOrdinal: existing.startSlotOrdinal,
            endSlotOrdinal: existing.endSlotOrdinal,
            location: existing.location,
            teacher: existing.teacher,
            cancelledDates: existing.cancelledDates,
            reschedules: existing.reschedules
                .where((item) => !_sameDate(item.originalDate, originalDate))
                .toList(),
            extraOccurrences: existing.extraOccurrences,
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
      if (mounted) {
        final refreshed = _readSchedules();
        setState(() {
          _schedules = refreshed;
        });
      }
    } finally {
      if (mounted) setState(() => _changingRule = false);
    }
  }

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _editRule(SessionRule rule) async {
    if (_changingRule) return;
    setState(() => _changingRule = true);
    try {
      final profile = await widget.repository.read();
      if (!mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        CupertinoPageRoute<bool>(
          builder: (_) => SessionRuleEditPage(
            controller: AcademicController(
              repository: widget.repository,
              initialProfile: profile,
            ),
            course: _course,
            rule: rule,
          ),
        ),
      );
      if (saved == true && mounted) {
        final refreshed = _readSchedules();
        setState(() {
          _schedules = refreshed;
        });
      }
    } finally {
      if (mounted) setState(() => _changingRule = false);
    }
  }

  Future<void> _toggleCancellation(
    SessionRule rule,
    DateTime date, {
    required bool cancel,
  }) async {
    if (_changingRule) return;
    setState(() => _changingRule = true);
    final dateOnly = DateTime(date.year, date.month, date.day);
    try {
      await widget.repository.update((current) {
        final index =
            current.sessionRules.indexWhere((item) => item.id == rule.id);
        if (index < 0) throw StateError('上课安排已不存在');
        final existing = current.sessionRules[index];
        final dates = existing.cancelledDates
            .where((item) => !_sameDate(item, dateOnly))
            .toList();
        if (cancel) dates.add(dateOnly);
        final updated = SessionRule(
          id: existing.id,
          courseId: existing.courseId,
          weekday: existing.weekday,
          weekNumbers: existing.weekNumbers,
          startSlotOrdinal: existing.startSlotOrdinal,
          endSlotOrdinal: existing.endSlotOrdinal,
          location: existing.location,
          teacher: existing.teacher,
          cancelledDates: dates,
          reschedules: existing.reschedules,
          extraOccurrences: existing.extraOccurrences,
        );
        final rules = List<SessionRule>.of(current.sessionRules)
          ..[index] = updated;
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
      if (mounted) {
        final refreshed = _readSchedules();
        setState(() {
          _schedules = refreshed;
        });
      }
    } finally {
      if (mounted) setState(() => _changingRule = false);
    }
  }

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _deleteRule(SessionRule rule) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('删除上课安排？'),
        content: const Text('只会删除这条安排，其他安排保持不变。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _changingRule) return;
    setState(() => _changingRule = true);
    try {
      await widget.repository.update((current) => AcademicProfile(
            schemaVersion: current.schemaVersion,
            revision: current.revision,
            currentSemesterId: current.currentSemesterId,
            semesters: current.semesters,
            timeSlots: current.timeSlots,
            courses: current.courses,
            sessionRules: current.sessionRules
                .where((item) => item.id != rule.id)
                .toList(),
            exams: current.exams,
            grades: current.grades,
            practiceRecords: current.practiceRecords,
          ));
      if (mounted) {
        final refreshed = _readSchedules();
        setState(() {
          _schedules = refreshed;
        });
      }
    } finally {
      if (mounted) setState(() => _changingRule = false);
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          previousPageTitle: '课程',
          middle: const Text('课程详情'),
          trailing: CupertinoButton(
            key: const ValueKey('course-detail-edit'),
            padding: EdgeInsets.zero,
            onPressed: _editing ? null : _edit,
            child: const Text('编辑'),
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _section('基本信息', [
                _value('课程名称', _course.name),
                _value('课程号', _course.courseNumber ?? '未填写'),
                _value('教师', _course.teacher ?? '未填写'),
                _value('学分', _course.credits?.toString() ?? '未填写'),
                _value('主修', _course.isMajor ? '是' : '否'),
                _value('所属学期', widget.semester.name),
              ]),
              const SizedBox(height: 12),
              _scheduleSection(),
              const SizedBox(height: 12),
              _examSection(),
              const SizedBox(height: 12),
              _gradeSection(),
              const SizedBox(height: 12),
              _section('成绩统计', [
                CupertinoListTile(
                  title: const Text('计入 GPA 与学分汇总'),
                  trailing: CupertinoSwitch(
                    key: const ValueKey('course-gpa-selection'),
                    value: _course.selectedForGpa,
                    onChanged: _settingGpaSelection ? null : _setGpaSelection,
                  ),
                ),
                if (_gpaSelectionError != null)
                  Text(
                    '保存统计选择失败：$_gpaSelectionError',
                    style: const TextStyle(color: CupertinoColors.systemRed),
                  ),
              ]),
              if (widget.previewBox != null) ...[
                const SizedBox(height: 12),
                CupertinoButton(
                  key: const ValueKey('course-delete'),
                  onPressed: _deletingCourse ? null : _deleteCourse,
                  color: CupertinoColors.systemRed,
                  child: Text(_deletingCourse ? '正在删除…' : '删除此课程'),
                ),
                if (_deleteError != null)
                  Text(
                    _deleteError!,
                    style: const TextStyle(color: CupertinoColors.systemRed),
                  ),
              ],
            ],
          ),
        ),
      );

  Widget _gradeSection() => FutureBuilder<List<GradeRecord>>(
        future: _grades,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _section('成绩', [
              const CupertinoActivityIndicator(),
              _addGradeButton(),
            ]);
          }
          if (snapshot.hasError) {
            return _section('成绩', [
              Text('读取成绩失败：${snapshot.error}'),
              _addGradeButton(),
            ]);
          }
          final grades = snapshot.data!;
          if (grades.isEmpty) {
            return _section('成绩', [
              const Text('尚无成绩记录'),
              _addGradeButton(),
            ]);
          }
          return _section('成绩', [
            ...grades.expand((grade) => [
                  _gradeSummary(grade),
                  Row(
                    children: [
                      CupertinoButton(
                        key: ValueKey('course-grade-edit-${grade.id}'),
                        onPressed:
                            _changingGrade ? null : () => _editGrade(grade),
                        child: const Text('编辑成绩'),
                      ),
                      CupertinoButton(
                        key: ValueKey('course-grade-delete-${grade.id}'),
                        onPressed:
                            _changingGrade ? null : () => _deleteGrade(grade),
                        child: const Text('删除成绩'),
                      ),
                    ],
                  ),
                ]),
          ]);
        },
      );

  Widget _addGradeButton() => CupertinoButton.filled(
        key: const ValueKey('course-add-grade'),
        onPressed: _addingGrade ? null : _addGrade,
        child: const Text('新增成绩'),
      );

  Widget _gradeSummary(GradeRecord record) {
    if (record.status == LocalGradeStatus.notRecorded) {
      return const Text('成绩尚未录入');
    }
    final value = switch (record.method) {
      LocalGradingMethod.percentage => '${record.rawScore} 分',
      LocalGradingMethod.letter => record.gradeLabel!,
      LocalGradingMethod.passFail => record.gradeLabel!,
      LocalGradingMethod.directGpa => '绩点 ${record.gradePoint}',
    };
    final calculation = GradeCalculator.calculate(
      record: record,
      course: _course,
    );
    final gpa = calculation.includedInGpa
        ? '计入 GPA（${calculation.gradePoint}）'
        : 'GPA 暂无可用换算';
    final earned = calculation.earnedCredits == null
        ? '获得学分：未确定'
        : '获得学分：${calculation.earnedCredits}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_methodLabel(record.method)}：$value'),
        Text(gpa),
        Text(earned),
      ],
    );
  }

  static String _methodLabel(LocalGradingMethod method) => switch (method) {
        LocalGradingMethod.percentage => '百分制',
        LocalGradingMethod.letter => '等级制',
        LocalGradingMethod.passFail => '通过制',
        LocalGradingMethod.directGpa => '直接绩点',
      };

  Widget _examSection() => FutureBuilder<List<LocalExam>>(
        future: _exams,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _section('考试', [
              const CupertinoActivityIndicator(),
              _addExamButton(),
            ]);
          }
          if (snapshot.hasError) {
            return _section('考试', [
              Text('读取考试失败：${snapshot.error}'),
              _addExamButton(),
            ]);
          }
          final exams = snapshot.data!;
          if (exams.isEmpty) {
            return _section('考试', [
              const Text('尚无考试记录'),
              _addExamButton(),
            ]);
          }
          return _section('考试', [
            ...exams.expand((exam) => [
                  Text(_examLabel(exam)),
                  Row(
                    children: [
                      CupertinoButton(
                        key: ValueKey('course-exam-edit-${exam.id}'),
                        onPressed: _changingExam ? null : () => _editExam(exam),
                        child: const Text('编辑考试'),
                      ),
                      CupertinoButton(
                        key: ValueKey('course-exam-delete-${exam.id}'),
                        onPressed:
                            _changingExam ? null : () => _deleteExam(exam),
                        child: const Text('删除考试'),
                      ),
                    ],
                  ),
                ]),
            _addExamButton(),
          ]);
        },
      );

  Widget _addExamButton() => CupertinoButton.filled(
        key: const ValueKey('course-add-exam'),
        onPressed: _addingExam ? null : _addExam,
        child: const Text('新增考试'),
      );

  static String _examLabel(LocalExam exam) {
    final timing = exam.start == null
        ? '时间未定'
        : '${_date(exam.start!)} ${_time(exam.start!)}–${_time(exam.end!)}';
    final details = [exam.location, exam.seat]
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .join(' · ');
    return '${exam.type} · $timing${details.isEmpty ? '' : ' · $details'}';
  }

  Widget _scheduleSection() => FutureBuilder<List<_CourseRuleSchedule>>(
        future: _schedules,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _section('上课安排', [
              const CupertinoActivityIndicator(),
              _addRuleButton(),
            ]);
          }
          if (snapshot.hasError) {
            return _section('上课安排', [
              Text('读取上课安排失败：${snapshot.error}'),
              _addRuleButton(),
            ]);
          }
          final schedules = snapshot.data!;
          if (schedules.isEmpty) {
            return _section('上课安排', [
              const Text('尚未添加上课安排'),
              _addRuleButton(),
            ]);
          }
          return _section(
            '上课安排',
            [
              ...schedules.expand((schedule) => [
                    Text('本次教师：${schedule.rule.teacher ?? _course.teacher ?? '未填写'}'),
                    ...schedule.periods.expand((period) {
                      final extraId = _extraId(period);
                      if (extraId != null) {
                        return [
                          Text('${_periodLabel(period)} · 补课'),
                          CupertinoButton(
                            key: ValueKey('course-extra-delete-$extraId'),
                            onPressed: _changingRule
                                ? null
                                : () => _deleteExtra(schedule.rule, extraId),
                            child: const Text('删除这次补课'),
                          ),
                        ];
                      }
                      final originalDate = _originalDate(period);
                      final moved = schedule.rule.reschedules.any(
                        (item) => _sameDate(item.originalDate, originalDate),
                      );
                      return [
                        Text(_periodLabel(period)),
                        CupertinoButton(
                          key: ValueKey(
                            'course-rule-reschedule-${schedule.rule.id}-${_dateKey(originalDate)}',
                          ),
                          onPressed: _changingRule
                              ? null
                              : () =>
                                  _editReschedule(schedule.rule, originalDate),
                          child: Text(moved ? '修改调课' : '调课'),
                        ),
                        CupertinoButton(
                          key: ValueKey(
                            'course-rule-cancel-${schedule.rule.id}-${_dateKey(period.startTime)}',
                          ),
                          onPressed: _changingRule
                              ? null
                              : () => _toggleCancellation(
                                    schedule.rule,
                                    period.startTime,
                                    cancel: true,
                                  ),
                          child: const Text('停课这一次'),
                        ),
                      ];
                    }),
                    ...schedule.rule.reschedules.map((item) => Row(
                          children: [
                            Text(
                                '${_date(item.originalDate)} → ${_date(item.targetDate)} · 已调课'),
                            CupertinoButton(
                              key: ValueKey(
                                'course-rule-restore-reschedule-${schedule.rule.id}-${_dateKey(item.originalDate)}',
                              ),
                              onPressed: _changingRule
                                  ? null
                                  : () => _restoreReschedule(
                                      schedule.rule, item.originalDate),
                              child: const Text('恢复原安排'),
                            ),
                          ],
                        )),
                    ...schedule.rule.cancelledDates.map((date) => Row(
                          children: [
                            Text('${_date(date)} · 已停课'),
                            CupertinoButton(
                              key: ValueKey(
                                'course-rule-restore-${schedule.rule.id}-${_dateKey(date)}',
                              ),
                              onPressed: _changingRule
                                  ? null
                                  : () => _toggleCancellation(
                                        schedule.rule,
                                        date,
                                        cancel: false,
                                      ),
                              child: const Text('恢复本次课程'),
                            ),
                          ],
                        )),
                    CupertinoButton(
                      key:
                          ValueKey('course-rule-add-extra-${schedule.rule.id}'),
                      onPressed:
                          _changingRule ? null : () => _addExtra(schedule.rule),
                      child: const Text('新增补课'),
                    ),
                    Row(
                      children: [
                        CupertinoButton(
                          key: ValueKey('course-rule-edit-${schedule.rule.id}'),
                          onPressed: _changingRule
                              ? null
                              : () => _editRule(schedule.rule),
                          child: const Text('编辑这条安排'),
                        ),
                        CupertinoButton(
                          key: ValueKey(
                              'course-rule-delete-${schedule.rule.id}'),
                          onPressed: _changingRule
                              ? null
                              : () => _deleteRule(schedule.rule),
                          child: const Text('删除这条安排'),
                        ),
                      ],
                    ),
                  ]),
              _addRuleButton(),
            ],
          );
        },
      );

  Widget _addRuleButton() => CupertinoButton.filled(
        key: const ValueKey('course-add-rule'),
        onPressed: _addingRule ? null : _addRule,
        child: const Text('新增上课安排'),
      );

  static String _periodLabel(Period period) =>
      '${_date(period.startTime)} ${_time(period.startTime)}–'
      '${_time(period.endTime)}${period.location.isEmpty ? '' : ' · ${period.location}'}';

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  static Widget _section(String title, List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );

  static Widget _value(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text('$label：$value'),
      );
}

final class _CourseRuleSchedule {
  const _CourseRuleSchedule(this.rule, this.periods);

  final SessionRule rule;
  final List<Period> periods;
}
