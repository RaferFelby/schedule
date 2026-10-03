import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import 'manual_preview_storage.dart';

/// Loads and clears development sample data in the preview-only box.
class ManualPreviewSampleLoader {
  ManualPreviewSampleLoader._();

  static const assetPath = 'test/fixtures/manual_sample.json';
  static const sampleKey = ManualPreviewStorage.sampleKey;

  static Future<void> load(
    Box<String> previewBox, {
    AssetBundle? assetBundle,
  }) async {
    final sample = await (assetBundle ?? rootBundle).loadString(assetPath);
    final taskSnapshotExists =
        previewBox.containsKey(ManualPreviewStorage.homeworkKey);
    final sampleChanged =
        previewBox.get(ManualPreviewStorage.sampleKey) != sample;
    await previewBox.delete(ManualPreviewStorage.homeworkKey);
    await previewBox.put(sampleKey, sample);
    if (taskSnapshotExists || sampleChanged) {
      final revision = int.tryParse(
            previewBox.get(ManualPreviewStorage.taskPlanningRevisionKey) ?? '',
          ) ??
          0;
      await previewBox.put(
        ManualPreviewStorage.taskPlanningRevisionKey,
        '${revision + 1}',
      );
    }
  }

  static Future<void> clear(Box<String> previewBox) async {
    await previewBox.clear();
  }
}
