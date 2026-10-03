import '../model/academic_profile.dart';

/// Builds a validated academic snapshot without a course and its dependants.
final class CourseDeletionService {
  const CourseDeletionService._();

  static AcademicProfile removeCourse(
    AcademicProfile current,
    String courseId,
  ) {
    if (!current.courses.any((course) => course.id == courseId)) return current;

    return AcademicProfile(
      schemaVersion: current.schemaVersion,
      revision: current.revision,
      planningRevision: current.planningRevision,
      currentSemesterId: current.currentSemesterId,
      semesters: current.semesters,
      timeSlots: current.timeSlots,
      courses:
          current.courses.where((course) => course.id != courseId).toList(),
      sessionRules: current.sessionRules
          .where((rule) => rule.courseId != courseId)
          .toList(),
      exams: current.exams.where((exam) => exam.courseId != courseId).toList(),
      grades:
          current.grades.where((grade) => grade.courseId != courseId).toList(),
      practiceRecords: current.practiceRecords,
    );
  }
}
