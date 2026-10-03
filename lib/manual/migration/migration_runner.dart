import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';

import '../../debug/manual_preview_storage.dart';
import '../../debug/manual_preview_task_store.dart';
import '../../model/task.dart';
import '../data/academic_repository.dart';
import '../data/generation_selection_store.dart';
import '../data/storage_generation.dart';
import '../model/academic_profile.dart';
import '../service/backup_service.dart';
import '../service/candidate_backup_restore_service.dart';
import 'migration_validator.dart';

abstract interface class MigrationGenerationWriter {
  /// Must write a candidate without activating it, flush it, and read it back.
  /// Repeating the same generation ID and identical payload must be safe.
  Future<void> writeAndVerify({
    required StorageGenerationManifest candidate,
    required AcademicProfile profile,
    required List<Task> tasks,
    required Map<String, Object?> settings,
  });
}

abstract interface class MigrationGenerationSelector {
  Future<GenerationSelectionResult> selectActive({
    required StorageGenerationManifest fallback,
  });

  Future<GenerationSelectionResult> commitCandidate({
    required StorageGenerationManifest currentActive,
    required StorageGenerationManifest candidate,
  });
}

final class MigrationRunResult {
  const MigrationRunResult({
    required this.active,
    required this.alreadyCommitted,
    required this.validation,
  });

  final StorageGenerationManifest active;
  final bool alreadyCommitted;
  final MigrationValidationReport validation;
}

/// Durable writer backed by the same isolated-generation restore path as backups.
final class CandidateRestoreMigrationWriter
    implements MigrationGenerationWriter {
  const CandidateRestoreMigrationWriter({
    this.restoreService = const CandidateBackupRestoreService(),
    this.hive,
  });

  final CandidateBackupRestoreService restoreService;
  final HiveInterface? hive;

  @override
  Future<void> writeAndVerify({
    required StorageGenerationManifest candidate,
    required AcademicProfile profile,
    required List<Task> tasks,
    required Map<String, Object?> settings,
  }) async {
    final directory = Directory(candidate.generationDirectory);
    if (await directory.exists()) {
      await _verifyExisting(candidate, profile, tasks, settings);
      return;
    }
    final payload = jsonEncode({
      'format': BackupService.formatName,
      'backupVersion': BackupService.backupVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'revisions': {
        'academic': profile.revision,
        'taskPlanning': profile.planningRevision,
      },
      'academic': profile.toJson(),
      'tasks': ManualPreviewTaskStore.encodeTasksForBackup(tasks),
      'settings': {
        'schemaVersion': BackupService.settingsVersion,
        'values': settings,
      },
    });
    await restoreService.restoreCandidate(
      backupJson: payload,
      active: StorageGenerationManifest.active(
        rootDirectory: candidate.rootDirectory,
        generationId: candidate.parentGenerationId!,
      ),
      candidate: candidate,
      hive: hive,
    );
  }

  Future<void> _verifyExisting(
    StorageGenerationManifest candidate,
    AcademicProfile profile,
    List<Task> tasks,
    Map<String, Object?> settings,
  ) async {
    final database = hive ?? Hive;
    Box<String>? academicBox;
    Box<String>? taskBox;
    Box<String>? settingsBox;
    try {
      academicBox = await database.openBox<String>(
        candidate.academicBoxName,
        path: candidate.academicLocation,
      );
      taskBox = await database.openBox<String>(
        candidate.taskBoxName,
        path: candidate.taskLocation,
      );
      settingsBox = await database.openBox<String>(
        candidate.settingsBoxName,
        path: candidate.settingsLocation,
      );
      final savedProfile = AcademicProfile.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(academicBox.get(AcademicRepository.snapshotKey)!) as Map,
        ),
      );
      final savedTasks = ManualPreviewTaskStore.decodeTasksForBackup(
        jsonDecode(taskBox.get(ManualPreviewStorage.homeworkKey)!),
      );
      final savedRevision = int.tryParse(
        taskBox.get(ManualPreviewStorage.taskPlanningRevisionKey) ?? '',
      );
      if (jsonEncode(savedProfile.toJson()) != jsonEncode(profile.toJson()) ||
          jsonEncode(ManualPreviewTaskStore.encodeTasksForBackup(savedTasks)) !=
              jsonEncode(ManualPreviewTaskStore.encodeTasksForBackup(tasks)) ||
          savedRevision != profile.planningRevision ||
          settingsBox.get('schemaVersion') !=
              '${BackupService.settingsVersion}' ||
          settingsBox.get('values') != jsonEncode(settings)) {
        throw StateError('已存在的迁移候选与本次数据不一致，拒绝激活');
      }
    } finally {
      for (final box in [academicBox, taskBox, settingsBox]) {
        if (box != null && box.isOpen) await box.close();
      }
    }
  }
}

/// Coordinates candidate persistence and active selection; old generations stay intact.
final class ManualMigrationRunner {
  const ManualMigrationRunner({
    required this.writer,
    required this.selector,
    this.validator = const ManualMigrationValidator(),
  });

  final MigrationGenerationWriter writer;
  final MigrationGenerationSelector selector;
  final ManualMigrationValidator validator;

  Future<MigrationRunResult> run({
    required StorageGenerationManifest fallbackActive,
    required StorageGenerationManifest candidate,
    required AcademicProfile profile,
    required List<Task> tasks,
    required Map<String, Object?> settings,
    required Map<String, MigrationCount> counts,
  }) async {
    final selected = await selector.selectActive(fallback: fallbackActive);
    final report = validator.validate(
      profile: profile,
      tasks: tasks,
      counts: counts,
    );
    if (report.blockingCount > 0) {
      throw MigrationBlockedError(report);
    }
    if (selected.active.generationId == candidate.generationId) {
      return MigrationRunResult(
        active: selected.active,
        alreadyCommitted: true,
        validation: report,
      );
    }
    if (candidate.parentGenerationId != selected.active.generationId ||
        candidate.rootDirectory != selected.active.rootDirectory ||
        candidate.role != StorageGenerationRole.candidate ||
        candidate.legacyRoot) {
      throw StateError('迁移候选与当前活动代次不匹配');
    }

    await writer.writeAndVerify(
      candidate: candidate,
      profile: profile,
      tasks: List.unmodifiable(tasks),
      settings: Map.unmodifiable(settings),
    );
    try {
      final committed = await selector.commitCandidate(
        currentActive: selected.active,
        candidate: candidate,
      );
      return MigrationRunResult(
        active: committed.active,
        alreadyCommitted: false,
        validation: report,
      );
    } on Object {
      // A caller may see an exception after the durable pointer flush. Read it
      // back before deciding whether retry should be reported as complete.
      final afterFailure =
          await selector.selectActive(fallback: fallbackActive);
      if (afterFailure.active.generationId == candidate.generationId) {
        return MigrationRunResult(
          active: afterFailure.active,
          alreadyCommitted: true,
          validation: report,
        );
      }
      rethrow;
    }
  }
}

final class MigrationBlockedError implements Exception {
  const MigrationBlockedError(this.report);

  final MigrationValidationReport report;

  @override
  String toString() => '迁移候选校验有 ${report.blockingCount} 个阻断问题';
}
