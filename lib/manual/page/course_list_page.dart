import 'package:flutter/cupertino.dart';
import 'package:hive/hive.dart';

import '../controller/academic_controller.dart';
import '../data/academic_repository.dart';
import '../model/local_course.dart';
import '../model/local_semester.dart';
import 'course_edit_page.dart';
import 'course_detail_page.dart';

/// Lists only the courses belonging to the selected semester.
final class CourseListPage extends StatefulWidget {
  const CourseListPage({
    super.key,
    required this.repository,
    required this.semester,
    this.previewBox,
  });

  final AcademicRepository repository;
  final LocalSemester semester;
  final Box<String>? previewBox;

  @override
  State<CourseListPage> createState() => _CourseListPageState();
}

final class _CourseListPageState extends State<CourseListPage> {
  late Future<List<LocalCourse>> _courses;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _courses = _readCourses();
  }

  Future<List<LocalCourse>> _readCourses() async {
    final profile = await widget.repository.read();
    final courses = profile.courses
        .where((course) => course.semesterId == widget.semester.id)
        .toList()
      ..sort((left, right) {
        final byName = left.name.compareTo(right.name);
        return byName == 0 ? left.id.compareTo(right.id) : byName;
      });
    return courses;
  }

  Future<void> _addCourse() async {
    await _openCourseForm();
  }

  Future<void> _openCourseForm() async {
    if (_adding) return;
    setState(() => _adding = true);
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
          ),
        ),
      );
      if (saved == true && mounted) {
        final refreshedCourses = _readCourses();
        setState(() {
          _courses = refreshedCourses;
        });
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _openDetails(LocalCourse course) async {
    await Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (_) => CourseDetailPage(
          repository: widget.repository,
          semester: widget.semester,
          course: course,
          previewBox: widget.previewBox,
        ),
      ),
    );
    if (mounted) {
      final refreshedCourses = _readCourses();
      setState(() {
        _courses = refreshedCourses;
      });
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          previousPageTitle: '学期',
          middle: Text(widget.semester.name),
          trailing: CupertinoButton(
            key: const ValueKey('course-add'),
            padding: EdgeInsets.zero,
            onPressed: _adding ? null : _addCourse,
            child: const Text('新增'),
          ),
        ),
        child: SafeArea(
          child: FutureBuilder<List<LocalCourse>>(
            future: _courses,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CupertinoActivityIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('读取课程失败：${snapshot.error}'));
              }
              final courses = snapshot.data!;
              if (courses.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('这个学期还没有课程'),
                      const SizedBox(height: 8),
                      const Text('课程会按所属学期显示在这里。'),
                      const SizedBox(height: 12),
                      CupertinoButton.filled(
                        onPressed: _adding ? null : _addCourse,
                        child: const Text('新增课程'),
                      ),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: courses.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) => _CourseRow(
                  key: ValueKey('course-${courses[index].id}'),
                  course: courses[index],
                  onTap: () => _openDetails(courses[index]),
                ),
              );
            },
          ),
        ),
      );
}

final class _CourseRow extends StatelessWidget {
  const _CourseRow({super.key, required this.course, required this.onTap});

  final LocalCourse course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CupertinoButton(
        key: ValueKey('edit-course-${course.id}'),
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Container(
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
              Text(course.name,
                  style: CupertinoTheme.of(context).textTheme.textStyle),
              const SizedBox(height: 6),
              Text('教师：${course.teacher ?? '未填写'}'),
              Text('学分：${course.credits?.toString() ?? '未填写'}'),
            ],
          ),
        ),
      );
}
