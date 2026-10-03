import 'dart:convert';
import 'dart:io';

import 'package:celechron/debug/manual_preview_generation_access.dart';
import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/data/storage_generation.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/service/candidate_backup_restore_service.dart';
import 'package:celechron/manual/service/manual_preview_restore_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

String _backup({int revision = 77}) => jsonEncode({
      'format': 'celechron-manual-backup',
      'backupVersion': 1,
      'exportedAt': '2026-10-02T12:00:00.000Z',
      'revisions': {'academic': revision, 'taskPlanning': 9},
      'academic':
          AcademicProfile(schemaVersion: 1, revision: revision).toJson(),
      'tasks': <Object?>[],
      'settings': {'schemaVersion': 1, 'values': <String, Object?>{}},
    });

void main() {
  late Directory documents;
  late StorageGenerationManifest legacy;
  late ManualPreviewGenerationAccess access;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('preview-restore-');
    legacy = StorageGenerationManifest.legacyActive(
      rootDirectory: '${documents.path}/celechron_manual_preview',
    );
    await Directory(legacy.rootDirectory).create(recursive: true);
    Hive.init(legacy.rootDirectory);
    access = await ManualPreviewGenerationAccess.openAt(documents.path);
    await access.academicRepository.save(
      AcademicProfile(schemaVersion: 1, revision: 0),
    );
  });

  tearDown(() async {
    await Hive.close();
    await documents.delete(recursive: true);
  });

  test('saves current backup, commits verified candidate and restarts on it',
      () async {
    final outcome = await ManualPreviewRestoreCoordinator(access: access)
        .restoreAndActivate(_backup());

    expect(await File(outcome.preRestoreBackupPath).exists(), isTrue);
    final savedBackup = jsonDecode(
      await File(outcome.preRestoreBackupPath).readAsString(),
    ) as Map;
    expect((savedBackup['academic'] as Map)['revision'], 1);
    expect(outcome.candidate.academicRevision, 77);
    expect(outcome.activeGeneration.generationId,
        outcome.candidate.generation.generationId);

    await Hive.close();
    Hive.init(legacy.rootDirectory);
    final restarted =
        await ManualPreviewGenerationAccess.openAt(documents.path);
    expect(restarted.generation.generationId,
        outcome.activeGeneration.generationId);
    expect((await restarted.academicRepository.read()).revision, 77);

    final oldRepository = await AcademicRepository.open(
      boxName: legacy.academicBoxName,
      path: legacy.academicLocation,
    );
    expect((await oldRepository.read()).revision, 1);
  });

  test('candidate failure keeps the legacy active generation selected',
      () async {
    final coordinator = ManualPreviewRestoreCoordinator(
      access: access,
      candidateRestore: CandidateBackupRestoreService(
        afterCandidateWrite: () async => throw StateError('interrupted'),
      ),
    );

    await expectLater(
      coordinator.restoreAndActivate(_backup()),
      throwsA(isA<Exception>()),
    );
    final restarted =
        await ManualPreviewGenerationAccess.openAt(documents.path);
    expect(restarted.generation.generationId, legacy.generationId);
    expect((await restarted.academicRepository.read()).revision, 1);
    expect(
      Directory('${legacy.rootDirectory}/recovery-backups').listSync(),
      isNotEmpty,
    );
  });

  test('invalid backup is rejected before saving or selecting anything',
      () async {
    await expectLater(
      ManualPreviewRestoreCoordinator(access: access)
          .restoreAndActivate('{bad json'),
      throwsA(isA<Exception>()),
    );
    expect(
      Directory('${legacy.rootDirectory}/recovery-backups').existsSync(),
      isFalse,
    );
    final restarted =
        await ManualPreviewGenerationAccess.openAt(documents.path);
    expect(restarted.generation.generationId, legacy.generationId);
    expect((await restarted.academicRepository.read()).revision, 1);
  });
}
