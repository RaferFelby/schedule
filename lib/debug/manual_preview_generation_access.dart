import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../manual/data/academic_repository.dart';
import '../manual/data/local_data_error.dart';
import '../manual/data/generation_selection_store.dart';
import '../manual/data/storage_generation.dart';
import 'manual_preview_storage.dart';

/// Opens academic and task stores under an explicitly selected data root.
final class ManualPreviewGenerationAccess {
  static const localDataDirectoryName = 'celechron_manual_data';

  const ManualPreviewGenerationAccess({
    required this.generation,
    required this.previewBox,
    required this.academicRepository,
  });

  final StorageGenerationManifest generation;
  final Box<String> previewBox;
  final AcademicRepository academicRepository;

  static Future<ManualPreviewGenerationAccess> open({
    HiveInterface? hive,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    return openAt(documents.path, hive: hive);
  }

  static Future<ManualPreviewGenerationAccess> openAt(
    String documentsPath, {
    HiveInterface? hive,
  }) =>
      openAtRoot(
        Directory('$documentsPath/${ManualPreviewStorage.directoryName}').path,
        hive: hive,
      );

  /// Opens the production local-data root, separate from preview samples.
  static Future<ManualPreviewGenerationAccess> openLocalAt(
    String documentsPath, {
    HiveInterface? hive,
  }) =>
      openAtRoot(
        Directory('$documentsPath/$localDataDirectoryName').path,
        hive: hive,
      );

  /// Opens an active selection under an explicit data root.
  static Future<ManualPreviewGenerationAccess> openAtRoot(
    String rootDirectory, {
    HiveInterface? hive,
  }) async {
    final legacy = StorageGenerationManifest.legacyActive(
      rootDirectory: Directory(rootDirectory).absolute.path,
    );
    await Directory(legacy.generationDirectory).create(recursive: true);
    final selection = await GenerationSelectionStore(
      rootDirectory: legacy.rootDirectory,
      hive: hive,
    ).selectActive(fallback: legacy);
    final manifest = selection.active;
    if (manifest.legacyRoot &&
        (manifest.academicBoxName != AcademicRepository.boxName ||
            manifest.taskBoxName != ManualPreviewStorage.boxName)) {
      throw const LocalDataValidationError('本地代次与 Hive box 定义不一致');
    }
    final previewBox = await ManualPreviewStorage.openForGeneration(
      manifest,
      hive: hive,
    );
    final academic = await AcademicRepository.open(
      hive: hive,
      boxName: manifest.academicBoxName,
      path: manifest.academicLocation,
    );
    return ManualPreviewGenerationAccess(
      generation: manifest,
      previewBox: previewBox,
      academicRepository: academic,
    );
  }
}
