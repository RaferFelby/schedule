import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import '../../model/todo.dart';

import '../../debug/manual_preview_generation_access.dart';
import '../../debug/manual_preview_storage.dart';
import '../../debug/manual_preview_task_store.dart';
import '../data/generation_selection_store.dart';
import '../data/storage_generation.dart';
import 'legacy_migration_assembler.dart';
import 'legacy_reader.dart';
import 'migration_runner.dart';
import 'migration_validator.dart';

enum LegacyMigrationStatus { noLegacyData, blocked, committed }

final class LegacyMigrationOutcome {
  const LegacyMigrationOutcome({
    required this.status,
    this.backup,
    this.assembly,
    this.runResult,
  });

  final LegacyMigrationStatus status;
  final LegacyHiveBackupResult? backup;
  final LegacyMigrationAssembly? assembly;
  final MigrationRunResult? runResult;
}

/// Backs up, converts, validates, and conditionally activates legacy data.
/// It never deletes legacy files, credentials, or an existing manual profile.
final class LegacyMigrationCoordinator {
  const LegacyMigrationCoordinator({
    this.reader = const LegacyHiveSnapshotReader(),
    this.assembler = const LegacyMigrationAssembler(),
    this.hive,
  });

  final LegacyHiveSnapshotReader reader;
  final LegacyMigrationAssembler assembler;
  final HiveInterface? hive;

  Future<LegacyMigrationOutcome> run({
    required String sourceDirectory,
    required String backupDirectory,
    required ManualPreviewGenerationAccess activeAccess,
    Set<String> skippedIssueCodes = const {},
    Map<String, Object?> correctedRecords = const {},
  }) async {
    final source = Directory(sourceDirectory);
    if (!await _hasLegacyFiles(source)) {
      return const LegacyMigrationOutcome(
        status: LegacyMigrationStatus.noLegacyData,
      );
    }

    final backupPath = Directory(backupDirectory);
    final LegacyHiveBackupResult backup;
    if (await backupPath.exists()) {
      await reader.readBackup(
        backupDirectory: backupDirectory,
        hive: hive,
      );
      final manifest = jsonDecode(
        await File('${backupPath.path}${Platform.pathSeparator}'
                '${LegacyHiveSnapshotReader.manifestFileName}')
            .readAsString(),
      ) as Map;
      backup = LegacyHiveBackupResult(
        directory: backupPath.path,
        boxFiles: (manifest['boxes'] as List).length,
        scholarProjectionWritten: manifest['scholarProjection'] is String,
      );
    } else {
      backup = await reader.createBackup(
        sourceDirectory: sourceDirectory,
        destinationDirectory: backupDirectory,
        hive: hive,
      );
    }
    final input = await reader.readBackup(
      backupDirectory: backup.directory,
      hive: hive,
    );
    final uncorrected = assembler.assemble(
      scholar: input.scholar,
      legacyTasks: input.tasks,
      todos: input.todos,
      legacyOptions: input.options,
      legacyCustomGpa: input.customGpa,
    );
    final skipPaths = uncorrected.report.issues
        .where((issue) => skippedIssueCodes.contains(issue.code))
        .map((issue) => _pathKey(issue.sourcePath))
        .whereType<String>()
        .toSet();
    final correctedInput = _applyCorrections(
      input,
      uncorrected,
      correctedRecords,
    );
    final converted = assembler.assemble(
      scholar: correctedInput.scholar,
      legacyTasks: correctedInput.tasks,
      todos: correctedInput.todos,
      legacyOptions: correctedInput.options,
      legacyCustomGpa: correctedInput.customGpa,
    );
    final assembly = _applySkippedIssues(
      converted,
      skippedIssueCodes,
      skipPaths,
    );
    final issues = [...assembly.report.issues];

    final selectionStore = GenerationSelectionStore(
      rootDirectory: activeAccess.generation.rootDirectory,
      hive: hive,
    );
    final selected = await selectionStore.selectActive(
      fallback: activeAccess.generation,
    );
    final candidateId = _candidateId(assembly);
    if (selected.active.generationId == candidateId) {
      return LegacyMigrationOutcome(
        status: LegacyMigrationStatus.committed,
        backup: backup,
        assembly: assembly,
        runResult: MigrationRunResult(
          active: selected.active,
          alreadyCommitted: true,
          validation: assembly.report,
        ),
      );
    }

    final currentGeneration = await ManualPreviewGenerationAccess.openAtRoot(
      activeAccess.generation.rootDirectory,
      hive: hive,
    );
    final currentProfile = await currentGeneration.academicRepository.read();
    final currentTasks =
        await ManualPreviewTaskStore(currentGeneration.previewBox).readTasks();
    final hasManualProfile = currentProfile.semesters.isNotEmpty ||
        currentProfile.revision > 0 ||
        currentProfile.planningRevision > 0 ||
        currentProfile.timeSlots.isNotEmpty ||
        currentProfile.courses.isNotEmpty ||
        currentProfile.sessionRules.isNotEmpty ||
        currentProfile.exams.isNotEmpty ||
        currentProfile.grades.isNotEmpty ||
        currentProfile.practiceRecords.isNotEmpty;
    final hasManualTaskData = currentTasks.isNotEmpty ||
        currentGeneration.previewBox
            .containsKey(ManualPreviewStorage.sampleKey) ||
        currentGeneration.previewBox
            .containsKey(ManualPreviewStorage.homeworkKey) ||
        currentGeneration.previewBox
            .containsKey(ManualPreviewStorage.taskPlanningRevisionKey) ||
        currentGeneration.previewBox
            .containsKey(ManualPreviewStorage.courseDeletionJournalKey);
    if (hasManualProfile || hasManualTaskData) {
      issues.add(const MigrationValidationIssue(
        code: 'existing-manual-data',
        message: '当前本地代次已有手动数据；为避免覆盖或合并错误，旧数据已备份但未导入',
        blocking: true,
      ));
    }

    final report = MigrationValidationReport(
      counts: assembly.report.counts,
      issues: List.unmodifiable(issues),
    );
    final reviewedAssembly = LegacyMigrationAssembly(
      profile: assembly.profile,
      tasks: assembly.tasks,
      settings: assembly.settings,
      report: report,
      reviewItems: assembly.reviewItems,
    );
    if (report.blockingCount > 0) {
      return LegacyMigrationOutcome(
        status: LegacyMigrationStatus.blocked,
        backup: backup,
        assembly: reviewedAssembly,
      );
    }

    final candidate = StorageGenerationManifest.candidateFor(
      active: selected.active,
      generationId: candidateId,
    );
    final runResult = await ManualMigrationRunner(
      writer: CandidateRestoreMigrationWriter(hive: hive),
      selector: _GenerationSelectorAdapter(selectionStore),
    ).run(
      fallbackActive: currentGeneration.generation,
      candidate: candidate,
      profile: assembly.profile,
      tasks: assembly.tasks,
      settings: assembly.settings,
      counts: report.counts,
    );
    return LegacyMigrationOutcome(
      status: LegacyMigrationStatus.committed,
      backup: backup,
      assembly: reviewedAssembly,
      runResult: runResult,
    );
  }

  static LegacyHiveMigrationInput _applyCorrections(
    LegacyHiveMigrationInput input,
    LegacyMigrationAssembly rawAssembly,
    Map<String, Object?> corrections,
  ) {
    if (corrections.isEmpty) return input;
    final source = <String, Object?>{
      'scholar': _deepCopy(input.scholar),
      'todos': input.todos.map((todo) => todo.toJson()).toList(),
      'legacyOptions': _deepCopy(input.options),
      'legacyCustomGpa': _deepCopy(input.customGpa),
    };
    for (final entry in corrections.entries) {
      final matching = rawAssembly.report.issues.where(
        (issue) => issue.code == entry.key,
      );
      if (matching.isEmpty) {
        throw StateError('迁移修正引用了不存在的问题：${entry.key}');
      }
      final path = matching.first.sourcePath;
      if (path == null) {
        throw StateError('该迁移问题没有可编辑的来源字段：${entry.key}');
      }
      _setAtPath(source, path, _deepCopy(entry.value));
    }
    final todos = (source['todos'] as List)
        .map((item) => Todo.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
    return LegacyHiveMigrationInput(
      scholar: Map<String, Object?>.from(source['scholar'] as Map),
      tasks: input.tasks,
      todos: todos,
      options: Map<String, Object?>.from(source['legacyOptions'] as Map),
      customGpa: Map<String, Object?>.from(source['legacyCustomGpa'] as Map),
    );
  }

  static Object? _deepCopy(Object? value) {
    if (value is Map) {
      return value.map<Object?, Object?>(
        (key, entry) => MapEntry(key, _deepCopy(entry)),
      );
    }
    if (value is List) return value.map(_deepCopy).toList();
    return value;
  }

  static void _setAtPath(
    Object? root,
    List<Object?> path,
    Object? value,
  ) {
    if (path.isEmpty) throw const FormatException('迁移修正路径为空');
    Object? current = root;
    for (final segment in path.take(path.length - 1)) {
      if (segment is String && current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else if (segment is int &&
          current is List &&
          segment >= 0 &&
          segment < current.length) {
        current = current[segment];
      } else {
        throw FormatException('迁移修正路径不存在：$path');
      }
    }
    final last = path.last;
    if (last is String && current is Map && current.containsKey(last)) {
      current[last] = value;
    } else if (last is int &&
        current is List &&
        last >= 0 &&
        last < current.length) {
      current[last] = value;
    } else {
      throw FormatException('迁移修正目标不存在：$path');
    }
  }

  static String? _pathKey(List<Object?>? path) =>
      path == null ? null : jsonEncode(path);

  static LegacyMigrationAssembly _applySkippedIssues(
    LegacyMigrationAssembly assembly,
    Set<String> requested,
    Set<String> sourcePaths,
  ) {
    final skippableCodes = assembly.report.issues
        .where((issue) =>
            issue.code.startsWith('legacy-unresolved:') &&
            (requested.contains(issue.code) ||
                sourcePaths.contains(_pathKey(issue.sourcePath))))
        .map((issue) => issue.code)
        .toSet();
    if (skippableCodes.isEmpty) return assembly;

    final counts = Map<String, MigrationCount>.from(assembly.report.counts);
    for (final code in skippableCodes) {
      final parts = code.split(':');
      if (parts.length < 3) continue;
      final category = parts[1];
      final current = counts[category];
      if (current == null || current.unresolvedRecords == 0) continue;
      counts[category] = MigrationCount(
        sourceRecords: current.sourceRecords,
        convertedRecords: current.convertedRecords,
        unresolvedRecords: current.unresolvedRecords - 1,
        ignoredRecords: current.ignoredRecords + 1,
      );
    }
    return LegacyMigrationAssembly(
      profile: assembly.profile,
      tasks: assembly.tasks,
      settings: assembly.settings,
      report: MigrationValidationReport(
        counts: counts,
        issues: assembly.report.issues
            .where((issue) => !skippableCodes.contains(issue.code))
            .toList(growable: false),
      ),
      reviewItems: assembly.reviewItems,
    );
  }

  static Future<bool> _hasLegacyFiles(Directory source) async {
    if (!await source.exists()) return false;
    for (final boxName in LegacyHiveSnapshotReader.legacyBoxNames) {
      for (final extension in const ['hive', 'hivec']) {
        if (await File(
          '${source.path}${Platform.pathSeparator}$boxName.$extension',
        ).exists()) {
          return true;
        }
      }
    }
    return false;
  }

  static String _candidateId(LegacyMigrationAssembly assembly) {
    final payload = jsonEncode({
      'academic': assembly.profile.toJson(),
      'tasks': ManualPreviewTaskStore.encodeTasksForBackup(assembly.tasks),
      'settings': assembly.settings,
    });
    return 'legacy-${sha256.convert(utf8.encode(payload)).toString().substring(0, 32)}';
  }
}

final class _GenerationSelectorAdapter implements MigrationGenerationSelector {
  const _GenerationSelectorAdapter(this.store);

  final GenerationSelectionStore store;

  @override
  Future<GenerationSelectionResult> selectActive({
    required StorageGenerationManifest fallback,
  }) =>
      store.selectActive(fallback: fallback);

  @override
  Future<GenerationSelectionResult> commitCandidate({
    required StorageGenerationManifest currentActive,
    required StorageGenerationManifest candidate,
  }) =>
      store.commitCandidate(
        currentActive: currentActive,
        candidate: candidate,
      );
}
