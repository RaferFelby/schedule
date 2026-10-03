import 'package:celechron/model/task.dart';
import 'package:celechron/model/todo.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/manual_user_preferences.dart';

import 'course_converter.dart';
import 'exam_converter.dart';
import 'grade_converter.dart';
import 'grade_preference_converter.dart';
import 'migration_validator.dart';
import 'practice_converter.dart';
import 'semester_converter.dart';
import 'session_converter.dart';
import 'task_converter.dart';

/// Pure conversion of sanitized legacy projections into a migration candidate.
/// It performs no storage, credential, networking, or active-generation work.
final class LegacyMigrationAssembler {
  const LegacyMigrationAssembler();

  LegacyMigrationAssembly assemble({
    required Map<String, Object?> scholar,
    Iterable<Task> legacyTasks = const [],
    Iterable<Todo> todos = const [],
    Map<String, Object?> legacyOptions = const {},
    Map<String, Object?> legacyCustomGpa = const {},
  }) {
    final sourceTasks = List<Task>.unmodifiable(legacyTasks);
    final sourceTodos = List<Todo>.unmodifiable(todos);
    final semesterResult = const LegacySemesterConverter().convert(scholar);
    final semesterIds =
        semesterResult.semesters.map((value) => value.id).toSet();
    final courseResult = const LegacyCourseConverter().convert(
      scholar: scholar,
      convertedSemesterIds: semesterIds,
    );
    final sessionResult = const LegacySessionConverter().convert(
      scholar: scholar,
      semesters: semesterResult.semesters,
      timeSlots: semesterResult.timeSlots,
      courseMappings: courseResult.idMappings,
    );
    final examResult = const LegacyExamConverter().convert(
      scholar: scholar,
      courseMappings: courseResult.idMappings,
    );
    final gradeResult = const LegacyGradeConverter().convert(
      scholar: scholar,
      courseMappings: courseResult.idMappings,
      courses: courseResult.courses,
    );
    final preferenceResult = const LegacyGradePreferenceConverter().convert(
      courses: courseResult.courses,
      gradeIdMappings: gradeResult.gradeIdMappings,
      legacyOptions: legacyOptions,
      legacyCustomGpa: legacyCustomGpa,
    );
    final practiceResult = const LegacyPracticeConverter().convert(scholar);
    final taskResult = const LegacyTaskConverter().convert(
      legacyTasks: sourceTasks,
      todos: sourceTodos,
    );
    final userPreferences = ManualUserPreferences.fromLegacy(legacyOptions);

    final profile = AcademicProfile(
      schemaVersion: AcademicProfile.supportedSchemaVersion,
      revision: 0,
      semesters: semesterResult.semesters,
      timeSlots: semesterResult.timeSlots,
      courses: preferenceResult.courses,
      sessionRules: sessionResult.sessionRules,
      exams: examResult.exams,
      grades: gradeResult.grades,
      practiceRecords: practiceResult.records,
    );
    final taskList = List<Task>.unmodifiable(taskResult.tasks);
    final counts = <String, MigrationCount>{
      '学期': _count(_listLength(scholar['semesters']), profile.semesters.length,
          semesterResult.unresolvedSemesters.length),
      '课程': _count(_courseSourceCount(scholar), profile.courses.length,
          courseResult.unresolvedCourses.length),
      '上课安排': _count(_sessionSourceCount(scholar), profile.sessionRules.length,
          sessionResult.unresolvedSessions.length),
      '考试': _count(_examSourceCount(scholar), profile.exams.length,
          examResult.unresolvedExams.length),
      '成绩': _count(_gradeSourceCount(scholar), profile.grades.length,
          gradeResult.unresolvedGrades.length),
      '实践明细': _count(
          _listLength(scholar['practiceScoreItems']),
          profile.practiceRecords.length,
          practiceResult.unresolvedRecords.length),
      '任务与作业': _count(
        sourceTasks.length + sourceTodos.length,
        taskList.length,
        taskResult.unresolvedTodos.length,
      ),
    };

    final base = const ManualMigrationValidator().validate(
      profile: profile,
      tasks: taskList,
      counts: counts,
    );
    final issues = <MigrationValidationIssue>[...base.issues];
    final sourceRoot = <String, Object?>{
      'scholar': scholar,
      'todos': sourceTodos.map((todo) => todo.toJson()).toList(),
      'legacyOptions': legacyOptions,
      'legacyCustomGpa': legacyCustomGpa,
    };
    void addUnresolved(String category, Iterable<Object?> rows) {
      for (var index = 0; index < rows.length; index++) {
        final row = rows.elementAt(index);
        final metadata =
            row is Map ? Map<String, Object?>.from(row) : <String, Object?>{};
        final sourcePath = _sourcePath(category, metadata);
        issues.add(MigrationValidationIssue(
          code: 'legacy-unresolved:$category:$index',
          message: '$category 第 ${index + 1} 条旧记录无法无损转换；原始内容仍保存在旧数据备份中',
          blocking: true,
          sourcePath: sourcePath,
          sourceRecord:
              sourcePath == null ? null : _valueAtPath(sourceRoot, sourcePath),
        ));
      }
    }

    addUnresolved('学期', semesterResult.unresolvedSemesters);
    addUnresolved('课程', courseResult.unresolvedCourses);
    addUnresolved('上课安排', sessionResult.unresolvedSessions);
    addUnresolved('考试', examResult.unresolvedExams);
    addUnresolved('成绩', gradeResult.unresolvedGrades);
    addUnresolved('实践明细', practiceResult.unresolvedRecords);
    addUnresolved('任务/作业', taskResult.unresolvedTodos);
    addUnresolved('GPA 偏好', preferenceResult.unresolvedPreferences);
    addUnresolved('实践汇总', practiceResult.unresolvedSummary);

    final review = <String>[
      ...semesterResult.reviewItems,
      ...courseResult.reviewItems,
      ...sessionResult.reviewItems,
      ...examResult.reviewItems,
      ...gradeResult.reviewItems,
      ...preferenceResult.reviewItems,
      ...practiceResult.reviewItems,
      ...taskResult.reviewItems,
    ];
    if (practiceResult.historicalSummary != null) {
      review.add('旧实践历史汇总保留在备份中；手动版只导入可编辑的实践明细');
    }
    if (semesterResult.semesters.isNotEmpty) {
      review.add('旧数据没有明确的当前学期 ID；当前学期留空，由用户选择');
    }

    return LegacyMigrationAssembly(
      profile: profile,
      tasks: taskList,
      settings: userPreferences.toJson(),
      report: MigrationValidationReport(
        counts: base.counts,
        issues: List.unmodifiable(issues),
      ),
      reviewItems: List.unmodifiable(review.toSet()),
    );
  }

  static MigrationCount _count(int source, int converted, int unresolved) {
    final completeUnresolved =
        unresolved > source - converted ? unresolved : source - converted;
    final safeUnresolved =
        completeUnresolved < 0 ? unresolved : completeUnresolved;
    return MigrationCount(
      sourceRecords: converted + safeUnresolved,
      convertedRecords: converted,
      unresolvedRecords: safeUnresolved,
    );
  }

  static int _listLength(Object? value) => value is List ? value.length : 0;

  static List<Object?>? _sourcePath(
    String category,
    Map<String, Object?> row,
  ) {
    final semesterIndex = row['semesterIndex'];
    final courseKey = row['courseMapKey'] ?? row['sourceMapKey'];
    final sourceIndex = row['sourceIndex'];
    switch (category) {
      case '学期':
        return sourceIndex is int
            ? ['scholar', 'semesters', sourceIndex]
            : null;
      case '课程':
        return semesterIndex is int && courseKey != null
            ? ['scholar', 'semesters', semesterIndex, 'courses', courseKey]
            : null;
      case '上课安排':
        final sessionIndex = row['sessionIndex'];
        return semesterIndex is int && courseKey != null && sessionIndex is int
            ? [
                'scholar',
                'semesters',
                semesterIndex,
                'courses',
                courseKey,
                'sessions',
                sessionIndex,
              ]
            : null;
      case '考试':
        final examIndex = row['examIndex'];
        if (semesterIndex is! int || examIndex is! int) return null;
        return courseKey == null
            ? ['scholar', 'semesters', semesterIndex, 'exams', examIndex]
            : [
                'scholar',
                'semesters',
                semesterIndex,
                'courses',
                courseKey,
                'exams',
                examIndex,
              ];
      case '成绩':
        final gradeIndex = row['gradeIndex'];
        switch (row['sourceKind']) {
          case 'courseGrade':
            return semesterIndex is int && courseKey != null
                ? [
                    'scholar',
                    'semesters',
                    semesterIndex,
                    'courses',
                    courseKey,
                    'grade',
                  ]
                : null;
          case 'semesterGrades':
            return semesterIndex is int && gradeIndex is int
                ? ['scholar', 'semesters', semesterIndex, 'grades', gradeIndex]
                : null;
          case 'globalGrades':
            final groupKey = row['legacyGradeGroupKey'];
            return groupKey != null && gradeIndex is int
                ? ['scholar', 'grades', groupKey, gradeIndex]
                : null;
          default:
            return null;
        }
      case '实践明细':
        if (sourceIndex is int) {
          return ['scholar', 'practiceScoreItems', sourceIndex];
        }
        return ['scholar', 'practiceScoreItems'];
      case '任务/作业':
        return sourceIndex is int ? ['todos', sourceIndex] : null;
      case 'GPA 偏好':
        final field = row['field'];
        if (field == 'gpaStrategy') return ['legacyOptions', field];
        if (field == 'selectList' || field == 'weightedGpa') {
          return ['legacyCustomGpa', field];
        }
        return null;
      case '实践汇总':
        final field = row['field'];
        return field is String ? ['scholar', field] : null;
      default:
        return null;
    }
  }

  static Object? _valueAtPath(Object? root, List<Object?> path) {
    var value = root;
    for (final segment in path) {
      if (segment is String && value is Map) {
        value = value[segment];
      } else if (segment is int &&
          value is List &&
          segment >= 0 &&
          segment < value.length) {
        value = value[segment];
      } else {
        return null;
      }
    }
    return value;
  }

  static int _courseSourceCount(Map<String, Object?> scholar) {
    var count = 0;
    for (final semester in scholar['semesters'] is List
        ? scholar['semesters'] as List
        : const []) {
      if (semester is Map && semester['courses'] is Map) {
        count += (semester['courses'] as Map).length;
      }
    }
    return count;
  }

  static int _sessionSourceCount(Map<String, Object?> scholar) {
    var count = 0;
    for (final semester in scholar['semesters'] is List
        ? scholar['semesters'] as List
        : const []) {
      if (semester is! Map || semester['courses'] is! Map) continue;
      for (final course in (semester['courses'] as Map).values) {
        if (course is Map) count += _listLength(course['sessions']);
      }
    }
    return count;
  }

  static int _examSourceCount(Map<String, Object?> scholar) {
    var count = 0;
    for (final semester in scholar['semesters'] is List
        ? scholar['semesters'] as List
        : const []) {
      if (semester is! Map) continue;
      count += _listLength(semester['exams']);
      if (semester['courses'] is Map) {
        for (final course in (semester['courses'] as Map).values) {
          if (course is Map) count += _listLength(course['exams']);
        }
      }
    }
    return count;
  }

  static int _gradeSourceCount(Map<String, Object?> scholar) {
    var count = 0;
    for (final semester in scholar['semesters'] is List
        ? scholar['semesters'] as List
        : const []) {
      if (semester is! Map) continue;
      count += _listLength(semester['grades']);
      if (semester['courses'] is Map) {
        for (final course in (semester['courses'] as Map).values) {
          if (course is! Map) continue;
          if (course['grade'] != null) count++;
        }
      }
    }
    if (scholar['grades'] is Map) {
      for (final grades in (scholar['grades'] as Map).values) {
        count += _listLength(grades);
      }
    }
    return count;
  }
}

final class LegacyMigrationAssembly {
  const LegacyMigrationAssembly({
    required this.profile,
    required this.tasks,
    required this.settings,
    required this.report,
    required this.reviewItems,
  });

  final AcademicProfile profile;
  final List<Task> tasks;
  final Map<String, Object?> settings;
  final MigrationValidationReport report;
  final List<String> reviewItems;
}
