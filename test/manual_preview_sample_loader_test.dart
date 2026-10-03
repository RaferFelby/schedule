import 'dart:convert';
import 'dart:io';

import 'package:celechron/debug/manual_preview_sample_loader.dart';
import 'package:celechron/debug/manual_preview_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp(
      'celechron-preview-sample-',
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await documentsDirectory.exists()) {
      await documentsDirectory.delete(recursive: true);
    }
  });

  test('load and clear affect only preview storage', () async {
    Hive.init(documentsDirectory.path);
    final scholarBox = await Hive.openBox<String>('dbScholar');
    await scholarBox.put('existing-user-data', 'keep-this-value');
    await Hive.close();

    final previewBox = await ManualPreviewStorage.openAt(
      documentsDirectory.path,
    );
    await previewBox.put(
        ManualPreviewStorage.homeworkKey, 'stale preview tasks');
    await ManualPreviewSampleLoader.load(previewBox);
    expect(previewBox.get(ManualPreviewStorage.homeworkKey), isNull);

    final sample = jsonDecode(
      previewBox.get(ManualPreviewSampleLoader.sampleKey)!,
    ) as Map<String, dynamic>;
    expect(sample['schemaVersion'], 1);
    expect((sample['courses'] as List), hasLength(2));

    await ManualPreviewSampleLoader.clear(previewBox);
    expect(previewBox.isEmpty, isTrue);
    await Hive.close();

    Hive.init(documentsDirectory.path);
    final formalScholarBox = await Hive.openBox<String>('dbScholar');
    expect(formalScholarBox.get('existing-user-data'), 'keep-this-value');
    final formalPreviewBox = await Hive.openBox<String>(
      ManualPreviewStorage.boxName,
    );
    expect(formalPreviewBox.get(ManualPreviewSampleLoader.sampleKey), isNull);
  });
}
