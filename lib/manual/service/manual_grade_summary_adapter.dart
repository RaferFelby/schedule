import '../model/academic_profile.dart';
import '../model/grade_record.dart';
import 'grade_calculator.dart';
import 'gpa_calculator.dart';
import 'retake_grade_selector.dart';

/// Builds GPA and earned-credit summaries from the local profile snapshot.
final class ManualGradeSummary {
  const ManualGradeSummary({
    required this.gpa,
    required this.earnedCredits,
    required this.unknownEarnedCreditCount,
  });

  final GpaSummary gpa;
  final double earnedCredits;
  final int unknownEarnedCreditCount;
}

final class ManualGradeSummaryAdapter {
  const ManualGradeSummaryAdapter._();

  static ManualGradeSummary calculate(
    AcademicProfile profile, {
    String? semesterId,
  }) {
    final coursesById = {
      for (final course in profile.courses) course.id: course
    };
    final selectedCourseIds = RetakeGradeSelector.selectedCourseIds(profile);
    final contributions = <GpaContribution>[];
    var earnedCredits = 0.0;
    var unknownEarnedCreditCount = 0;

    for (final record in profile.grades) {
      final course = coursesById[record.courseId]!;
      if (!selectedCourseIds.contains(course.id)) continue;
      if (semesterId != null && course.semesterId != semesterId) continue;
      final calculation = GradeCalculator.calculate(
        record: record,
        course: course,
      );
      contributions.add(GpaContribution(
        calculation: calculation,
        courseCredits: course.credits,
        weight: course.gpaWeight,
      ));
      if (record.status == LocalGradeStatus.recorded &&
          record.countsTowardCredits) {
        final earned = calculation.earnedCredits;
        if (earned == null) {
          unknownEarnedCreditCount++;
        } else {
          earnedCredits += earned;
        }
      }
    }

    return ManualGradeSummary(
      gpa: GpaCalculator.calculate(contributions),
      earnedCredits: earnedCredits,
      unknownEarnedCreditCount: unknownEarnedCreditCount,
    );
  }
}
