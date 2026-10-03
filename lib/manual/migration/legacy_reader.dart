import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

import '../../database/adapters/course_id_map_adapter.dart';
import '../../database/adapters/deadline_adapter.dart';
import '../../database/adapters/duration_adapter.dart';
import '../../database/adapters/fuse_adapter.dart';
import '../../database/adapters/period_adapter.dart';
import '../../model/task.dart';
import '../../model/todo.dart';
import '../data/local_data_error.dart';
import 'legacy_scholar_record.dart';

final class LegacyHiveBackupResult {
  const LegacyHiveBackupResult({
    required this.directory,
    required this.boxFiles,
    required this.scholarProjectionWritten,
  });

  final String directory;
  final int boxFiles;
  final bool scholarProjectionWritten;
}

/// Sanitized, read-only input loaded from a completed legacy backup.
final class LegacyHiveMigrationInput {
  const LegacyHiveMigrationInput({
    required this.scholar,
    required this.tasks,
    required this.todos,
    required this.options,
    required this.customGpa,
  });

  final Map<String, Object?> scholar;
  final List<Task> tasks;
  final List<Todo> todos;
  final Map<String, Object?> options;
  final Map<String, Object?> customGpa;
}

/// Copies legacy Hive files without opening or writing the source boxes.
final class LegacyHiveSnapshotReader {
  const LegacyHiveSnapshotReader();

  static const manifestFileName = 'legacy-backup-manifest.json';
  static const projectionFileName = 'legacy-scholar-projection.json';
  static const supportedSchemaVersion = 1;
  static const legacyBoxNames = [
    'dbOptions',
    'dbUser',
    'dbDeadline',
    'dbFlow',
    'dbOriginalWebPage',
    'dbFuse',
    'dbCustomGpa',
  ];

  static var _readerBoxSequence = 0;

  Future<LegacyHiveBackupResult> createBackup({
    required String sourceDirectory,
    required String destinationDirectory,
    HiveInterface? hive,
  }) async {
    final source = Directory(sourceDirectory).absolute;
    final destination = Directory(destinationDirectory).absolute;
    if (!source.isAbsolute ||
        !destination.isAbsolute ||
        source.path == destination.path ||
        destination.path
            .startsWith('${source.path}${Platform.pathSeparator}')) {
      throw const LocalDataValidationError('旧数据备份路径无效或位于源目录内');
    }
    if (!await source.exists()) {
      throw const LocalDataStorageError('旧 Hive 数据目录不存在');
    }
    if (await destination.exists()) {
      throw const LocalDataValidationError('旧数据备份目录已存在，拒绝覆盖');
    }

    final inputs = <_LegacyBoxFile>[];
    for (final boxName in legacyBoxNames) {
      for (final extension in const ['hive', 'hivec']) {
        final file = File('${source.path}${Platform.pathSeparator}'
            '$boxName.$extension');
        if (await file.exists()) inputs.add(_LegacyBoxFile(boxName, file));
      }
    }
    if (inputs.isEmpty) {
      throw const LocalDataStorageError('旧 Hive 目录中没有可备份的数据 box');
    }

    await destination.create(recursive: true);
    final boxesDirectory = Directory(
      '${destination.path}${Platform.pathSeparator}boxes',
    );
    await boxesDirectory.create();
    final fileManifest = <Map<String, Object?>>[];
    var scholarProjectionWritten = false;
    String? scholarProjectionChecksum;

    for (final input in inputs) {
      final bytesBefore = await input.file.readAsBytes();
      final checksum = _checksum(bytesBefore);
      if (input.boxName == 'dbUser') {
        final projection = await _readSanitizedScholarProjection(
          bytesBefore,
          hive ?? Hive,
        );
        final projectionFile = File(
          '${destination.path}${Platform.pathSeparator}$projectionFileName',
        );
        if (!scholarProjectionWritten) {
          final projectionText = const JsonEncoder.withIndent('  ').convert({
            'schemaVersion': supportedSchemaVersion,
            'sourceBox': 'dbUser',
            'containsCredentials': false,
            'scholar': projection,
          });
          await projectionFile.writeAsString(projectionText, flush: true);
          scholarProjectionChecksum = _checksum(utf8.encode(projectionText));
          scholarProjectionWritten = true;
        }
      } else {
        final target = File(
          '${boxesDirectory.path}${Platform.pathSeparator}'
          '${input.boxName}.${input.file.uri.pathSegments.last.split('.').last}',
        );
        await target.writeAsBytes(bytesBefore, flush: true);
        final targetChecksum = _checksum(await target.readAsBytes());
        if (targetChecksum != checksum) {
          throw const LocalDataStorageError('旧 Hive box 备份校验失败');
        }
      }

      final bytesAfter = await input.file.readAsBytes();
      if (_checksum(bytesAfter) != checksum) {
        throw LocalDataStorageError(
          '旧 Hive box 在备份期间发生变化：${input.boxName}',
        );
      }
      fileManifest.add({
        'box': input.boxName,
        'sourceFile': input.file.uri.pathSegments.last,
        'bytes': bytesBefore.length,
        'sha256': checksum,
        'copiedRaw': input.boxName != 'dbUser',
      });
    }

    final originalFileNames =
        inputs.map((input) => input.file.uri.pathSegments.last).toSet();
    final finalFileNames = <String>{};
    for (final boxName in legacyBoxNames) {
      for (final extension in const ['hive', 'hivec']) {
        final fileName = '$boxName.$extension';
        if (await File(
          '${source.path}${Platform.pathSeparator}$fileName',
        ).exists()) {
          finalFileNames.add(fileName);
        }
      }
    }
    if (originalFileNames.length != finalFileNames.length ||
        !originalFileNames.containsAll(finalFileNames)) {
      throw const LocalDataStorageError('旧 Hive box 列表在备份期间发生变化');
    }

    final manifest = {
      'schemaVersion': supportedSchemaVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'boxes': fileManifest,
      'scholarProjection': scholarProjectionWritten ? projectionFileName : null,
      'scholarProjectionSha256': scholarProjectionChecksum,
      'secureStorageCopied': false,
    };
    await File(
      '${destination.path}${Platform.pathSeparator}$manifestFileName',
    ).writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
      flush: true,
    );
    return LegacyHiveBackupResult(
      directory: destination.path,
      boxFiles: inputs.length,
      scholarProjectionWritten: scholarProjectionWritten,
    );
  }

  /// Reads only the sanitized projection and explicit migration whitelist from
  /// [backupDirectory]. The caller must close any source boxes first because
  /// Hive cannot open the same box name at two paths concurrently.
  Future<LegacyHiveMigrationInput> readBackup({
    required String backupDirectory,
    HiveInterface? hive,
  }) async {
    final directory = Directory(backupDirectory).absolute;
    final manifestFile = File(
      '${directory.path}${Platform.pathSeparator}$manifestFileName',
    );
    final projectionFile = File(
      '${directory.path}${Platform.pathSeparator}$projectionFileName',
    );
    if (!await manifestFile.exists() || !await projectionFile.exists()) {
      throw const LocalDataValidationError('旧数据备份缺少清单或脱敏投影');
    }
    final manifestText = await manifestFile.readAsString();
    final projectionText = await projectionFile.readAsString();
    final manifest = jsonDecode(manifestText);
    final projection = jsonDecode(projectionText);
    if (manifest is! Map ||
        manifest['schemaVersion'] != supportedSchemaVersion ||
        manifest['secureStorageCopied'] != false ||
        manifest['scholarProjectionSha256'] !=
            _checksum(utf8.encode(projectionText)) ||
        manifest['boxes'] is! List ||
        projection is! Map ||
        projection['schemaVersion'] != supportedSchemaVersion ||
        projection['containsCredentials'] != false ||
        projection['scholar'] is! Map) {
      throw const LocalDataValidationError('旧数据备份清单或脱敏投影无效');
    }
    final scholar = Map<String, Object?>.from(projection['scholar'] as Map);
    if (scholar.containsKey('username') || scholar.containsKey('password')) {
      throw const LocalDataValidationError('脱敏旧 Scholar 投影仍包含凭据字段');
    }
    final database = hive ?? Hive;
    registerLegacyAdapters(database);
    final boxesDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}boxes',
    );
    for (final record in manifest['boxes'] as List) {
      if (record is! Map || record['copiedRaw'] != true) continue;
      final fileName = record['sourceFile'];
      final expectedChecksum = record['sha256'];
      if (fileName is! String ||
          expectedChecksum is! String ||
          fileName.contains('/') ||
          fileName.contains('\\')) {
        throw const LocalDataValidationError('旧数据备份文件清单无效');
      }
      final file = File(
        '${boxesDirectory.path}${Platform.pathSeparator}$fileName',
      );
      if (!await file.exists() ||
          _checksum(await file.readAsBytes()) != expectedChecksum) {
        throw const LocalDataValidationError('旧数据备份文件校验失败');
      }
    }

    final stagingDirectory = await Directory.systemTemp.createTemp(
      'celechron-legacy-read-',
    );
    try {
      if (await boxesDirectory.exists()) {
        await for (final entity in boxesDirectory.list(followLinks: false)) {
          if (entity is File &&
              (entity.path.endsWith('.hive') ||
                  entity.path.endsWith('.hivec'))) {
            await entity.copy(
              '${stagingDirectory.path}${Platform.pathSeparator}'
              '${entity.uri.pathSegments.last}',
            );
          }
        }
      }

      Future<Box?> openOptional(String name) async {
        final hiveFile = File(
          '${stagingDirectory.path}${Platform.pathSeparator}$name.hive',
        );
        if (!await hiveFile.exists()) return null;
        return database.openBox(name, path: stagingDirectory.path);
      }

      Box? taskBox;
      Box? optionsBox;
      Box? customGpaBox;
      try {
        taskBox = await openOptional('dbDeadline');
        optionsBox = await openOptional('dbOptions');
        customGpaBox = await openOptional('dbCustomGpa');
        final rawTasks = taskBox?.get('deadlineList') ?? const <Object?>[];
        if (rawTasks is! List || rawTasks.any((value) => value is! Task)) {
          throw const LocalDataValidationError('旧任务列表格式无效');
        }
        final rawTodos = scholar['todos'] ?? const <Object?>[];
        if (rawTodos is! List || rawTodos.any((value) => value is! Map)) {
          throw const LocalDataValidationError('旧 Todo 列表格式无效');
        }
        final todos = <Todo>[];
        for (final value in rawTodos) {
          try {
            todos.add(Todo.fromJson(Map<String, dynamic>.from(value as Map)));
          } on Object {
            // Preserve malformed rows in the original backup for review.
          }
        }
        final options = <String, Object?>{};
        for (final key in const [
          'gpaStrategy',
          'brightnessMode',
          'workTime',
          'restTime',
          'allowTime',
        ]) {
          final value = optionsBox?.get(key);
          if (value != null) options[key] = value;
        }
        final customGpa = <String, Object?>{};
        for (final key in const ['selectList', 'weightedGpa']) {
          final value = customGpaBox?.get(key);
          if (value != null) customGpa[key] = value;
        }
        return LegacyHiveMigrationInput(
          scholar: Map.unmodifiable(scholar),
          tasks: List.unmodifiable(rawTasks.cast<Task>()),
          todos: List.unmodifiable(todos),
          options: Map.unmodifiable(options),
          customGpa: Map.unmodifiable(customGpa),
        );
      } finally {
        for (final box in [taskBox, optionsBox, customGpaBox]) {
          if (box != null && box.isOpen) await box.close();
        }
      }
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }
    }
  }

  static Future<Map<String, dynamic>> _readSanitizedScholarProjection(
    Uint8List bytes,
    HiveInterface hive,
  ) async {
    registerLegacyAdapters(hive);
    final readerName = 'legacy-reader-scholar-${_readerBoxSequence++}';
    final box = await hive.openBox(readerName, bytes: bytes);
    try {
      final scholar = box.get('user');
      if (scholar == null) return <String, dynamic>{};
      if (scholar is! LegacyScholarRecord) {
        throw const LocalDataValidationError('旧 dbUser 中 user 记录类型异常');
      }
      // Keep migration independent from Scholar; discard credential fields
      // even if an unusually old JSON encoding includes them.
      final projection = Map<String, dynamic>.from(scholar.fields)
        ..remove('username')
        ..remove('password');
      return projection;
    } finally {
      await box.close();
    }
  }

  static void registerLegacyAdapters(HiveInterface hive) {
    void registerIfMissing<T>(TypeAdapter<T> adapter) {
      if (!hive.isAdapterRegistered(adapter.typeId)) {
        hive.registerAdapter(adapter);
      }
    }

    registerIfMissing(DurationAdapter());
    registerIfMissing(LegacyScholarRecordAdapter());
    registerIfMissing(DeadlineStatusAdapter());
    registerIfMissing(DeadlineTypeAdapter());
    registerIfMissing(DeadlineRepeatTypeAdapter());
    registerIfMissing(DeadlineAdapter());
    registerIfMissing(PeriodTypeAdapter());
    registerIfMissing(PeriodAdapter());
    registerIfMissing(FuseAdapter());
    registerIfMissing(CourseIdMapAdapter());
  }

  static String _checksum(List<int> bytes) => sha256.convert(bytes).toString();
}

final class _LegacyBoxFile {
  const _LegacyBoxFile(this.boxName, this.file);

  final String boxName;
  final File file;
}
