import 'dart:io';

import 'package:celechron/debug/manual_preview_generation_access.dart';
import 'package:celechron/debug/manual_preview_storage.dart';
import 'package:celechron/debug/manual_preview_task_store.dart';
import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/data/storage_generation.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory documents;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('manual-generation-');
  });

  tearDown(() async {
    await Hive.close();
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  test('academic and task access open under the same legacy active generation',
      () async {
    final access = await ManualPreviewGenerationAccess.openAt(documents.path);
    final profile = await access.academicRepository.save(
      AcademicProfile(schemaVersion: 1, revision: 0),
    );
    final taskStore = ManualPreviewTaskStore(access.previewBox);

    expect(access.generation.role, StorageGenerationRole.active);
    expect(
      access.generation.generationDirectory,
      '${documents.path}/${ManualPreviewStorage.directoryName}',
    );
    expect(access.previewBox.path,
        startsWith(access.generation.generationDirectory));
    expect(
      Hive.box<String>(AcademicRepository.boxName).path,
      startsWith(access.generation.generationDirectory),
    );
    expect((await access.academicRepository.read()).revision, profile.revision);
    expect(await taskStore.readTasks(), isEmpty);
    expect(access.generation.academicLocation, access.generation.taskLocation);
    expect(access.generation.settingsLocation, access.generation.taskLocation);
    expect(access.generation.academicBoxName, AcademicRepository.boxName);
    expect(access.generation.taskBoxName, access.previewBox.name);
    expect(access.generation.settingsBoxName, 'manual-settings-v1');
    expect(Hive.isBoxOpen(access.generation.settingsBoxName), isFalse);
  });

  test('candidate generation is not opened or created by active initialization',
      () async {
    final access = await ManualPreviewGenerationAccess.openAt(documents.path);
    final candidate = StorageGenerationManifest.candidateFor(
      active: access.generation,
      generationId: 'restore-candidate-1',
    );

    expect(candidate.generationDirectory,
        isNot(access.generation.generationDirectory));
    expect(await Directory(candidate.generationDirectory).exists(), isFalse);
  });

  test('production local data opens separately from preview sample storage',
      () async {
    final preview = await ManualPreviewGenerationAccess.openAt(documents.path);
    await preview.previewBox
        .put(ManualPreviewStorage.sampleKey, '{"demo":true}');
    final previewRoot = preview.generation.rootDirectory;
    await Hive.close();

    final local =
        await ManualPreviewGenerationAccess.openLocalAt(documents.path);

    expect(local.generation.rootDirectory, isNot(previewRoot));
    expect(local.generation.rootDirectory,
        '${documents.path}/${ManualPreviewGenerationAccess.localDataDirectoryName}');
    expect(local.previewBox.get(ManualPreviewStorage.sampleKey), isNull);
    expect(local.previewBox.path, startsWith(local.generation.rootDirectory));
  });
}
