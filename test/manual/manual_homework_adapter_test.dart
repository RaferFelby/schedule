import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/service/manual_homework_adapter.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter_test/flutter_test.dart';

const _courseId = '20000000-0000-4000-8000-000000000001';

LocalCourse _course(String name) => LocalCourse(
      id: _courseId,
      semesterId: '20000000-0000-4000-8000-000000000002',
      name: name,
    );

Task _task({
  required String uid,
  required DateTime deadline,
  TaskStatus status = TaskStatus.running,
  bool coursework = true,
  String? courseId = _courseId,
  TaskType type = TaskType.deadline,
}) =>
    Task(
      uid: uid,
      summary: '报告 $uid',
      endTime: deadline,
      startTime: deadline.subtract(const Duration(hours: 1)),
      repeatEndsTime: DateTime(deadline.year, deadline.month, deadline.day),
      status: status,
      type: type,
      isCoursework: coursework,
      courseId: courseId,
    );

void main() {
  final now = DateTime(2026, 10, 2, 12);

  test('filters by coursework, association and unfinished status, then sorts',
      () {
    final items = ManualHomeworkAdapter.pending(
      tasks: [
        _task(uid: 'later', deadline: now.add(const Duration(days: 2))),
        _task(uid: 'done', deadline: now, status: TaskStatus.completed),
        _task(uid: 'first', deadline: now.add(const Duration(hours: 1))),
        _task(uid: 'unlinked', deadline: now, courseId: null),
        _task(uid: 'ordinary', deadline: now, coursework: false),
        _task(uid: 'fixed', deadline: now, type: TaskType.fixed),
        _task(uid: 'deleted', deadline: now, status: TaskStatus.deleted),
        _task(uid: 'suspended', deadline: now, status: TaskStatus.suspended),
        _task(
            uid: 'overdue',
            deadline: now.subtract(const Duration(days: 1)),
            status: TaskStatus.failed),
      ],
      courses: [_course('数据库')],
    );

    expect(items.map((item) => item.task.uid), [
      'overdue',
      'suspended',
      'first',
      'later',
    ]);
    expect(items.first.courseName, '数据库');
  });

  test('resolves renamed courses by ID and counts deadlines within a window',
      () {
    final items = ManualHomeworkAdapter.pending(
      tasks: [
        _task(uid: 'overdue', deadline: now.subtract(const Duration(days: 2))),
        _task(uid: 'soon', deadline: now.add(const Duration(hours: 8))),
        _task(uid: 'later', deadline: now.add(const Duration(days: 3))),
      ],
      courses: [_course('已改名的数据库课')],
    );

    expect(items.map((item) => item.courseName).toSet(), {'已改名的数据库课'});
    expect(
      ManualHomeworkAdapter.pending(
        tasks: items.map((item) => item.task),
        courses: [_course('已改名的数据库课')],
        courseId: _courseId,
      ),
      hasLength(3),
    );
    expect(
      ManualHomeworkAdapter.dueWithin(
        items,
        now: now,
        window: const Duration(days: 1),
      ),
      hasLength(2),
    );
    expect(
      ManualHomeworkAdapter.dueWithin(
        items,
        now: now,
        window: const Duration(days: 7),
      ),
      hasLength(3),
    );
  });

  test('pending tasks include unlinked regular deadlines and sort by date', () {
    final tasks = ManualHomeworkAdapter.pendingTasks(
      tasks: [
        _task(uid: 'later', deadline: now.add(const Duration(days: 2))),
        _task(
          uid: 'regular',
          deadline: now.add(const Duration(hours: 1)),
          coursework: false,
          courseId: null,
        ),
        _task(uid: 'completed', deadline: now, status: TaskStatus.completed),
        _task(uid: 'fixed', deadline: now, type: TaskType.fixed),
        _task(uid: 'first', deadline: now),
      ],
    );

    expect(tasks.map((task) => task.uid), ['first', 'regular', 'later']);
    expect(() => tasks.add(_task(uid: 'x', deadline: now)),
        throwsUnsupportedError);
  });
}
