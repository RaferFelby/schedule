import 'dart:convert';

import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/page/backup_preview_page.dart';
import 'package:celechron/manual/service/backup_preview_service.dart';
import 'package:celechron/manual/service/backup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const semesterId = '10000000-0000-4000-8000-000000000001';
const courseId = '20000000-0000-4000-8000-000000000001';

Map<String, Object?> _task({
  String uid = 'task-1',
  String? linkedCourse = courseId,
}) =>
    {
      'uid': uid,
      'status': 0,
      'description': '作业说明',
      'timeSpent': 0,
      'timeNeeded': 3600000000,
      'endTime': '2026-10-20T18:00:00.000',
      'location': '',
      'summary': '作业一',
      'isBreakable': true,
      'type': 0,
      'startTime': '2026-10-01T08:00:00.000',
      'repeatType': 0,
      'repeatPeriod': 1,
      'repeatEndsTime': '2026-10-20T00:00:00.000',
      'blockArrangements': true,
      'fromUid': null,
      'courseId': linkedCourse,
      'isCoursework': true,
      'isTimeEstimated': true,
      'reminderEnabled': true,
      'reminderOffset': 900000000,
    };

AcademicProfile _profile() => AcademicProfile(
      schemaVersion: 1,
      revision: 7,
      currentSemesterId: semesterId,
      semesters: [
        LocalSemester(
          id: semesterId,
          name: '2026 秋季',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2027, 1, 31),
          weekOneStart: DateTime(2026, 9, 7),
        ),
      ],
      courses: [
        LocalCourse(
          id: courseId,
          semesterId: semesterId,
          name: '数据结构',
        ),
      ],
    );

Map<String, Object?> _backup({
  int version = 1,
  List<Map<String, Object?>> tasks = const [],
  Map<String, Object?>? academic,
  Map<String, Object?> settings = const {'schemaVersion': 1, 'values': {}},
}) =>
    {
      'format': BackupService.formatName,
      'backupVersion': version,
      'exportedAt': '2026-10-02T12:00:00.000Z',
      'revisions': {'academic': 7, 'taskPlanning': 5},
      'academic': academic ?? _profile().toJson(),
      'tasks': tasks,
      'settings': settings,
    };

void main() {
  test('valid backup reports counts and matching revisions without storage',
      () {
    final result = const BackupPreviewService().previewJson(
      jsonEncode(_backup(tasks: [_task()])),
    );

    expect(result.isValid, isTrue);
    expect(result.backupVersion, 1);
    expect(result.academicRevision, 7);
    expect(result.taskPlanningRevision, 5);
    expect(result.recordCounts, {
      'semesters': 1,
      'courses': 1,
      'sessionRules': 0,
      'exams': 0,
      'grades': 0,
      'practiceRecords': 0,
      'tasks': 1,
      'settings': 0,
    });
  });

  test('reports malformed JSON and unsupported future versions', () {
    const service = BackupPreviewService();
    expect(service.previewJson('{broken').errors, contains('文件不是有效的 JSON'));
    expect(
      service.previewJson(jsonEncode(_backup(version: 2))).errors,
      contains('备份版本 2 高于当前支持版本'),
    );
  });

  test('rejects invalid migrated preferences before restore', () {
    final result = const BackupPreviewService().previewJson(jsonEncode(_backup(
      settings: {
        'schemaVersion': 1,
        'values': {
          'theme': 'dark',
          'workMinutes': 25,
          'restMinutes': 5,
          'availableWindows': [
            {'startMinutes': 600, 'endMinutes': 700},
            {'startMinutes': 650, 'endMinutes': 720},
          ],
        },
      },
    )));

    expect(result.isValid, isFalse);
    expect(result.errors, contains(contains('可用时段不能重叠')));
  });

  test('keeps legacy generic theme settings compatible', () {
    final result = const BackupPreviewService().previewJson(jsonEncode(_backup(
      settings: {
        'schemaVersion': 1,
        'values': {'theme': 'dark', 'plannerHorizonDays': 14},
      },
    )));

    expect(result.isValid, isTrue);
  });

  test(
      'reports duplicate task IDs, dangling course refs, and sensitive settings',
      () {
    final result = const BackupPreviewService().previewJson(jsonEncode(_backup(
      tasks: [
        _task(),
        _task(
            uid: 'task-1',
            linkedCourse: '30000000-0000-4000-8000-000000000001'),
      ],
      settings: const {
        'schemaVersion': 1,
        'values': {'accessToken': 'excluded'},
      },
    )));

    expect(result.isValid, isFalse);
    expect(result.errors, contains('任务 ID 重复'));
    expect(result.errors, contains('任务引用了备份中不存在的课程'));
    expect(result.errors, contains('设置包含不可导出的敏感字段'));
  });

  testWidgets(
      'backup preview page shows summary and errors without a restore action',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home:
          BackupPreviewPage(initialJson: jsonEncode(_backup(tasks: [_task()]))),
    ));
    await tester.tap(find.text('校验备份'));
    await tester.pumpAndSettle();

    expect(find.text('备份校验通过'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data?.contains('课程：1') == true,
      ),
      findsOneWidget,
    );
    expect(find.text('恢复'), findsNothing);
  });

  testWidgets('restore confirmation cancel never invokes the restore writer',
      (tester) async {
    var restoreCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: BackupPreviewPage(
        initialJson: jsonEncode(_backup(tasks: [_task()])),
        onRestore: (_) async {
          restoreCalls++;
        },
      ),
    ));
    await tester.tap(find.text('校验备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复并替换本地数据'));
    await tester.pumpAndSettle();

    expect(find.text('替换当前本地数据？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(restoreCalls, 0);
  });
}
