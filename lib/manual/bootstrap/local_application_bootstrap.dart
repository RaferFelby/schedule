import 'dart:io';

import 'package:hive/hive.dart';

import '../../debug/manual_preview_generation_access.dart';
import '../../manual/migration/legacy_migration_coordinator.dart';
import '../../manual/migration/migration_resolution_store.dart';
import '../../manual/service/course_deletion_coordinator.dart';
import '../../services/legacy_background_task_cleanup.dart';

final class LocalApplicationBootstrapResult {
  const LocalApplicationBootstrapResult({
    required this.access,
    required this.migration,
  });

  final ManualPreviewGenerationAccess access;
  final LegacyMigrationOutcome migration;

  bool get isBlocked => migration.status == LegacyMigrationStatus.blocked;
}

/// Stops the old background fetch before selecting or migrating local data.
final class LocalApplicationBootstrap {
  const LocalApplicationBootstrap({
    Future<bool> Function()? stopLegacyTasks,
    this.migrationCoordinator = const LegacyMigrationCoordinator(),
    this.hive,
  }) : _stopLegacyTasks = stopLegacyTasks;

  final Future<bool> Function()? _stopLegacyTasks;
  final LegacyMigrationCoordinator migrationCoordinator;
  final HiveInterface? hive;

  Future<LocalApplicationBootstrapResult> run({
    required String documentsPath,
    required String applicationSupportPath,
  }) async {
    await (_stopLegacyTasks ?? const LegacyBackgroundTaskCleanup().run)();

    var access = await ManualPreviewGenerationAccess.openLocalAt(
      documentsPath,
      hive: hive,
    );
    final backupRoot = Directory(
      '$applicationSupportPath${Platform.pathSeparator}celechron-legacy-backup',
    );
    final resolutionStore = MigrationResolutionStore(
      '$applicationSupportPath${Platform.pathSeparator}'
      '${MigrationResolutionStore.fileName}',
    );
    final migration = await migrationCoordinator.run(
      sourceDirectory: documentsPath,
      backupDirectory: backupRoot.path,
      activeAccess: access,
      skippedIssueCodes: await resolutionStore.readSkippedIssueCodes(),
      correctedRecords: await resolutionStore.readCorrections(),
    );

    if (migration.status == LegacyMigrationStatus.blocked) {
      return LocalApplicationBootstrapResult(
        access: access,
        migration: migration,
      );
    }

    final committedGeneration = migration.runResult?.active.generationId;
    if (committedGeneration != null &&
        committedGeneration != access.generation.generationId) {
      await (hive ?? Hive).close();
      access = await ManualPreviewGenerationAccess.openLocalAt(
        documentsPath,
        hive: hive,
      );
    }

    await CourseDeletionCoordinator(
      repository: access.academicRepository,
      previewBox: access.previewBox,
    ).recoverPending();

    return LocalApplicationBootstrapResult(
      access: access,
      migration: migration,
    );
  }
}
