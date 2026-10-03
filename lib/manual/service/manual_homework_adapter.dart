import '../model/local_course.dart';
import '../../model/task.dart';

final class ManualHomeworkItem {
  const ManualHomeworkItem({
    required this.task,
    required this.courseName,
  });

  final Task task;
  final String courseName;
}

/// Resolves coursework by stable course ID and returns unfinished local tasks.
final class ManualHomeworkAdapter {
  const ManualHomeworkAdapter._();

  /// All unfinished deadline tasks, including regular tasks with no course.
  static List<Task> pendingTasks({required Iterable<Task> tasks}) {
    final pending = tasks.where((task) {
      if (task.type != TaskType.deadline) return false;
      return task.status == TaskStatus.running ||
          task.status == TaskStatus.suspended ||
          task.status == TaskStatus.failed;
    }).toList()
      ..sort((left, right) {
        final byDeadline = left.endTime.compareTo(right.endTime);
        return byDeadline != 0 ? byDeadline : left.uid.compareTo(right.uid);
      });
    return List.unmodifiable(pending);
  }

  static List<ManualHomeworkItem> pending({
    required Iterable<Task> tasks,
    required Iterable<LocalCourse> courses,
    String? courseId,
  }) {
    final coursesById = {for (final course in courses) course.id: course};
    final pending = tasks.where((task) {
      if (task.type != TaskType.deadline ||
          !task.isCoursework ||
          task.courseId == null ||
          (courseId != null && task.courseId != courseId)) {
        return false;
      }
      return task.status == TaskStatus.running ||
          task.status == TaskStatus.suspended ||
          task.status == TaskStatus.failed;
    }).toList()
      ..sort((left, right) {
        final byDeadline = left.endTime.compareTo(right.endTime);
        return byDeadline != 0 ? byDeadline : left.uid.compareTo(right.uid);
      });

    return pending
        .map(
          (task) => ManualHomeworkItem(
            task: task,
            courseName: coursesById[task.courseId]?.name ?? '关联课程不可用',
          ),
        )
        .toList(growable: false);
  }

  static List<ManualHomeworkItem> dueWithin(
    Iterable<ManualHomeworkItem> items, {
    required DateTime now,
    required Duration window,
  }) =>
      items
          .where((item) => !item.task.endTime.isAfter(now.add(window)))
          .toList(growable: false);
}
