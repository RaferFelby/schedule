import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../manual/data/local_data_error.dart';
import '../manual/data/storage_generation.dart';

/// Hive task-box format shared by preview and production local generations.
/// Preview samples stay isolated because each mode opens a different root.
class ManualPreviewStorage {
  ManualPreviewStorage._();

  static const directoryName = 'celechron_manual_preview';
  static const boxName = 'manual-preview-v1';
  static const markerKey = 'preview-marker';
  static const markerValue = 'manual-preview-storage-ready';
  static const sampleKey = 'manual-sample-json';
  static const homeworkKey = 'manual-preview-homework-v1';
  static const taskPlanningRevisionKey = 'manual-task-planning-revision-v1';
  static const courseDeletionJournalKey = 'manual-course-deletion-operation-v1';

  static Future<Box<String>> open() async {
    final documents = await getApplicationDocumentsDirectory();
    return openAt(documents.path);
  }

  /// Opens only the preview box beneath [documentsPath].
  ///
  /// [hive] is injectable so tests can verify storage isolation without using
  /// the application's Hive singleton or its real user data.
  static Future<Box<String>> openAt(
    String documentsPath, {
    HiveInterface? hive,
  }) =>
      openForGeneration(
        StorageGenerationManifest.legacyActive(
          rootDirectory: Directory('$documentsPath/$directoryName').path,
        ),
        hive: hive,
      );

  /// Opens only an active generation. Candidate generations are never read by
  /// the running preview app.
  static Future<Box<String>> openForGeneration(
    StorageGenerationManifest generation, {
    HiveInterface? hive,
  }) async {
    if (generation.role != StorageGenerationRole.active) {
      throw const LocalDataValidationError('当前预览只能打开活动数据代次');
    }
    final directory = Directory(generation.generationDirectory);
    await directory.create(recursive: true);

    final previewHive = hive ?? Hive;
    previewHive.init(directory.path);
    final box = await previewHive.openBox<String>(
      generation.taskBoxName,
      path: generation.taskLocation,
    );
    await box.put(markerKey, markerValue);
    return box;
  }
}
