import 'package:celechron/manual/migration/task_converter.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/model/todo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const converter = LegacyTaskConverter();

  test('copies legacy task without changing ID, progress, or status', () {
    final legacy = _legacyTask();
    final converted =
        converter.convert(legacyTasks: [legacy], todos: []).tasks.single;

    expect(converted.uid, legacy.uid);
    expect(converted.status, TaskStatus.suspended);
    expect(converted.timeSpent, const Duration(minutes: 37));
    expect(converted.timeNeeded, const Duration(hours: 2));
    expect(converted.getProgress(), legacy.getProgress());
    expect(identical(converted, legacy), isFalse);
  });

  test('Todo creates stable unestimated coursework preserving course text', () {
    final todo = _todo('todo-17');
    final first = converter.convert(legacyTasks: [], todos: [todo]);
    final second = converter.convert(legacyTasks: [], todos: [todo]);

    expect(first.tasks, hasLength(1));
    final task = first.tasks.single;
    expect(task.uid, second.tasks.single.uid);
    expect(task.uid, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(task.isCoursework, isTrue);
    expect(task.isTimeEstimated, isFalse);
    expect(task.timeSpent, Duration.zero);
    expect(task.courseId, isNull);
    expect(task.summary, '报告 · 数据结构');
    expect(first.reviewItems, contains(contains('未猜测关联')));
  });

  test('identical duplicate Todo source IDs are deduplicated', () {
    final todo = _todo('todo-17');
    final result =
        converter.convert(legacyTasks: [], todos: [todo, _todo('todo-17')]);

    expect(result.tasks, hasLength(1));
    expect(result.unresolvedTodos, isEmpty);
  });

  test('conflicting duplicate and missing due date are reported', () {
    final result = converter.convert(
      legacyTasks: [],
      todos: [
        _todo('todo-17'),
        _todo('todo-17', name: '另一个标题'),
        _todo('todo-18', missingDue: true)
      ],
    );

    expect(result.tasks, hasLength(1));
    expect(result.unresolvedTodos, hasLength(2));
  });
}

Task _legacyTask() => Task(
      uid: 'legacy-task-8',
      status: TaskStatus.suspended,
      description: '原描述',
      timeSpent: const Duration(minutes: 37),
      timeNeeded: const Duration(hours: 2),
      endTime: DateTime(2025, 4, 12, 18),
      location: '图书馆',
      summary: '旧任务',
      type: TaskType.deadline,
      startTime: DateTime(2025, 4, 1),
      repeatEndsTime: DateTime(2025, 4, 12),
    );

Todo _todo(
  String id, {
  String name = '报告',
  DateTime? due,
  bool missingDue = false,
}) =>
    Todo.fromJson({
      'id': id,
      'title': name,
      'course_name': '数据结构',
      if (!missingDue)
        'end_time': (due ?? DateTime(2025, 4, 12, 23, 59)).toIso8601String(),
    });
