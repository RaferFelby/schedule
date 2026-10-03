import 'dart:convert';

import 'package:hive/hive.dart';

import 'storage_generation.dart';
import '../model/manual_user_preferences.dart';

/// Reads and writes settings inside the selected isolated data generation.
final class ManualUserPreferencesStore {
  const ManualUserPreferencesStore(this.generation, {this.hive});

  final StorageGenerationManifest generation;
  final HiveInterface? hive;

  Future<ManualUserPreferences> read() async {
    final box = await _open();
    try {
      final raw = box.get('values');
      if (raw == null) return const ManualUserPreferences();
      try {
        return ManualUserPreferences.fromJson(jsonDecode(raw));
      } on Object {
        return const ManualUserPreferences();
      }
    } finally {
      await box.close();
    }
  }

  Future<void> write(ManualUserPreferences preferences) async {
    final box = await _open();
    try {
      await box.put('schemaVersion', '1');
      await box.put('values', jsonEncode(preferences.toJson()));
      await box.flush();
    } finally {
      await box.close();
    }
  }

  Future<Box<String>> _open() async => (hive ?? Hive).openBox<String>(
        generation.settingsBoxName,
        path: generation.settingsLocation,
      );
}
