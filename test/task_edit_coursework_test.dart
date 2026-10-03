import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/page/task/task_edit_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

const _courseId = '20000000-0000-4000-8000-000000000001';

LocalCourse _course() => LocalCourse(
      id: _courseId,
      semesterId: '20000000-0000-4000-8000-000000000002',
      name: '数据库',
    );

Task _task() {
  final end = DateTime(2030, 1, 1, 17);
  return Task(
    uid: 'task-form-test',
    description: 'task form test',
    summary: '完成报告',
    endTime: end,
    startTime: end.subtract(const Duration(hours: 1)),
    repeatEndsTime: DateTime(2030, 1, 1),
  );
}

Future<void> _openEditor(
  WidgetTester tester,
  Task task, {
  TaskCourseLoader? courseLoader,
  required ValueChanged<Task?> onResult,
}) async {
  await tester.pumpWidget(
    CupertinoApp(
      home: Builder(
        builder: (context) => CupertinoPageScaffold(
          child: CupertinoButton(
            onPressed: () async {
              final result = await Navigator.of(context).push<Task>(
                CupertinoPageRoute(
                  builder: (_) =>
                      TaskEditPage(task, courseLoader: courseLoader),
                ),
              );
              onResult(result);
            },
            child: const Text('打开任务编辑'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开任务编辑'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('coursework can be saved with only a title and due date',
      (tester) async {
    final task = _task();
    Task? saved;
    await _openEditor(
      tester,
      task,
      courseLoader: () async => [_course()],
      onResult: (result) => saved = result,
    );

    await tester.tap(find.byKey(const ValueKey('task-coursework-switch')));
    await tester.pumpAndSettle();
    expect(find.text('尚未估时'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('task-edit-save')));
    await tester.pumpAndSettle();

    expect(saved?.isCoursework, isTrue);
    expect(saved?.courseId, isNull);
    expect(saved?.isTimeEstimated, isFalse);
    expect(saved?.timeNeeded, Duration.zero);
    expect(saved?.summary, '完成报告');
    expect(task.isCoursework, isFalse);
    expect(task.isTimeEstimated, isTrue);
  });

  testWidgets('coursework can select a course and estimate its workload',
      (tester) async {
    final task = _task();
    Task? returned;
    await _openEditor(
      tester,
      task,
      courseLoader: () async => [_course()],
      onResult: (result) => returned = result,
    );
    await tester.tap(find.byKey(const ValueKey('task-coursework-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-course-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('数据库').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-estimate-switch')));
    await tester.pumpAndSettle();
    expect(find.text('预期用时'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('task-edit-save')));
    await tester.pumpAndSettle();

    expect(returned?.isCoursework, isTrue);
    expect(returned?.courseId, _courseId);
    expect(returned?.isTimeEstimated, isTrue);
    expect(returned?.timeNeeded, const Duration(hours: 1));
    expect(returned?.summary, '完成报告');
    expect(task.courseId, isNull);
  });

  testWidgets('reminder preference can be saved and disabled independently',
      (tester) async {
    final task = _task()
      ..timeSpent = const Duration(minutes: 12)
      ..reminderEnabled = true
      ..reminderOffset = const Duration(minutes: 30);
    Task? returned;
    await _openEditor(
      tester,
      task,
      courseLoader: () async => const [],
      onResult: (result) => returned = result,
    );

    await tester.tap(find.byKey(const ValueKey('task-reminder-offset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-reminder-offset-1440')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-edit-save')));
    await tester.pumpAndSettle();

    expect(returned?.reminderEnabled, isTrue);
    expect(returned?.reminderOffset, const Duration(days: 1));
    expect(task.reminderOffset, const Duration(minutes: 30));

    await _openEditor(
      tester,
      returned!,
      courseLoader: () async => const [],
      onResult: (result) => returned = result,
    );
    await tester.tap(find.byKey(const ValueKey('task-reminder-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-edit-save')));
    await tester.pumpAndSettle();

    expect(returned?.reminderEnabled, isFalse);
    expect(returned?.reminderOffset, const Duration(days: 1));
    expect(returned?.summary, '完成报告');
    expect(returned?.endTime, DateTime(2030, 1, 1, 17));
    expect(returned?.timeSpent, const Duration(minutes: 12));
  });
}
