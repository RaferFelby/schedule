import 'dart:io';

import 'local_data_error.dart';

enum StorageGenerationRole { active, candidate }

/// Describes one isolated generation without opening or creating its files.
final class StorageGenerationManifest {
  StorageGenerationManifest._({
    required this.rootDirectory,
    required this.generationId,
    required this.role,
    this.parentGenerationId,
    required this.legacyRoot,
    required this.schemaVersion,
  });

  static const supportedSchemaVersion = 1;

  final String rootDirectory;
  final String generationId;
  final StorageGenerationRole role;
  final String? parentGenerationId;
  final bool legacyRoot;
  final int schemaVersion;

  String get generationDirectory => legacyRoot
      ? rootDirectory
      : _join(rootDirectory, 'generations', generationId);
  String get academicLocation => generationDirectory;
  String get taskLocation => generationDirectory;
  String get settingsLocation => generationDirectory;
  String get academicBoxName => legacyRoot
      ? 'manual-academic-profile-v1'
      : 'manual-academic-profile-v1-$generationId';
  String get taskBoxName =>
      legacyRoot ? 'manual-preview-v1' : 'manual-preview-v1-$generationId';
  String get settingsBoxName =>
      legacyRoot ? 'manual-settings-v1' : 'manual-settings-v1-$generationId';

  static StorageGenerationManifest active({
    required String rootDirectory,
    required String generationId,
  }) =>
      _create(
        rootDirectory: rootDirectory,
        generationId: generationId,
        role: StorageGenerationRole.active,
      );

  /// Describes data already stored at the original preview directory.
  static StorageGenerationManifest legacyActive({
    required String rootDirectory,
  }) =>
      _create(
        rootDirectory: rootDirectory,
        generationId: 'legacy-preview-v1',
        role: StorageGenerationRole.active,
        legacyRoot: true,
      );

  static StorageGenerationManifest candidateFor({
    required StorageGenerationManifest active,
    required String generationId,
  }) {
    if (active.role != StorageGenerationRole.active) {
      throw const LocalDataValidationError('恢复候选必须关联活动数据代次');
    }
    return _create(
      rootDirectory: active.rootDirectory,
      generationId: generationId,
      role: StorageGenerationRole.candidate,
      parentGenerationId: active.generationId,
    );
  }

  static StorageGenerationManifest _create({
    required String rootDirectory,
    required String generationId,
    required StorageGenerationRole role,
    String? parentGenerationId,
    bool legacyRoot = false,
  }) {
    if (rootDirectory.trim().isEmpty || !Directory(rootDirectory).isAbsolute) {
      throw const LocalDataValidationError('代次根目录必须是绝对路径');
    }
    if (!_isSafeId(generationId) ||
        (parentGenerationId != null && !_isSafeId(parentGenerationId))) {
      throw const LocalDataValidationError('代次 ID 格式无效');
    }
    if (generationId == parentGenerationId) {
      throw const LocalDataValidationError('活动代次与恢复候选必须使用不同 ID');
    }
    if (legacyRoot && role != StorageGenerationRole.active) {
      throw const LocalDataValidationError('恢复候选不能复用 legacy 活动存储根');
    }
    return StorageGenerationManifest._(
      rootDirectory: _trimTrailingSeparators(rootDirectory),
      generationId: generationId,
      role: role,
      parentGenerationId: parentGenerationId,
      legacyRoot: legacyRoot,
      schemaVersion: supportedSchemaVersion,
    );
  }

  factory StorageGenerationManifest.fromJson(Map<String, dynamic> json) {
    final version = json['schemaVersion'];
    final root = json['rootDirectory'];
    final id = json['generationId'];
    final roleName = json['role'];
    final parent = json['parentGenerationId'];
    final legacyRoot = json['legacyRoot'] ?? false;
    if (version != supportedSchemaVersion ||
        root is! String ||
        id is! String ||
        roleName is! String ||
        (parent != null && parent is! String) ||
        legacyRoot is! bool) {
      throw const LocalDataValidationError('存储代次清单格式或版本无效');
    }
    final role = switch (roleName) {
      'active' => StorageGenerationRole.active,
      'candidate' => StorageGenerationRole.candidate,
      _ => throw const LocalDataValidationError('存储代次角色无效'),
    };
    if (role == StorageGenerationRole.active && parent != null) {
      throw const LocalDataValidationError('活动代次不能有父代次');
    }
    if (role == StorageGenerationRole.candidate && parent is! String) {
      throw const LocalDataValidationError('恢复候选缺少父代次 ID');
    }
    final manifest = _create(
      rootDirectory: root,
      generationId: id,
      role: role,
      parentGenerationId: parent as String?,
      legacyRoot: legacyRoot,
    );
    final locations = json['locations'];
    if (locations != null) {
      if (locations is! Map ||
          locations['academic'] != manifest.academicLocation ||
          locations['tasks'] != manifest.taskLocation ||
          locations['settings'] != manifest.settingsLocation) {
        throw const LocalDataValidationError('存储代次数据位置与清单不一致');
      }
    }
    final boxes = json['boxNames'];
    if (boxes != null &&
        (boxes is! Map ||
            boxes['academic'] != manifest.academicBoxName ||
            boxes['tasks'] != manifest.taskBoxName ||
            boxes['settings'] != manifest.settingsBoxName)) {
      throw const LocalDataValidationError('存储代次 box 名称与清单不一致');
    }
    return manifest;
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'rootDirectory': rootDirectory,
        'generationId': generationId,
        'role': role.name,
        'parentGenerationId': parentGenerationId,
        'legacyRoot': legacyRoot,
        'locations': {
          'academic': academicLocation,
          'tasks': taskLocation,
          'settings': settingsLocation,
        },
        'boxNames': {
          'academic': academicBoxName,
          'tasks': taskBoxName,
          'settings': settingsBoxName,
        },
      };

  static bool _isSafeId(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(value);

  static String _join(String base, String first, [String? second]) {
    final separator = Platform.pathSeparator;
    final suffix = second == null ? first : '$first$separator$second';
    return '$base$separator$suffix';
  }

  static String _trimTrailingSeparators(String value) =>
      value == Platform.pathSeparator
          ? value
          : value.replaceFirst(RegExp(r'[\\/]+$'), '');
}

abstract interface class GenerationDirectoryCleaner {
  Future<void> deleteGenerationDirectory(String path);
}

/// Allows cleanup only for a candidate belonging to the active generation.
final class StorageGenerationCleanup {
  const StorageGenerationCleanup();

  Future<void> cleanCandidate({
    required StorageGenerationManifest active,
    required StorageGenerationManifest candidate,
    required GenerationDirectoryCleaner cleaner,
  }) async {
    if (active.role != StorageGenerationRole.active ||
        candidate.role != StorageGenerationRole.candidate ||
        candidate.parentGenerationId != active.generationId ||
        candidate.rootDirectory != active.rootDirectory ||
        candidate.generationDirectory == active.generationDirectory) {
      throw const LocalDataValidationError('拒绝清理非当前活动代次的恢复候选');
    }
    await cleaner.deleteGenerationDirectory(candidate.generationDirectory);
  }
}
