import 'dart:convert';

import '../../debug/manual_preview_task_store.dart';
import '../data/academic_repository.dart';
import '../model/manual_user_preferences.dart';

/// Exports only the isolated manual-entry preview data sources.
final class BackupService {
  const BackupService({required this.academic, required this.tasks});

  final AcademicRepository academic;
  final ManualPreviewTaskStore tasks;

  static const formatName = 'celechron-manual-backup';
  static const backupVersion = 1;
  static const settingsVersion = 1;

  Future<String> exportJson({
    Map<String, Object?> settings = const {},
    DateTime? exportedAt,
  }) async {
    final profile = await academic.read();
    final taskRecords = await tasks.exportTasksForBackup();
    final safeSettings = validateSettings(settings);
    final backup = <String, Object?>{
      'format': formatName,
      'backupVersion': backupVersion,
      'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'revisions': {
        'academic': profile.revision,
        'taskPlanning': tasks.taskPlanningRevision,
      },
      'academic': profile.toJson(),
      'tasks': taskRecords,
      'settings': {
        'schemaVersion': settingsVersion,
        'values': safeSettings,
      },
    };
    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  static Map<String, Object?> validateSettings(
    Map<String, Object?> settings,
  ) {
    const preferenceKeys = {
      'theme',
      'workMinutes',
      'restMinutes',
      'availableWindows',
    };
    final preferenceKeyCount =
        settings.keys.where(preferenceKeys.contains).length;
    if (settings.containsKey('availableWindows') || preferenceKeyCount >= 2) {
      ManualUserPreferences.fromJson(settings);
    }
    final result = <String, Object?>{};
    for (final entry in settings.entries) {
      if (_containsSensitiveField(entry.key, entry.value)) {
        throw const FormatException('设置包含不可导出的敏感字段');
      }
      result[entry.key] = entry.value;
    }
    return result;
  }

  static bool _containsSensitiveField(String key, Object? value) {
    final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    const blockedFragments = [
      'password',
      'passwd',
      'secret',
      'auth',
      'credential',
      'apikey',
      'token',
      'cookie',
      'username',
      'account',
      'studentid',
      'studentnumber',
      'studentno',
      'log',
      'response',
      'cache',
    ];
    if (blockedFragments.any(normalized.contains)) return true;
    if (value is Map) {
      return value.entries.any((entry) =>
          entry.key is String &&
          _containsSensitiveField(entry.key as String, entry.value));
    }
    if (value is Iterable) {
      return value.any((item) => _containsSensitiveField('', item));
    }
    return false;
  }
}
