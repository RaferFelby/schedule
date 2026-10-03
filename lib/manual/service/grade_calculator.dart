import '../model/grade_record.dart';
import '../model/local_course.dart';

/// Calculates the values that can be derived for one recorded course grade.
final class GradeCalculator {
  const GradeCalculator._();

  static GradeCalculation calculate({
    required GradeRecord record,
    required LocalCourse course,
    double? resolvedGradePoint,
    bool? explicitlyPassed,
  }) {
    if (record.courseId != course.id) {
      throw ArgumentError('成绩记录与课程关联不一致');
    }
    if (resolvedGradePoint != null &&
        (!resolvedGradePoint.isFinite || resolvedGradePoint < 0)) {
      throw ArgumentError.value(
        resolvedGradePoint,
        'resolvedGradePoint',
        '必须是非负有限数值',
      );
    }
    if (record.status == LocalGradeStatus.notRecorded) {
      return const GradeCalculation(
        gradePoint: null,
        includedInGpa: false,
        earnedCredits: null,
      );
    }

    final gradePoint = record.method == LocalGradingMethod.directGpa
        ? record.gradePoint
        : resolvedGradePoint;
    final passed = explicitlyPassed ?? _knownPassResult(record, gradePoint);
    final earnedCredits = !record.countsTowardCredits
        ? 0.0
        : passed == null || course.credits == null
            ? null
            : passed
                ? course.credits
                : 0.0;

    return GradeCalculation(
      gradePoint: gradePoint,
      includedInGpa: record.countsTowardGpa && gradePoint != null,
      earnedCredits: earnedCredits,
    );
  }

  static bool? _knownPassResult(GradeRecord record, double? gradePoint) {
    switch (record.method) {
      case LocalGradingMethod.percentage:
        return record.rawScore == 0 ? false : null;
      case LocalGradingMethod.letter:
        return switch (record.gradeLabel?.trim().toUpperCase()) {
          'F' || '不及格' || '不合格' => false,
          _ => null,
        };
      case LocalGradingMethod.passFail:
        return switch (record.gradeLabel?.trim().toLowerCase()) {
          '合格' || '通过' || 'pass' || 'passed' => true,
          '不合格' || '不通过' || 'fail' || 'failed' => false,
          _ => null,
        };
      case LocalGradingMethod.directGpa:
        return gradePoint == null ? null : gradePoint > 0;
    }
  }
}

final class GradeCalculation {
  const GradeCalculation({
    required this.gradePoint,
    required this.includedInGpa,
    required this.earnedCredits,
  });

  final double? gradePoint;
  final bool includedInGpa;

  /// Null means the grade or its pass result is not known well enough to derive.
  final double? earnedCredits;
}
