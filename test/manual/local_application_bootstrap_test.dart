import 'dart:io';

import 'package:celechron/debug/manual_preview_generation_access.dart';
import 'package:celechron/manual/bootstrap/local_application_bootstrap.dart';
import 'package:celechron/manual/data/generation_selection_store.dart';
import 'package:celechron/manual/migration/legacy_reader.dart';
import 'package:celechron/manual/migration/legacy_scholar_record.dart';
import 'package:celechron/manual/migration/migration_resolution_store.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory documents;
  late Directory support;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('local-app-bootstrap-');
    documents = Directory('${root.path}/Documents')..createSync();
    support = Directory('${root.path}/Library/Application Support')
      ..createSync(recursive: true);
  });

  tearDown(() async {
    await Hive.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> writeLegacy({required bool blocking}) async {
    Hive.init(documents.path);
    LegacyHiveSnapshotReader.registerLegacyAdapters(Hive);
    final scholarBox = await Hive.openBox('dbUser');
    await scholarBox.put(
      'user',
      LegacyScholarRecord({
        'semesters': <Object?>[
          if (blocking) {'name': '短名称'},
        ],
      }),
    );
    final taskBox = await Hive.openBox('dbDeadline');
    final date = DateTime(2026, 10, 10);
    await taskBox.put('deadlineList', [
      Task(
        uid: 'task-from-legacy',
        summary: '合成迁移任务',
        endTime: date,
        startTime: date,
        repeatEndsTime: date,
      ),
    ]);
    await Hive.close();
  }

  test('first install opens local storage without inventing legacy backup',
      () async {
    var cleanupCalls = 0;
    final result = await LocalApplicationBootstrap(
      stopLegacyTasks: () async {
        cleanupCalls++;
        return true;
      },
    ).run(
      documentsPath: documents.path,
      applicationSupportPath: support.path,
    );

    expect(cleanupCalls, 1);
    expect(result.isBlocked, isFalse);
    expect(result.migration.backup, isNull);
    expect(
      result.access.generation.rootDirectory,
      '${documents.path}/${ManualPreviewGenerationAccess.localDataDirectoryName}',
    );
    expect(
      await Directory('${support.path}/celechron-legacy-backup').exists(),
      isFalse,
    );
  });

  test('committed migration reopens the candidate as the active generation',
      () async {
    await writeLegacy(blocking: false);
    final result = await LocalApplicationBootstrap(
      stopLegacyTasks: () async => true,
    ).run(
      documentsPath: documents.path,
      applicationSupportPath: support.path,
    );
    final selected = await GenerationSelectionStore(
      rootDirectory: result.access.generation.rootDirectory,
    ).selectActive(fallback: result.access.generation);

    expect(result.migration.backup?.boxFiles, greaterThan(0));
    expect(result.migration.status.name, 'committed');
    expect(selected.active.generationId, result.access.generation.generationId);
    expect(result.access.generation.generationId, startsWith('legacy-'));
    expect(result.access.previewBox.isOpen, isTrue);
    expect(result.access.previewBox.name, result.access.generation.taskBoxName);
  });

  test('blocked migration leaves active selection unchanged', () async {
    await writeLegacy(blocking: true);
    final result = await LocalApplicationBootstrap(
      stopLegacyTasks: () async => true,
    ).run(
      documentsPath: documents.path,
      applicationSupportPath: support.path,
    );
    final selected = await GenerationSelectionStore(
      rootDirectory: result.access.generation.rootDirectory,
    ).selectActive(fallback: result.access.generation);

    expect(result.isBlocked, isTrue);
    expect(result.migration.assembly!.report.blockingCount, greaterThan(0));
    expect(selected.active.generationId, result.access.generation.generationId);
    expect(
      await Directory('${result.access.generation.rootDirectory}/generations')
          .exists(),
      isFalse,
    );
  });

  test('restores saved skip decisions and commits with ignored count',
      () async {
    await writeLegacy(blocking: true);
    await MigrationResolutionStore(
      '${support.path}/${MigrationResolutionStore.fileName}',
    ).skipIssue('legacy-unresolved:学期:0');

    final result = await LocalApplicationBootstrap(
      stopLegacyTasks: () async => true,
    ).run(
      documentsPath: documents.path,
      applicationSupportPath: support.path,
    );

    expect(result.isBlocked, isFalse);
    expect(result.migration.status.name, 'committed');
    expect(result.migration.assembly!.report.counts['学期']!.ignoredRecords, 1);
    expect(
      await Directory('${support.path}/celechron-legacy-backup').exists(),
      isTrue,
    );
  });
}
