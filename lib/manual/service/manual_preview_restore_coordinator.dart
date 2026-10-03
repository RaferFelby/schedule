import 'dart:io';
import 'dart:math';

import 'package:hive/hive.dart';

import '../../debug/manual_preview_generation_access.dart';
import '../../debug/manual_preview_task_store.dart';
import '../data/generation_selection_store.dart';
import '../data/local_data_error.dart';
import '../data/storage_generation.dart';
import 'backup_preview_service.dart';
import 'backup_service.dart';
import 'candidate_backup_restore_service.dart';

final class ManualPreviewRestoreOutcome {
  const ManualPreviewRestoreOutcome({
    required this.activeGeneration,
    required this.candidate,
    required this.preRestoreBackupPath,
  });

  final StorageGenerationManifest activeGeneration;
  final CandidateRestoreResult candidate;
  final String preRestoreBackupPath;
}

/// Coordinates pre-restore backup, candidate validation and pointer commit.
final class ManualPreviewRestoreCoordinator {
  const ManualPreviewRestoreCoordinator({
    required this.access,
    this.candidateRestore = const CandidateBackupRestoreService(),
    this.hive,
    this.random,
  });

  final ManualPreviewGenerationAccess access;
  final CandidateBackupRestoreService candidateRestore;
  final HiveInterface? hive;
  final Random? random;

  Future<ManualPreviewRestoreOutcome> restoreAndActivate(
    String backupJson,
  ) async {
    final previewResult = const BackupPreviewService().previewJson(backupJson);
    if (!previewResult.isValid) {
      throw LocalDataValidationError(
        '备份校验未通过：${previewResult.errors.join('；')}',
      );
    }
    final beforeRestore = await BackupService(
      academic: access.academicRepository,
      tasks: ManualPreviewTaskStore(access.previewBox),
    ).exportJson();
    final backupDirectory =
        Directory('${access.generation.rootDirectory}/recovery-backups');
    await backupDirectory.create(recursive: true);
    final unique = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final backupFile =
        File('${backupDirectory.path}/pre-restore-$stamp-$unique.json');
    await backupFile.create(exclusive: true);
    await backupFile.writeAsString(beforeRestore, flush: true);

    final generationId = 'restore-$stamp-$unique';
    final candidate = StorageGenerationManifest.candidateFor(
      active: access.generation,
      generationId: generationId,
    );
    final candidateResult = await candidateRestore.restoreCandidate(
      backupJson: backupJson,
      active: access.generation,
      candidate: candidate,
      hive: hive,
    );
    final committed = await GenerationSelectionStore(
      rootDirectory: access.generation.rootDirectory,
      hive: hive,
    ).commitCandidate(
      currentActive: access.generation,
      candidate: candidateResult.generation,
    );
    return ManualPreviewRestoreOutcome(
      activeGeneration: committed.active,
      candidate: candidateResult,
      preRestoreBackupPath: backupFile.path,
    );
  }

  Random get _random => random ?? Random.secure();
}
