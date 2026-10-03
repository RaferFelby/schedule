import '../model/academic_profile.dart';
import '../../model/task.dart';

final class MigrationCount {
  const MigrationCount({
    required this.sourceRecords,
    required this.convertedRecords,
    required this.unresolvedRecords,
    this.ignoredRecords = 0,
  });

  final int sourceRecords;
  final int convertedRecords;
  final int unresolvedRecords;
  final int ignoredRecords;
}

final class MigrationValidationIssue {
  const MigrationValidationIssue({
    required this.code,
    required this.message,
    required this.blocking,
    this.sourcePath,
    this.sourceRecord,
  });

  final String code;
  final String message;
  final bool blocking;
  final List<Object?>? sourcePath;
  final Object? sourceRecord;

  bool get canCorrect => sourcePath != null;
}

final class MigrationValidationReport {
  const MigrationValidationReport({
    required this.counts,
    required this.issues,
  });

  final Map<String, MigrationCount> counts;
  final List<MigrationValidationIssue> issues;

  int get blockingCount => issues.where((issue) => issue.blocking).length;
  int get reviewCount => issues.length - blockingCount;
}

/// Validates an assembled candidate only; this class never commits a generation.
final class ManualMigrationValidator {
  const ManualMigrationValidator();

  MigrationValidationReport validate({
    required AcademicProfile profile,
    required Iterable<Task> tasks,
    required Map<String, MigrationCount> counts,
  }) {
    final issues = <MigrationValidationIssue>[];
    for (final entry in counts.entries) {
      final count = entry.value;
      if ([
        count.sourceRecords,
        count.convertedRecords,
        count.unresolvedRecords,
        count.ignoredRecords,
      ].any((value) => value < 0)) {
        issues.add(MigrationValidationIssue(
          code: 'negative-count:${entry.key}',
          message: '${entry.key} 包含负数记录计数',
          blocking: true,
        ));
        continue;
      }
      final accounted = count.convertedRecords +
          count.unresolvedRecords +
          count.ignoredRecords;
      if (accounted != count.sourceRecords) {
        issues.add(MigrationValidationIssue(
          code: 'count-mismatch:${entry.key}',
          message: '${entry.key} 来源 ${count.sourceRecords} 条，已转换 '
              '${count.convertedRecords} 条、待确认 ${count.unresolvedRecords} 条、'
              '明确忽略 ${count.ignoredRecords} 条，尚有 ${count.sourceRecords - accounted} 条未解释',
          blocking: true,
        ));
      }
    }

    final ids = <String>{};
    void add(String kind, Iterable<String> values) {
      for (final id in values) {
        if (!ids.add(id)) {
          issues.add(MigrationValidationIssue(
            code: 'duplicate-id:$kind:$id',
            message: '$kind 候选 ID 重复：$id',
            blocking: true,
          ));
        }
      }
    }

    add('academic', [
      ...profile.semesters.map((value) => value.id),
      ...profile.timeSlots.map((value) => value.id),
      ...profile.courses.map((value) => value.id),
      ...profile.sessionRules.map((value) => value.id),
      ...profile.exams.map((value) => value.id),
      ...profile.grades.map((value) => value.id),
      ...profile.practiceRecords.map((value) => value.id),
    ]);
    add('task', tasks.map((task) => task.uid));

    final semesterIds = profile.semesters.map((value) => value.id).toSet();
    final courseIds = profile.courses.map((value) => value.id).toSet();
    if (profile.currentSemesterId != null &&
        !semesterIds.contains(profile.currentSemesterId)) {
      issues.add(const MigrationValidationIssue(
        code: 'missing-current-semester',
        message: '当前学期引用不存在的学期',
        blocking: true,
      ));
    }
    for (final course in profile.courses) {
      if (!semesterIds.contains(course.semesterId)) {
        issues.add(MigrationValidationIssue(
          code: 'missing-course-semester:${course.id}',
          message: '课程 ${course.id} 引用了不存在的学期',
          blocking: true,
        ));
      }
    }
    for (final task in tasks) {
      if (task.courseId != null && !courseIds.contains(task.courseId)) {
        issues.add(MigrationValidationIssue(
          code: 'missing-task-course:${task.uid}',
          message: '任务 ${task.uid} 引用了不存在的课程',
          blocking: true,
        ));
      }
    }
    return MigrationValidationReport(
      counts: Map.unmodifiable(counts),
      issues: List.unmodifiable(issues),
    );
  }
}
