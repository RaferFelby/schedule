import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';

import '../../debug/manual_preview_storage.dart';
import '../../debug/manual_preview_task_store.dart';
import '../data/academic_repository.dart';
import '../data/local_data_error.dart';
import '../data/storage_generation.dart';
import '../model/academic_profile.dart';
import 'backup_preview_service.dart';

final class CandidateRestoreResult {
  const CandidateRestoreResult({
    required this.generation,
    required this.academicRevision,
    required this.taskPlanningRevision,
    required this.academicRecordCount,
    required this.taskCount,
    required this.settingCount,
  });

  final StorageGenerationManifest generation;
  final int academicRevision;
  final int taskPlanningRevision;
  final int academicRecordCount;
  final int taskCount;
  final int settingCount;
}

/// Writes a validated backup into an isolated generation without activating it.
final class CandidateBackupRestoreService {
  const CandidateBackupRestoreService({
    this.preview = const BackupPreviewService(),
    this.afterCandidateWrite,
  });

  final BackupPreviewService preview;

  /// Allows tests to simulate interruption after durable writes and before
  /// readback validation. Production callers should leave this unset.
  final Future<void> Function()? afterCandidateWrite;

  Future<CandidateRestoreResult> restoreCandidate({
    required String backupJson,
    required StorageGenerationManifest active,
    required StorageGenerationManifest candidate,
    HiveInterface? hive,
  }) async {
    _validateRelationship(active, candidate);
    final previewResult = preview.previewJson(backupJson);
    if (!previewResult.isValid) {
      throw LocalDataValidationError(
        '备份校验未通过：${previewResult.errors.join('；')}',
      );
    }

    final decoded = jsonDecode(backupJson) as Map;
    final academic = AcademicProfile.fromJson(
      Map<String, dynamic>.from(decoded['academic'] as Map),
    );
    final tasks = ManualPreviewTaskStore.decodeTasksForBackup(decoded['tasks']);
    final taskRevision = (decoded['revisions'] as Map)['taskPlanning'] as int;
    final settings = Map<String, dynamic>.from(decoded['settings'] as Map);
    final values = Map<String, Object?>.from(settings['values'] as Map);
    final candidateDirectory = Directory(candidate.generationDirectory);
    if (await candidateDirectory.exists()) {
      throw const LocalDataValidationError('恢复候选目录已存在，拒绝覆盖');
    }

    final candidateHive = hive ?? Hive;
    Box<String>? academicBox;
    Box<String>? taskBox;
    Box<String>? settingsBox;
    try {
      await candidateDirectory.create(recursive: true);
      academicBox = await candidateHive.openBox<String>(
        candidate.academicBoxName,
        path: candidate.academicLocation,
      );
      taskBox = await candidateHive.openBox<String>(
        candidate.taskBoxName,
        path: candidate.taskLocation,
      );
      settingsBox = await candidateHive.openBox<String>(
        candidate.settingsBoxName,
        path: candidate.settingsLocation,
      );

      await academicBox.put(
        AcademicRepository.snapshotKey,
        jsonEncode(academic.toJson()),
      );
      await taskBox.put(
        ManualPreviewStorage.homeworkKey,
        jsonEncode(ManualPreviewTaskStore.encodeTasksForBackup(tasks)),
      );
      await taskBox.put(
        ManualPreviewStorage.taskPlanningRevisionKey,
        '$taskRevision',
      );
      await settingsBox.put('schemaVersion', '${settings['schemaVersion']}');
      await settingsBox.put('values', jsonEncode(values));
      await academicBox.flush();
      await taskBox.flush();
      await settingsBox.flush();
      await _closeBoxes(academicBox, taskBox, settingsBox);
      academicBox = taskBox = settingsBox = null;

      await afterCandidateWrite?.call();

      // Reopen from disk so validation does not rely on in-memory box state.
      academicBox = await candidateHive.openBox<String>(
        candidate.academicBoxName,
        path: candidate.academicLocation,
      );
      taskBox = await candidateHive.openBox<String>(
        candidate.taskBoxName,
        path: candidate.taskLocation,
      );
      settingsBox = await candidateHive.openBox<String>(
        candidate.settingsBoxName,
        path: candidate.settingsLocation,
      );
      final savedAcademic = AcademicProfile.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(
            academicBox.get(AcademicRepository.snapshotKey) ??
                (throw const FormatException('候选学业快照丢失')),
          ) as Map,
        ),
      );
      final savedTasks = ManualPreviewTaskStore.decodeTasksForBackup(
        jsonDecode(
          taskBox.get(ManualPreviewStorage.homeworkKey) ??
              (throw const FormatException('候选任务数据丢失')),
        ),
      );
      final savedTaskRevision = int.tryParse(
        taskBox.get(ManualPreviewStorage.taskPlanningRevisionKey) ?? '',
      );
      final savedSettings = jsonDecode(settingsBox.get('values') ?? '{}');
      if (jsonEncode(savedAcademic.toJson()) != jsonEncode(academic.toJson()) ||
          jsonEncode(ManualPreviewTaskStore.encodeTasksForBackup(savedTasks)) !=
              jsonEncode(ManualPreviewTaskStore.encodeTasksForBackup(tasks)) ||
          savedTaskRevision != taskRevision ||
          settingsBox.get('schemaVersion') != '${settings['schemaVersion']}' ||
          jsonEncode(savedSettings) != jsonEncode(values)) {
        throw const FormatException('候选数据回读结果与备份不一致');
      }
      return CandidateRestoreResult(
        generation: candidate,
        academicRevision: savedAcademic.revision,
        taskPlanningRevision: savedTaskRevision!,
        academicRecordCount: savedAcademic.semesters.length +
            savedAcademic.timeSlots.length +
            savedAcademic.courses.length +
            savedAcademic.sessionRules.length +
            savedAcademic.exams.length +
            savedAcademic.grades.length +
            savedAcademic.practiceRecords.length,
        taskCount: savedTasks.length,
        settingCount: values.length,
      );
    } on LocalDataError {
      rethrow;
    } on Object catch (error) {
      throw LocalDataStorageError('恢复候选写入或回读校验失败', cause: error);
    } finally {
      await _closeBoxes(academicBox, taskBox, settingsBox);
    }
  }

  static void _validateRelationship(
    StorageGenerationManifest active,
    StorageGenerationManifest candidate,
  ) {
    if (active.role != StorageGenerationRole.active ||
        candidate.role != StorageGenerationRole.candidate ||
        candidate.parentGenerationId != active.generationId ||
        candidate.rootDirectory != active.rootDirectory ||
        candidate.legacyRoot) {
      throw const LocalDataValidationError('恢复候选与当前活动代次不匹配');
    }
  }

  static Future<void> _closeBoxes(
    Box<String>? academic,
    Box<String>? tasks,
    Box<String>? settings,
  ) async {
    for (final box in [academic, tasks, settings]) {
      if (box != null && box.isOpen) await box.close();
    }
  }
}
