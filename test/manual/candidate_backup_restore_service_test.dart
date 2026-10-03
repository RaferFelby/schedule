import 'dart:convert';
import 'dart:io';

import 'package:celechron/debug/manual_preview_generation_access.dart';
import 'package:celechron/debug/manual_preview_storage.dart';
import 'package:celechron/manual/data/local_data_error.dart';
import 'package:celechron/manual/data/storage_generation.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/service/candidate_backup_restore_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

Map<String, Object?> _task() => {
      'uid': 'restore-task-1',
      'status': 0,
      'description': '候选作业',
      'timeSpent': 0,
      'timeNeeded': 3600000000,
      'endTime': '2026-10-20T18:00:00.000',
      'location': '',
      'summary': '验证候选任务',
      'isBreakable': true,
      'type': 0,
      'startTime': '2026-10-01T08:00:00.000',
      'repeatType': 0,
      'repeatPeriod': 1,
      'repeatEndsTime': '2026-10-20T00:00:00.000',
      'blockArrangements': true,
      'fromUid': null,
      'courseId': null,
      'isCoursework': true,
      'isTimeEstimated': true,
      'reminderEnabled': true,
      'reminderOffset': 900000000,
    };

String _backup(
        {int version = 1, List<Map<String, Object?>> tasks = const []}) =>
    jsonEncode({
      'format': 'celechron-manual-backup',
      'backupVersion': version,
      'exportedAt': '2026-10-02T12:00:00.000Z',
      'revisions': {'academic': 4, 'taskPlanning': 8},
      'academic': AcademicProfile(schemaVersion: 1, revision: 4).toJson(),
      'tasks': tasks,
      'settings': {
        'schemaVersion': 1,
        'values': {'weekStartsOnMonday': true},
      },
    });

void main() {
  late Directory tempDirectory;
  late StorageGenerationManifest active;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('candidate-restore-');
    active = StorageGenerationManifest.legacyActive(
      rootDirectory: '${tempDirectory.path}/celechron_manual_preview',
    );
    await Directory(active.rootDirectory).create(recursive: true);
    Hive.init(active.rootDirectory);
    final access = await ManualPreviewGenerationAccess.openAt(
      tempDirectory.path,
    );
    await access.academicRepository.save(
      AcademicProfile(schemaVersion: 1, revision: 0),
    );
  });

  tearDown(() async {
    await Hive.close();
    await tempDirectory.delete(recursive: true);
  });

  test('writes, closes, reopens and validates an isolated candidate', () async {
    final candidate = StorageGenerationManifest.candidateFor(
      active: active,
      generationId: 'restore-1',
    );

    final result = await const CandidateBackupRestoreService().restoreCandidate(
      backupJson: _backup(tasks: [_task()]),
      active: active,
      candidate: candidate,
    );

    expect(result.generation.generationId, 'restore-1');
    expect(result.academicRevision, 4);
    expect(result.taskPlanningRevision, 8);
    expect(result.taskCount, 1);
    expect(result.settingCount, 1);
    expect(await Directory(candidate.generationDirectory).exists(), isTrue);

    final access = await ManualPreviewGenerationAccess.openAt(
      tempDirectory.path,
    );
    expect((await access.academicRepository.read()).revision, 1);
    expect(access.previewBox.get(ManualPreviewStorage.markerKey),
        ManualPreviewStorage.markerValue);
    expect(Hive.isBoxOpen(candidate.academicBoxName), isFalse);

    final candidateAcademic = await Hive.openBox<String>(
      candidate.academicBoxName,
      path: candidate.academicLocation,
    );
    expect(
      AcademicProfile.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(candidateAcademic.get('snapshot')!) as Map,
        ),
      ).revision,
      4,
    );
    final candidateSettings = await Hive.openBox<String>(
      candidate.settingsBoxName,
      path: candidate.settingsLocation,
    );
    expect(jsonDecode(candidateSettings.get('values')!), {
      'weekStartsOnMonday': true,
    });
    final candidateTasks = await Hive.openBox<String>(
      candidate.taskBoxName,
      path: candidate.taskLocation,
    );
    final restoredTasks = jsonDecode(
      candidateTasks.get(ManualPreviewStorage.homeworkKey)!,
    ) as List;
    expect(restoredTasks, hasLength(1));
    expect((restoredTasks.single as Map)['uid'], 'restore-task-1');
    expect((restoredTasks.single as Map)['reminderEnabled'], isTrue);
  });

  test('rejects invalid backup before creating a candidate directory',
      () async {
    final candidate = StorageGenerationManifest.candidateFor(
      active: active,
      generationId: 'invalid-1',
    );

    await expectLater(
      const CandidateBackupRestoreService().restoreCandidate(
        backupJson: _backup(version: 2),
        active: active,
        candidate: candidate,
      ),
      throwsA(isA<LocalDataValidationError>()),
    );
    expect(await Directory(candidate.generationDirectory).exists(), isFalse);
    final access = await ManualPreviewGenerationAccess.openAt(
      tempDirectory.path,
    );
    expect((await access.academicRepository.read()).revision, 1);
  });

  test('interrupted candidate write leaves active preview data unchanged',
      () async {
    final candidate = StorageGenerationManifest.candidateFor(
      active: active,
      generationId: 'interrupted-1',
    );
    final service = CandidateBackupRestoreService(
      afterCandidateWrite: () async =>
          throw StateError('simulated interruption'),
    );

    await expectLater(
      service.restoreCandidate(
        backupJson: _backup(tasks: [_task()]),
        active: active,
        candidate: candidate,
      ),
      throwsA(isA<LocalDataStorageError>()),
    );
    expect(await Directory(candidate.generationDirectory).exists(), isTrue);
    final access = await ManualPreviewGenerationAccess.openAt(
      tempDirectory.path,
    );
    expect((await access.academicRepository.read()).revision, 1);
    expect(access.previewBox.get(ManualPreviewStorage.markerKey),
        ManualPreviewStorage.markerValue);
  });
}
