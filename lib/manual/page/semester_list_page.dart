import 'package:flutter/cupertino.dart';
import 'package:hive/hive.dart';

import '../../debug/manual_preview_task_store.dart';
import '../controller/academic_controller.dart';
import '../data/academic_repository.dart';
import '../model/academic_profile.dart';
import '../model/local_semester.dart';
import '../service/course_deletion_coordinator.dart';
import '../service/manual_grade_summary_adapter.dart';
import '../service/semester_deletion_service.dart';
import 'course_list_page.dart';
import 'semester_edit_page.dart';
import 'time_slot_list_page.dart';

/// Local academic overview used by the academic tab and manual-entry preview.
final class SemesterListPage extends StatefulWidget {
  const SemesterListPage(
      {super.key,
      required this.repository,
      this.previewBox,
      this.deleteSemester});

  final AcademicRepository repository;
  final Box<String>? previewBox;
  final Future<void> Function(String semesterId)? deleteSemester;

  @override
  State<SemesterListPage> createState() => _SemesterListPageState();
}

final class _SemesterListPageState extends State<SemesterListPage> {
  late Future<AcademicProfile> _profile;
  bool _adding = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _profile = widget.repository.read();
  }

  @override
  void didUpdateWidget(covariant SemesterListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _profile = widget.repository.read();
    }
  }

  Future<void> _addSemester() async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      final current = await _profile;
      if (!mounted) return;
      final controller = AcademicController(
        repository: widget.repository,
        initialProfile: current,
      );
      final saved = await Navigator.of(context).push<bool>(
        CupertinoPageRoute(
          builder: (_) => SemesterEditPage(controller: controller),
        ),
      );
      if (saved == true && mounted) {
        setState(() {
          _profile = widget.repository.read();
        });
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _editSemester(LocalSemester semester) async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      final current = await _profile;
      if (!mounted) return;
      final controller = AcademicController(
        repository: widget.repository,
        initialProfile: current,
      );
      final saved = await Navigator.of(context).push<bool>(
        CupertinoPageRoute(
          builder: (_) => SemesterEditPage(
            controller: controller,
            semester: semester,
          ),
        ),
      );
      if (saved == true && mounted) {
        setState(() {
          _profile = widget.repository.read();
        });
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _setCurrentSemester(
    AcademicProfile current,
    LocalSemester semester,
  ) async {
    if (_adding) return;
    setState(() {
      _adding = true;
      _actionError = null;
    });
    try {
      final controller = AcademicController(
        repository: widget.repository,
        initialProfile: current,
      );
      final saved = await controller.applyUpdate(
        (latest) => AcademicProfile(
          schemaVersion: latest.schemaVersion,
          revision: latest.revision,
          currentSemesterId: semester.id,
          semesters: latest.semesters,
          timeSlots: latest.timeSlots,
          courses: latest.courses,
          sessionRules: latest.sessionRules,
          exams: latest.exams,
          grades: latest.grades,
          practiceRecords: latest.practiceRecords,
        ),
      );
      if (mounted) {
        setState(() => _profile = Future.value(saved));
      }
    } catch (error) {
      if (mounted) setState(() => _actionError = error.toString());
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _openTimeSlots() async {
    if (_adding) return;
    await Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (_) => TimeSlotListPage(repository: widget.repository),
      ),
    );
  }

  Future<void> _openCourses(LocalSemester semester) async {
    if (_adding) return;
    await Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (_) => CourseListPage(
          repository: widget.repository,
          semester: semester,
          previewBox: widget.previewBox,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _profile = widget.repository.read();
      });
    }
  }

  Future<void> _deleteSemester(LocalSemester semester) async {
    final previewBox = widget.previewBox;
    if (_adding || previewBox == null) return;
    setState(() {
      _adding = true;
      _actionError = null;
    });
    try {
      final current = await widget.repository.read();
      final tasks = await ManualPreviewTaskStore(previewBox).readTasks();
      final impact = SemesterDeletionService.impact(
        profile: current,
        tasks: tasks,
        semesterId: semester.id,
      );
      if (!mounted || impact == null) return;
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text('删除“${impact.semesterName}”？'),
          content: Text(
            '将删除 ${impact.courseIds.length} 门课程、'
            '${impact.sessionRuleCount} 条上课安排、${impact.examCount} 场考试、'
            '${impact.gradeCount} 条成绩，并解除 ${impact.taskCount} 个作业关联。'
            '作业及已用时间会保留。',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除学期'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final deleteSemester = widget.deleteSemester;
      if (deleteSemester == null) {
        await CourseDeletionCoordinator(
          repository: widget.repository,
          previewBox: previewBox,
        ).removeSemester(semester.id);
      } else {
        await deleteSemester(semester.id);
      }
      if (mounted) setState(() => _profile = widget.repository.read());
    } catch (error) {
      if (mounted) setState(() => _actionError = '删除未完成，可重试：$error');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        previousPageTitle: '学业',
        middle: const Text('学期'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: const EdgeInsets.only(right: 8),
              onPressed: _adding ? null : _openTimeSlots,
              child: const Text('节次表'),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _adding ? null : _addSemester,
              child: const Text('新增'),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (_actionError != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _actionError!,
                  style: const TextStyle(color: CupertinoColors.systemRed),
                ),
              ),
            Expanded(
              child: FutureBuilder<AcademicProfile>(
                future: _profile,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CupertinoActivityIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('读取学期失败：${snapshot.error}'));
                  }

                  final profile = snapshot.data!;
                  final semesters = [...profile.semesters]
                    ..sort(_compareSemesters);
                  if (semesters.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('还没有学期'),
                          SizedBox(height: 8),
                          Text('创建学期后会显示在这里。'),
                        ],
                      ),
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _SummaryCard(
                        key: const ValueKey('grade-summary-all'),
                        title: '全部学期',
                        summary: ManualGradeSummaryAdapter.calculate(profile),
                      ),
                      const SizedBox(height: 12),
                      for (final semester in semesters) ...[
                        _SemesterRow(
                          semester: semester,
                          isCurrent: profile.currentSemesterId == semester.id,
                          summary: ManualGradeSummaryAdapter.calculate(
                            profile,
                            semesterId: semester.id,
                          ),
                          onEdit: () => _editSemester(semester),
                          onSelect: () =>
                              _setCurrentSemester(profile, semester),
                          onCourses: () => _openCourses(semester),
                          onDelete: widget.previewBox == null
                              ? null
                              : () => _deleteSemester(semester),
                          deleting: _adding,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static int _compareSemesters(LocalSemester left, LocalSemester right) {
    final byStartDate = left.startDate.compareTo(right.startDate);
    if (byStartDate != 0) return byStartDate;
    final byEndDate = left.endDate.compareTo(right.endDate);
    if (byEndDate != 0) return byEndDate;
    return left.id.compareTo(right.id);
  }
}

final class _SemesterRow extends StatelessWidget {
  const _SemesterRow({
    required this.semester,
    required this.isCurrent,
    required this.summary,
    required this.onEdit,
    required this.onSelect,
    required this.onCourses,
    this.onDelete,
    required this.deleting,
  });

  final LocalSemester semester;
  final bool isCurrent;
  final ManualGradeSummary summary;
  final VoidCallback onEdit;
  final VoidCallback onSelect;
  final VoidCallback onCourses;
  final VoidCallback? onDelete;
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CupertinoButton(
            key: ValueKey('semester-courses-${semester.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: onCourses,
            child: const Text('课程'),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onEdit,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(semester.name,
                        style: CupertinoTheme.of(context).textTheme.textStyle),
                    const SizedBox(height: 6),
                    Text(
                      '${_date(semester.startDate)} — ${_date(semester.endDate)}',
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .tabLabelTextStyle,
                    ),
                    const SizedBox(height: 4),
                    Text(_summaryText(summary)),
                  ],
                ),
              ),
            ),
          ),
          if (isCurrent)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('当前学期'),
            )
          else
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: onSelect,
              child: const Text('设为当前'),
            ),
          if (onDelete != null)
            CupertinoButton(
              key: ValueKey('semester-delete-${semester.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              onPressed: deleting ? null : onDelete,
              child: const Icon(
                CupertinoIcons.delete,
                color: CupertinoColors.systemRed,
                semanticLabel: '删除学期',
              ),
            ),
        ],
      ),
    );
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

final class _SummaryCard extends StatelessWidget {
  const _SummaryCard({super.key, required this.title, required this.summary});

  final String title;
  final ManualGradeSummary summary;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: CupertinoTheme.of(context).textTheme.textStyle),
            const SizedBox(height: 6),
            Text(_summaryText(summary)),
          ],
        ),
      );
}

String _summaryText(ManualGradeSummary summary) {
  final gpa = summary.gpa.gpa;
  return [
    gpa == null ? 'GPA 暂无结果' : 'GPA：${gpa.toStringAsFixed(1)}',
    'GPA 计入学分：${summary.gpa.includedCredits.toStringAsFixed(1)}',
    '已获学分：${summary.earnedCredits.toStringAsFixed(1)}',
    if (summary.gpa.unknownCreditCount > 0)
      'GPA 学分未知：${summary.gpa.unknownCreditCount} 门',
    if (summary.unknownEarnedCreditCount > 0)
      '获得学分未知：${summary.unknownEarnedCreditCount} 门',
  ].join(' · ');
}
