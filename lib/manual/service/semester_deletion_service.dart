import 'package:celechron/model/task.dart';

import '../model/academic_profile.dart';

final class SemesterDeletionImpact {
  const SemesterDeletionImpact({
    required this.semesterId,
    required this.semesterName,
    required this.courseIds,
    required this.sessionRuleCount,
    required this.examCount,
    required this.gradeCount,
    required this.taskCount,
  });

  final String semesterId;
  final String semesterName;
  final List<String> courseIds;
  final int sessionRuleCount;
  final int examCount;
  final int gradeCount;
  final int taskCount;
}

/// Calculates impact and creates a new profile after semester cascades.
final class SemesterDeletionService {
  const SemesterDeletionService._();

  static SemesterDeletionImpact? impact({
    required AcademicProfile profile,
    required Iterable<Task> tasks,
    required String semesterId,
  }) {
    final semester =
        profile.semesters.where((item) => item.id == semesterId).firstOrNull;
    if (semester == null) return null;
    final courseIds = profile.courses
        .where((course) => course.semesterId == semesterId)
        .map((course) => course.id)
        .toList()
      ..sort();
    final ids = courseIds.toSet();
    return SemesterDeletionImpact(
      semesterId: semesterId,
      semesterName: semester.name,
      courseIds: List.unmodifiable(courseIds),
      sessionRuleCount: profile.sessionRules
          .where((rule) => ids.contains(rule.courseId))
          .length,
      examCount:
          profile.exams.where((exam) => ids.contains(exam.courseId)).length,
      gradeCount:
          profile.grades.where((grade) => ids.contains(grade.courseId)).length,
      taskCount: tasks.where((task) => ids.contains(task.courseId)).length,
    );
  }

  static AcademicProfile removeSemester(
    AcademicProfile current,
    String semesterId,
  ) {
    if (!current.semesters.any((semester) => semester.id == semesterId)) {
      return current;
    }
    final courseIds = current.courses
        .where((course) => course.semesterId == semesterId)
        .map((course) => course.id)
        .toSet();
    return AcademicProfile(
      schemaVersion: current.schemaVersion,
      revision: current.revision,
      planningRevision: current.planningRevision,
      currentSemesterId: current.currentSemesterId == semesterId
          ? null
          : current.currentSemesterId,
      semesters: current.semesters
          .where((semester) => semester.id != semesterId)
          .toList(),
      timeSlots: current.timeSlots,
      courses: current.courses
          .where((course) => course.semesterId != semesterId)
          .toList(),
      sessionRules: current.sessionRules
          .where((rule) => !courseIds.contains(rule.courseId))
          .toList(),
      exams: current.exams
          .where((exam) => !courseIds.contains(exam.courseId))
          .toList(),
      grades: current.grades
          .where((grade) => !courseIds.contains(grade.courseId))
          .toList(),
      practiceRecords: current.practiceRecords,
    );
  }
}
