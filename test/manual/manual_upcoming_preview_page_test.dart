import 'dart:convert';

import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/local_exam.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/model/session_rule.dart';
import 'package:celechron/manual/model/time_slot.dart';
import 'package:celechron/manual/page/manual_upcoming_preview_page.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/manual/service/local_upcoming_schedule_planner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Store implements AcademicProfileStore {
  _Store(this.value);
  String value;

  @override
  Future<String?> readSnapshot() async => value;

  @override
  Future<void> writeSnapshot(String encoded) async {}
}

const _semesterId = '10000000-0000-4000-8000-000000000001';
const _courseId = '20000000-0000-4000-8000-000000000001';

AcademicProfile _profile() => AcademicProfile(
      schemaVersion: 1,
      revision: 0,
      currentSemesterId: _semesterId,
      semesters: [
        LocalSemester(
          id: _semesterId,
          name: '本地学期',
          startDate: DateTime(2026, 9, 28),
          endDate: DateTime(2026, 11, 30),
          weekOneStart: DateTime(2026, 9, 28),
        ),
      ],
      timeSlots: TimeSlot.defaultTemplate(),
      courses: [
        LocalCourse(
          id: _courseId,
          semesterId: _semesterId,
          name: '数据库',
        ),
      ],
      sessionRules: [
        SessionRule(
          id: '30000000-0000-4000-8000-000000000001',
          courseId: _courseId,
          weekday: DateTime.tuesday,
          weekNumbers: [2],
          startSlotOrdinal: 1,
          endSlotOrdinal: 1,
        ),
      ],
      exams: [
        LocalExam(
          id: '40000000-0000-4000-8000-000000000001',
          courseId: _courseId,
          type: '期中考试',
          start: DateTime(2026, 10, 4, 13),
          end: DateTime(2026, 10, 4, 14),
          location: '教学楼 201',
        ),
      ],
    );

void main() {
  final now = DateTime(2026, 10, 2, 12);

  testWidgets('refresh reads courses added while another tab was open',
      (tester) async {
    final store = _Store(jsonEncode(
      AcademicProfile(schemaVersion: 1, revision: 0).toJson(),
    ));
    final key = GlobalKey<ManualUpcomingPreviewPageState>();
    await tester.pumpWidget(MaterialApp(
        home: ManualUpcomingPreviewPage(
      key: key,
      repository: AcademicRepository(store),
      now: () => now,
    )));
    await tester.pumpAndSettle();
    expect(find.text('数据库'), findsNothing);
    store.value = jsonEncode(_profile().toJson());
    await key.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(find.text('数据库'), findsOneWidget);
  });

  testWidgets('empty academic profile offers create or skip actions',
      (tester) async {
    var createSemester = 0;
    var skipToTasks = 0;
    final repository = AcademicRepository(_Store(jsonEncode(
      AcademicProfile(schemaVersion: 1, revision: 0).toJson(),
    )));

    await tester.pumpWidget(MaterialApp(
      home: ManualUpcomingPreviewPage(
        repository: repository,
        now: () => now,
        onOpenSemesters: () => createSemester++,
        onOpenTasks: () => skipToTasks++,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('先创建学期，也可以稍后再建'), findsOneWidget);
    expect(find.text('跳过，先添加任务'), findsOneWidget);
    expect(find.textContaining('登录'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('first-use-create-semester')));
    await tester.tap(find.byKey(const ValueKey('first-use-skip-to-tasks')));
    expect(createSemester, 1);
    expect(skipToTasks, 1);
  });

  testWidgets('a regular task remains usable before creating a semester',
      (tester) async {
    final task = Task(
      uid: 'first-use-regular-task',
      summary: '先完成普通任务',
      startTime: now,
      endTime: now.add(const Duration(days: 1)),
      repeatEndsTime: DateTime(2026, 10, 3),
      isCoursework: false,
      isTimeEstimated: true,
      timeNeeded: const Duration(minutes: 30),
    );
    final repository = AcademicRepository(_Store(jsonEncode(
      AcademicProfile(schemaVersion: 1, revision: 0).toJson(),
    )));

    await tester.pumpWidget(MaterialApp(
      home: ManualUpcomingPreviewPage(
        repository: repository,
        taskLoader: () async => [task],
        now: () => now,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('先完成普通任务'), findsNWidgets(2));
    expect(find.text('跳过，先添加任务'), findsOneWidget);
  });

  testWidgets('upcoming preview reads local classes and timed exams',
      (tester) async {
    final repository =
        AcademicRepository(_Store(jsonEncode(_profile().toJson())));
    final periods =
        await const LocalUpcomingSchedulePlanner().readPeriods(repository);
    expect(periods.map((period) => period.type), [
      PeriodType.test,
      PeriodType.classes,
    ]);

    await tester.pumpWidget(MaterialApp(
      home: ManualUpcomingPreviewPage(
        repository: repository,
        now: () => now,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('数据库'), findsOneWidget);
    expect(find.text('数据库 · 期中考试'), findsOneWidget);
    expect(find.textContaining('2026-10-04 13:00–14:00'), findsOneWidget);
  });

  testWidgets('local task plan starts after the occupied class period',
      (tester) async {
    final task = Task(
      uid: 'task-local-plan',
      summary: '完成作业',
      endTime: DateTime(2026, 10, 6, 9, 30),
      startTime: DateTime(2026, 10, 6, 7),
      repeatEndsTime: DateTime(2026, 10, 6),
      timeNeeded: const Duration(minutes: 10),
      isTimeEstimated: true,
    );

    await tester.pumpWidget(MaterialApp(
      home: ManualUpcomingPreviewPage(
        repository: AcademicRepository(_Store(jsonEncode(_profile().toJson()))),
        taskLoader: () async => [task],
        now: () => DateTime(2026, 10, 6, 7),
        horizon: const Duration(hours: 2),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('完成作业'), findsNWidgets(2));
    expect(find.textContaining('2026-10-06 08:45–08:55'), findsOneWidget);
    expect(find.textContaining('数据库'), findsOneWidget);
  });
}
