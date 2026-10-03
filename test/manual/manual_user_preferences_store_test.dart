import 'dart:io';

import 'package:celechron/manual/data/manual_user_preferences_store.dart';
import 'package:celechron/manual/data/storage_generation.dart';
import 'package:celechron/manual/model/manual_user_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('manual-preferences-');
    Hive.init(root.path);
  });

  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test('persists preferences in their selected isolated generation', () async {
    final active = StorageGenerationManifest.legacyActive(
      rootDirectory: '${root.path}/active',
    );
    final other = StorageGenerationManifest.active(
      rootDirectory: '${root.path}/active',
      generationId: 'other',
    );
    await Directory(active.settingsLocation).create(recursive: true);
    await Directory(other.settingsLocation).create(recursive: true);
    const preferences = ManualUserPreferences(
      theme: 'dark',
      workMinutes: 40,
      restMinutes: 8,
      availableWindows: [
        <int>[510, 690]
      ],
    );

    await ManualUserPreferencesStore(active).write(preferences);

    expect(await ManualUserPreferencesStore(active).read(), isNotNull);
    expect((await ManualUserPreferencesStore(active).read()).toJson(),
        preferences.toJson());
    expect((await ManualUserPreferencesStore(other).read()).theme, 'system');
  });
}
