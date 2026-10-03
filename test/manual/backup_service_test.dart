import 'dart:convert';
import 'dart:io';

import 'package:celechron/debug/manual_preview_storage.dart';
import 'package:celechron/debug/manual_preview_task_store.dart';
import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/service/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

final class _ProfileStore implements AcademicProfileStore {
  _ProfileStore(this.encoded);
  final String encoded;

  @override
  Future<String?> readSnapshot() async => encoded;

  @override
  Future<void> writeSnapshot(String value) async {}
}

AcademicProfile _profile() => AcademicProfile(
      schemaVersion: 1,
      revision: 8,
      planningRevision: 3,
      currentSemesterId: '10000000-0000-4000-8000-000000000001',
      semesters: [
        LocalSemester(
          id: '10000000-0000-4000-8000-000000000001',
          name: '2026 秋季',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2027, 1, 31),
          weekOneStart: DateTime(2026, 9, 7),
        ),
      ],
      courses: [
        LocalCourse(
          id: '20000000-0000-4000-8000-000000000001',
          semesterId: '10000000-0000-4000-8000-000000000001',
          name: '数据结构',
          credits: 3,
        ),
      ],
    );

Map<String, Object?> _taskJson() => {
      'uid': 'task-1',
      'status': 0,
      'description': '复习树与图',
      'timeSpent': 1200000,
      'timeNeeded': 7200000000,
      'endTime': '2026-10-20T18:00:00.000',
      'location': '',
      'summary': '数据结构作业',
      'isBreakable': true,
      'type': 0,
      'startTime': '2026-10-01T08:00:00.000',
      'repeatType': 0,
      'repeatPeriod': 1,
      'repeatEndsTime': '2026-10-20T00:00:00.000',
      'blockArrangements': true,
      'fromUid': null,
      'courseId': '20000000-0000-4000-8000-000000000001',
      'isCoursework': true,
      'isTimeEstimated': true,
      'reminderEnabled': true,
      'reminderOffset': 900000000,
    };

Set<String> _collectKeys(Object? value) {
  if (value is Map) {
    return {
      ...value.keys.whereType<String>().map((key) => key.toLowerCase()),
      for (final nested in value.values) ..._collectKeys(nested),
    };
  }
  if (value is Iterable) {
    return {for (final nested in value) ..._collectKeys(nested)};
  }
  return const {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box<String> previewBox;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('backup-service-');
    Hive.init(directory.path);
    previewBox = await Hive.openBox<String>(ManualPreviewStorage.boxName);
    await previewBox.put(
      ManualPreviewStorage.homeworkKey,
      jsonEncode([_taskJson()]),
    );
    await previewBox.put(ManualPreviewStorage.taskPlanningRevisionKey, '7');
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('exports versioned academic, task, revisions and settings snapshot',
      () async {
    final profile = _profile();
    final service = BackupService(
      academic: AcademicRepository(_ProfileStore(jsonEncode(profile.toJson()))),
      tasks: ManualPreviewTaskStore(previewBox),
    );
    final decoded = jsonDecode(await service.exportJson(
      settings: const {'theme': 'dark', 'plannerHorizonDays': 14},
      exportedAt: DateTime.utc(2026, 10, 2),
    )) as Map<String, dynamic>;
    final academics = decoded['academic'] as Map<String, dynamic>;
    final task = (decoded['tasks'] as List).single as Map<String, dynamic>;

    expect(decoded['format'], BackupService.formatName);
    expect(decoded['backupVersion'], 1);
    expect(decoded['exportedAt'], '2026-10-02T00:00:00.000Z');
    expect(decoded['revisions'], {'academic': 8, 'taskPlanning': 7});
    expect(academics['revision'], 8);
    expect(
      (academics['courses'] as List).single['id'],
      '20000000-0000-4000-8000-000000000001',
    );
    expect(task['uid'], 'task-1');
    expect(task['courseId'], '20000000-0000-4000-8000-000000000001');
    expect(task['reminderEnabled'], isTrue);
    expect(task['reminderOffset'], 900000000);
    expect(decoded['settings'], {
      'schemaVersion': 1,
      'values': {'theme': 'dark', 'plannerHorizonDays': 14},
    });
    final allKeys = _collectKeys(decoded);
    for (final forbidden in [
      'password',
      'token',
      'account',
      'credentials',
      'logs',
      'response',
      'webcache',
    ]) {
      expect(allKeys, isNot(contains(forbidden)));
    }
    expect(decoded.containsKey('calendarMappings'), isFalse);
  });

  test('rejects nested credential and legacy cache fields in settings',
      () async {
    final service = BackupService(
      academic:
          AcademicRepository(_ProfileStore(jsonEncode(_profile().toJson()))),
      tasks: ManualPreviewTaskStore(previewBox),
    );

    await expectLater(
      service.exportJson(settings: const {
        'display': {'theme': 'dark', 'sessionToken': 'must not export'},
      }),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      service.exportJson(settings: const {'oldWebCache': '<html>...'}),
      throwsA(isA<FormatException>()),
    );
  });
}
