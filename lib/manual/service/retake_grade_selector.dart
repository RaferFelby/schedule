import '../model/academic_profile.dart';
import '../model/local_course.dart';
import '../model/retake_selection_strategy.dart';
import 'grade_calculator.dart';

/// Selects one course offering per explicit retake group without sorting source lists.
final class RetakeGradeSelector {
  const RetakeGradeSelector._();

  static Set<String> selectedCourseIds(AcademicProfile profile) {
    final courses = profile.courses
        .where((course) => course.selectedForGpa)
        .toList(growable: false);
    final gradesByCourse = {
      for (final grade in profile.grades) grade.courseId: grade
    };
    final semestersById = {
      for (final semester in profile.semesters) semester.id: semester,
    };
    final groups = <String, List<LocalCourse>>{};
    final selected = <String>{};

    for (final course in courses) {
      final groupId = course.retakeGroupId;
      if (groupId == null) {
        selected.add(course.id);
      } else {
        groups.putIfAbsent(groupId, () => []).add(course);
      }
    }

    int compareAttempt(LocalCourse left, LocalCourse right) {
      final leftSemester = semestersById[left.semesterId]!;
      final rightSemester = semestersById[right.semesterId]!;
      final byDate = leftSemester.startDate.compareTo(rightSemester.startDate);
      return byDate != 0 ? byDate : left.id.compareTo(right.id);
    }

    double? usableGpa(LocalCourse course) {
      final grade = gradesByCourse[course.id];
      if (grade == null) return null;
      final calculation =
          GradeCalculator.calculate(record: grade, course: course);
      return calculation.includedInGpa ? calculation.gradePoint : null;
    }

    for (final members in groups.values) {
      final attempts = [...members]..sort(compareAttempt);
      final strategy = attempts.first.retakeStrategy;
      LocalCourse winner = attempts.first;
      if (strategy == RetakeSelectionStrategy.highestGpa) {
        double? best;
        for (final attempt in attempts) {
          final value = usableGpa(attempt);
          if (value != null && (best == null || value > best)) {
            winner = attempt;
            best = value;
          }
        }
      }
      selected.add(winner.id);
    }

    return Set.unmodifiable(selected);
  }
}
