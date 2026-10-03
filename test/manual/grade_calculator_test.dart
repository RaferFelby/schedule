import 'package:celechron/manual/model/grade_record.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/service/grade_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

const _courseId = '20000000-0000-4000-8000-000000000001';

LocalCourse _course({double? credits = 3}) => LocalCourse(
      id: _courseId,
      semesterId: '10000000-0000-4000-8000-000000000001',
      name: '算法',
      credits: credits,
    );

GradeRecord _record({
  LocalGradeStatus status = LocalGradeStatus.recorded,
  LocalGradingMethod method = LocalGradingMethod.percentage,
  double? rawScore,
  String? gradeLabel,
  double? gradePoint,
  bool countsTowardGpa = true,
  bool countsTowardCredits = true,
}) =>
    GradeRecord(
      id: '30000000-0000-4000-8000-000000000001',
      courseId: _courseId,
      status: status,
      method: method,
      rawScore: rawScore,
      gradeLabel: gradeLabel,
      gradePoint: gradePoint,
      calculationRuleId: null,
      countsTowardGpa: countsTowardGpa,
      countsTowardCredits: countsTowardCredits,
    );

void main() {
  test('zero percentage is recorded but has no GPA or earned credits', () {
    final result = GradeCalculator.calculate(
      record: _record(rawScore: 0),
      course: _course(),
    );

    expect(result.gradePoint, isNull);
    expect(result.includedInGpa, isFalse);
    expect(result.earnedCredits, 0);
  });

  test('89.5 keeps the raw score without inventing GPA or pass status', () {
    final result = GradeCalculator.calculate(
      record: _record(rawScore: 89.5),
      course: _course(),
    );

    expect(_record(rawScore: 89.5).rawScore, 89.5);
    expect(result.gradePoint, isNull);
    expect(result.includedInGpa, isFalse);
    expect(result.earnedCredits, isNull);
  });

  test('pass/fail labels determine credit without default GPA conversion', () {
    final passed = GradeCalculator.calculate(
      record: _record(
        method: LocalGradingMethod.passFail,
        gradeLabel: '合格',
      ),
      course: _course(),
    );
    final failed = GradeCalculator.calculate(
      record: _record(
        method: LocalGradingMethod.passFail,
        gradeLabel: '不合格',
      ),
      course: _course(),
    );

    expect(passed.earnedCredits, 3);
    expect(passed.includedInGpa, isFalse);
    expect(failed.earnedCredits, 0);
  });

  test('not recorded grade keeps earned credits unknown', () {
    final result = GradeCalculator.calculate(
      record: _record(status: LocalGradeStatus.notRecorded),
      course: _course(),
    );

    expect(result.gradePoint, isNull);
    expect(result.includedInGpa, isFalse);
    expect(result.earnedCredits, isNull);
  });

  test('direct and explicitly converted GPA can participate', () {
    final direct = GradeCalculator.calculate(
      record: _record(
        method: LocalGradingMethod.directGpa,
        gradePoint: 4,
      ),
      course: _course(),
    );
    final converted = GradeCalculator.calculate(
      record: _record(rawScore: 89.5),
      course: _course(),
      resolvedGradePoint: 3.7,
      explicitlyPassed: true,
    );

    expect(direct.gradePoint, 4);
    expect(direct.includedInGpa, isTrue);
    expect(direct.earnedCredits, 3);
    expect(converted.gradePoint, 3.7);
    expect(converted.includedInGpa, isTrue);
    expect(converted.earnedCredits, 3);
  });

  test('respects GPA and credit inclusion flags', () {
    final result = GradeCalculator.calculate(
      record: _record(
        method: LocalGradingMethod.directGpa,
        gradePoint: 4,
        countsTowardGpa: false,
        countsTowardCredits: false,
      ),
      course: _course(),
    );

    expect(result.gradePoint, 4);
    expect(result.includedInGpa, isFalse);
    expect(result.earnedCredits, 0);
  });
}
