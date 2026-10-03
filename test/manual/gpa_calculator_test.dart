import 'package:celechron/manual/service/grade_calculator.dart';
import 'package:celechron/manual/service/gpa_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

GradeCalculation _calculation({
  double? gradePoint,
  bool included = true,
}) =>
    GradeCalculation(
      gradePoint: gradePoint,
      includedInGpa: included,
      earnedCredits: null,
    );

void main() {
  test('calculates a credit-weighted GPA', () {
    final summary = GpaCalculator.calculate([
      GpaContribution(
        calculation: _calculation(gradePoint: 4),
        courseCredits: 2,
      ),
      GpaContribution(
        calculation: _calculation(gradePoint: 3),
        courseCredits: 3,
      ),
    ]);

    expect(summary.gpa, closeTo(3.4, 1e-12));
    expect(summary.includedCredits, 5);
    expect(summary.includedCount, 2);
    expect(summary.hasResult, isTrue);
  });

  test('applies course weight to points while retaining credit denominator',
      () {
    final summary = GpaCalculator.calculate([
      GpaContribution(
        calculation: _calculation(gradePoint: 4),
        courseCredits: 2,
        weight: 0.5,
      ),
      GpaContribution(
        calculation: _calculation(gradePoint: 3),
        courseCredits: 3,
      ),
    ]);

    expect(summary.gpa, closeTo(2.6, 1e-12));
    expect(summary.includedCredits, 5);
  });

  test('returns no GPA when there are no valid credit-weighted grades', () {
    final summary = GpaCalculator.calculate([
      GpaContribution(
        calculation: _calculation(gradePoint: 4),
        courseCredits: null,
      ),
      GpaContribution(
        calculation: _calculation(gradePoint: 3, included: false),
        courseCredits: 3,
      ),
      GpaContribution(
        calculation: _calculation(gradePoint: 2),
        courseCredits: 0,
      ),
    ]);

    expect(summary.gpa, isNull);
    expect(summary.hasResult, isFalse);
    expect(summary.includedCredits, 0);
    expect(summary.includedCount, 0);
    expect(summary.excludedCount, 3);
    expect(summary.unknownCreditCount, 1);
  });

  test('rejects negative or non-finite credit weights', () {
    expect(
      () => GpaCalculator.calculate([
        GpaContribution(
          calculation: _calculation(gradePoint: 4),
          courseCredits: -1,
        ),
      ]),
      throwsArgumentError,
    );
  });

  test('rejects negative or non-finite custom GPA weights', () {
    expect(
      () => GpaCalculator.calculate([
        GpaContribution(
          calculation: _calculation(gradePoint: 4),
          courseCredits: 2,
          weight: -0.5,
        ),
      ]),
      throwsArgumentError,
    );
    expect(
      () => GpaCalculator.calculate([
        GpaContribution(
          calculation: _calculation(gradePoint: 4),
          courseCredits: 2,
          weight: double.infinity,
        ),
      ]),
      throwsArgumentError,
    );
  });
}
