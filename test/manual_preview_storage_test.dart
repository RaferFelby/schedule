import 'dart:io';

import 'package:celechron/debug/manual_preview_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp(
      'celechron-preview-storage-',
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await documentsDirectory.exists()) {
      await documentsDirectory.delete(recursive: true);
    }
  });

  test(
    "preview marker is isolated from the formal application's Hive path",
    () async {
      Hive.init(documentsDirectory.path);
      final scholarBox = await Hive.openBox<String>('dbScholar');
      await scholarBox.put('existing-user-data', 'keep-this-value');
      await Hive.close();

      final previewBox = await ManualPreviewStorage.openAt(
        documentsDirectory.path,
      );
      expect(
        previewBox.get(ManualPreviewStorage.markerKey),
        ManualPreviewStorage.markerValue,
      );
      expect(
        previewBox.path,
        contains('/${ManualPreviewStorage.directoryName}/'),
      );
      await Hive.close();

      Hive.init(documentsDirectory.path);
      final reopenedScholarBox = await Hive.openBox<String>('dbScholar');
      expect(reopenedScholarBox.get('existing-user-data'), 'keep-this-value');

      final formalAppView = await Hive.openBox<String>(
        ManualPreviewStorage.boxName,
      );
      expect(formalAppView.get(ManualPreviewStorage.markerKey), isNull);
    },
  );
}
