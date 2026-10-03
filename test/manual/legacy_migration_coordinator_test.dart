import 'dart:io';

import 'package:celechron/debug/manual_preview_generation_access.dart';
import 'package:celechron/manual/data/generation_selection_store.dart';
import 'package:celechron/manual/migration/legacy_migration_coordinator.dart';
import 'package:celechron/manual/migration/legacy_reader.dart';
import 'package:celechron/manual/migration/legacy_scholar_record.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory source;
  late Directory documents;
  late Directory backup;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('legacy-migration-run-');
    source = Directory('${root.path}/legacy');
    documents = Directory('${root.path}/documents');
    backup = Directory('${root.path}/support/legacy-backup');
    await source.create(recursive: true);
    await documents.create(recursive: true);
  });

  tearDown(() async {
    await Hive.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> writeLegacy(Map<String, Object?> scholar,
      {bool includeTask = false}) async {
    Hive.init(source.path);
    LegacyHiveSnapshotReader.registerLegacyAdapters(Hive);
    final scholarBox = await Hive.openBox('dbUser');
    await scholarBox.put(
      'user',
      LegacyScholarRecord(Map<String, Object?>.from(scholar)),
    );
    if (includeTask) {
      final date = DateTime(2026, 10, 10);
      final taskBox = await Hive.openBox('dbDeadline');
      await taskBox.put('deadlineList', [
        Task(
          uid: 'legacy-task',
          endTime: date,
          startTime: date,
          repeatEndsTime: date,
        ),
      ]);
    }
    await Hive.close();
  }

  test('backs up, activates a valid candidate and retries idempotently',
      () async {
    await writeLegacy({'semesters': <Object?>[]}, includeTask: true);
    final originalScholar =
        await File('${source.path}/dbUser.hive').readAsBytes();
    final access = await ManualPreviewGenerationAccess.openAt(documents.path);
    const coordinator = LegacyMigrationCoordinator();

    final first = await coordinator.run(
      sourceDirectory: source.path,
      backupDirectory: backup.path,
      activeAccess: access,
    );
    final selected = await GenerationSelectionStore(
      rootDirectory: access.generation.rootDirectory,
    ).selectActive(fallback: access.generation);
    final retry = await coordinator.run(
      sourceDirectory: source.path,
      backupDirectory: backup.path,
      activeAccess: access,
    );

    expect(first.status, LegacyMigrationStatus.committed);
    expect(first.assembly?.tasks.single.uid, 'legacy-task');
    expect(selected.active.generationId, startsWith('legacy-'));
    expect(retry.runResult?.alreadyCommitted, isTrue);
    expect(await File('${source.path}/dbUser.hive').readAsBytes(),
        originalScholar);
  });

  test('leaves active pointer and candidate files untouched on blockers',
      () async {
    await writeLegacy({
      'semesters': <Object?>[
        {'name': '旧学期'},
      ],
    });
    final access = await ManualPreviewGenerationAccess.openAt(documents.path);
    final before = await GenerationSelectionStore(
      rootDirectory: access.generation.rootDirectory,
    ).selectActive(fallback: access.generation);

    final result = await const LegacyMigrationCoordinator().run(
      sourceDirectory: source.path,
      backupDirectory: backup.path,
      activeAccess: access,
    );
    final after = await GenerationSelectionStore(
      rootDirectory: access.generation.rootDirectory,
    ).selectActive(fallback: access.generation);

    expect(result.status, LegacyMigrationStatus.blocked);
    expect(result.backup, isNotNull);
    expect(after.active.generationId, before.active.generationId);
    expect(
      await Directory('${access.generation.rootDirectory}/generations')
          .exists(),
      isFalse,
    );
  });

  test('skipping one unresolved record reports it ignored and keeps backup',
      () async {
    await writeLegacy({
      'semesters': <Object?>[
        {'name': '旧学期'},
      ],
    });
    final originalScholar =
        await File('${source.path}/dbUser.hive').readAsBytes();
    final access = await ManualPreviewGenerationAccess.openAt(documents.path);
    const coordinator = LegacyMigrationCoordinator();
    final blocked = await coordinator.run(
      sourceDirectory: source.path,
      backupDirectory: backup.path,
      activeAccess: access,
    );
    final issue = blocked.assembly!.report.issues.singleWhere(
      (issue) => issue.code.startsWith('legacy-unresolved:'),
    );

    final skipped = await coordinator.run(
      sourceDirectory: source.path,
      backupDirectory: backup.path,
      activeAccess: access,
      skippedIssueCodes: {issue.code},
    );

    expect(skipped.status, LegacyMigrationStatus.committed);
    expect(skipped.assembly!.report.blockingCount, 0);
    expect(skipped.assembly!.report.counts['学期']!.unresolvedRecords, 0);
    expect(skipped.assembly!.report.counts['学期']!.ignoredRecords, 1);
    expect(await backup.exists(), isTrue);
    expect(await File('${source.path}/dbUser.hive').readAsBytes(),
        originalScholar);
  });

  test('corrects an unresolved semester from backup without changing source',
      () async {
    await writeLegacy({
      'semesters': <Object?>[
        {'name': '旧学期'},
      ],
    });
    final originalScholar =
        await File('${source.path}/dbUser.hive').readAsBytes();
    final access = await ManualPreviewGenerationAccess.openAt(documents.path);
    const coordinator = LegacyMigrationCoordinator();
    final blocked = await coordinator.run(
      sourceDirectory: source.path,
      backupDirectory: backup.path,
      activeAccess: access,
    );
    final issue = blocked.assembly!.report.issues.singleWhere(
      (issue) => issue.code.startsWith('legacy-unresolved:学期:'),
    );
    final correctedRecord = Map<String, Object?>.from(
      issue.sourceRecord! as Map,
    )..addAll({
        'startDate': '2026-09-01',
        'endDate': '2027-01-15',
        'weekOneStart': '2026-08-31',
      });

    final corrected = await coordinator.run(
      sourceDirectory: source.path,
      backupDirectory: backup.path,
      activeAccess: access,
      correctedRecords: {issue.code: correctedRecord},
    );

    expect(corrected.status, LegacyMigrationStatus.committed);
    expect(corrected.assembly!.profile.semesters.single.name, '旧学期');
    expect(corrected.assembly!.report.counts['学期']!.convertedRecords, 1);
    expect(corrected.assembly!.report.counts['学期']!.unresolvedRecords, 0);
    expect(await File('${source.path}/dbUser.hive').readAsBytes(),
        originalScholar);
    expect(await backup.exists(), isTrue);
  });

  test('returns without creating backup when no legacy Hive files exist',
      () async {
    final access = await ManualPreviewGenerationAccess.openAt(documents.path);

    final result = await const LegacyMigrationCoordinator().run(
      sourceDirectory: source.path,
      backupDirectory: backup.path,
      activeAccess: access,
    );

    expect(result.status, LegacyMigrationStatus.noLegacyData);
    expect(await backup.exists(), isFalse);
  });
}
