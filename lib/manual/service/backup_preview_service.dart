import 'dart:convert';

import '../../debug/manual_preview_task_store.dart';
import '../model/academic_profile.dart';
import 'backup_service.dart';

final class BackupPreviewResult {
  BackupPreviewResult({
    required Iterable<String> errors,
    required Map<String, int> recordCounts,
    this.backupVersion,
    this.academicRevision,
    this.taskPlanningRevision,
  })  : errors = List.unmodifiable(errors),
        recordCounts = Map.unmodifiable(recordCounts);

  final List<String> errors;
  final Map<String, int> recordCounts;
  final int? backupVersion;
  final int? academicRevision;
  final int? taskPlanningRevision;

  bool get isValid => errors.isEmpty;
}

/// Validates backup contents without opening or writing any data store.
final class BackupPreviewService {
  const BackupPreviewService();

  BackupPreviewResult previewJson(String encoded) {
    final errors = <String>[];
    final counts = <String, int>{};
    Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      return BackupPreviewResult(
        errors: const ['文件不是有效的 JSON'],
        recordCounts: counts,
      );
    }
    if (decoded is! Map) {
      return BackupPreviewResult(
        errors: const ['备份根节点必须是 JSON 对象'],
        recordCounts: counts,
      );
    }
    final json = Map<String, dynamic>.from(decoded);
    if (json['format'] != BackupService.formatName) {
      errors.add('文件格式不是 Celechron 手动录入备份');
    }

    final rawVersion = json['backupVersion'];
    final version = rawVersion is int ? rawVersion : null;
    if (version == null) {
      errors.add('缺少有效的备份版本号');
    } else if (version > BackupService.backupVersion) {
      errors.add('备份版本 $version 高于当前支持版本');
    } else if (version != BackupService.backupVersion) {
      errors.add('不支持的备份版本 $version');
    }

    final exportedAt = json['exportedAt'];
    if (exportedAt is! String || DateTime.tryParse(exportedAt) == null) {
      errors.add('导出时间缺失或格式无效');
    }

    AcademicProfile? profile;
    final rawAcademic = json['academic'];
    if (rawAcademic is! Map) {
      errors.add('学业数据缺失或格式无效');
      profile = null;
    } else {
      try {
        profile = AcademicProfile.fromJson(
          Map<String, dynamic>.from(rawAcademic),
        );
        counts.addAll({
          'semesters': profile.semesters.length,
          'courses': profile.courses.length,
          'sessionRules': profile.sessionRules.length,
          'exams': profile.exams.length,
          'grades': profile.grades.length,
          'practiceRecords': profile.practiceRecords.length,
        });
      } on Object catch (error) {
        errors.add('学业数据无效：$error');
        profile = null;
      }
    }

    List<dynamic>? tasks;
    try {
      tasks = ManualPreviewTaskStore.decodeTasksForBackup(json['tasks']);
      counts['tasks'] = tasks.length;
    } on Object catch (error) {
      errors.add('任务数据无效：$error');
      tasks = null;
    }
    if (tasks != null) {
      final taskIds = tasks.map((task) => task.uid).toSet();
      if (taskIds.length != tasks.length) errors.add('任务 ID 重复');
      final courseIds = profile?.courses.map((course) => course.id).toSet();
      if (courseIds != null &&
          tasks.any((task) =>
              task.courseId != null && !courseIds.contains(task.courseId))) {
        errors.add('任务引用了备份中不存在的课程');
      }
    }
    final rawSettings = json['settings'];
    if (rawSettings is! Map) {
      errors.add('设置快照缺失或格式无效');
      counts['settings'] = 0;
    } else {
      final settings = Map<String, dynamic>.from(rawSettings);
      if (settings['schemaVersion'] != BackupService.settingsVersion) {
        errors.add('不支持的设置快照版本');
      }
      final values = settings['values'];
      if (values is! Map || values.keys.any((key) => key is! String)) {
        errors.add('设置内容必须是字符串键的对象');
        counts['settings'] = 0;
      } else {
        try {
          BackupService.validateSettings(Map<String, Object?>.from(values));
          counts['settings'] = values.length;
        } on FormatException catch (error) {
          errors.add(error.message);
          counts['settings'] = values.length;
        }
      }
    }

    final revisions = json['revisions'];
    int? academicRevision;
    int? taskPlanningRevision;
    if (revisions is! Map) {
      errors.add('revision 信息缺失或格式无效');
    } else {
      final revisionMap = Map<String, dynamic>.from(revisions);
      final rawAcademicRevision = revisionMap['academic'];
      final rawTaskRevision = revisionMap['taskPlanning'];
      if (rawAcademicRevision is int && rawAcademicRevision >= 0) {
        academicRevision = rawAcademicRevision;
        if (profile != null && profile.revision != academicRevision) {
          errors.add('学业 revision 与快照内容不一致');
        }
      } else {
        errors.add('学业 revision 无效');
      }
      if (rawTaskRevision is int && rawTaskRevision >= 0) {
        taskPlanningRevision = rawTaskRevision;
      } else {
        errors.add('任务 revision 无效');
      }
    }

    return BackupPreviewResult(
      errors: errors,
      recordCounts: counts,
      backupVersion: version,
      academicRevision: academicRevision,
      taskPlanningRevision: taskPlanningRevision,
    );
  }
}
