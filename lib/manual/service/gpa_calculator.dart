import 'grade_calculator.dart';

/// A course calculation paired with the credit weight for its GPA.
final class GpaContribution {
  const GpaContribution({
    required this.calculation,
    required this.courseCredits,
    this.weight = 1,
  });

  final GradeCalculation calculation;
  final double? courseCredits;
  final double weight;
}

/// A GPA result and explicit counts for excluded or unavailable inputs.
final class GpaSummary {
  const GpaSummary({
    required this.gpa,
    required this.includedCredits,
    required this.includedCount,
    required this.excludedCount,
    required this.unknownCreditCount,
  });

  final double? gpa;
  final double includedCredits;
  final int includedCount;
  final int excludedCount;
  final int unknownCreditCount;

  bool get hasResult => gpa != null;
}

/// Calculates a credit-weighted GPA from already validated course results.
final class GpaCalculator {
  const GpaCalculator._();

  static GpaSummary calculate(Iterable<GpaContribution> contributions) {
    var weightedPoints = 0.0;
    var includedCredits = 0.0;
    var includedCount = 0;
    var excludedCount = 0;
    var unknownCreditCount = 0;

    for (final contribution in contributions) {
      final calculation = contribution.calculation;
      if (!calculation.includedInGpa || calculation.gradePoint == null) {
        excludedCount++;
        continue;
      }
      final credits = contribution.courseCredits;
      if (!contribution.weight.isFinite || contribution.weight < 0) {
        throw ArgumentError.value(
          contribution.weight,
          'weight',
          '必须是非负有限数值',
        );
      }
      if (credits != null && (!credits.isFinite || credits < 0)) {
        throw ArgumentError.value(credits, 'courseCredits', '必须是非负有限数值');
      }
      if (credits == null) {
        unknownCreditCount++;
        excludedCount++;
        continue;
      }
      if (credits == 0) {
        excludedCount++;
        continue;
      }
      final gradePoint = calculation.gradePoint!;
      if (!gradePoint.isFinite || gradePoint < 0) {
        throw ArgumentError.value(gradePoint, 'gradePoint', '必须是非负有限数值');
      }
      weightedPoints += gradePoint * contribution.weight * credits;
      includedCredits += credits;
      includedCount++;
      if (!weightedPoints.isFinite || !includedCredits.isFinite) {
        throw ArgumentError('GPA 汇总超出可表示范围');
      }
    }

    return GpaSummary(
      gpa: includedCount == 0 ? null : weightedPoints / includedCredits,
      includedCredits: includedCredits,
      includedCount: includedCount,
      excludedCount: excludedCount,
      unknownCreditCount: unknownCreditCount,
    );
  }
}
