import 'package:celechron/manual/data/local_data_error.dart';
import 'package:celechron/manual/model/grade_record.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = '10000000-0000-4000-8000-000000000001';
const _courseId = '20000000-0000-4000-8000-000000000001';

void main() {
  group('GradeRecord', () {
    test('recorded zero differs from a not-recorded grade', () {
      final zero = GradeRecord(
        id: _id,
        courseId: _courseId,
        status: LocalGradeStatus.recorded,
        method: LocalGradingMethod.percentage,
        rawScore: 0,
      );
      final missing = GradeRecord(
        id: '10000000-0000-4000-8000-000000000002',
        courseId: _courseId,
        status: LocalGradeStatus.notRecorded,
        method: LocalGradingMethod.percentage,
      );

      final restoredZero = GradeRecord.fromJson(zero.toJson());
      final restoredMissing = GradeRecord.fromJson(missing.toJson());
      expect(restoredZero.status, LocalGradeStatus.recorded);
      expect(restoredZero.rawScore, 0);
      expect(restoredMissing.status, LocalGradeStatus.notRecorded);
      expect(restoredMissing.rawScore, isNull);
    });

    test('preserves fractional scores and explicit calculation flags', () {
      final record = GradeRecord(
        id: _id,
        courseId: _courseId,
        status: LocalGradeStatus.recorded,
        method: LocalGradingMethod.percentage,
        rawScore: 89.5,
        calculationRuleId: 'percentage-policy-v1',
        isMajor: true,
        countsTowardGpa: false,
        countsTowardCredits: true,
      );

      final restored = GradeRecord.fromJson(record.toJson());
      expect(restored.rawScore, 89.5);
      expect(restored.calculationRuleId, 'percentage-policy-v1');
      expect(restored.isMajor, isTrue);
      expect(restored.countsTowardGpa, isFalse);
      expect(restored.countsTowardCredits, isTrue);
    });

    test('round-trips labels and direct GPA without deriving a rule', () {
      final record = GradeRecord(
        id: _id,
        courseId: _courseId,
        status: LocalGradeStatus.recorded,
        method: LocalGradingMethod.letter,
        gradeLabel: 'A-',
        gradePoint: 3.7,
      );
      final direct = GradeRecord(
        id: '10000000-0000-4000-8000-000000000002',
        courseId: _courseId,
        status: LocalGradeStatus.recorded,
        method: LocalGradingMethod.directGpa,
        gradePoint: 0,
      );

      expect(GradeRecord.fromJson(record.toJson()).gradeLabel, 'A-');
      expect(GradeRecord.fromJson(direct.toJson()).gradePoint, 0);
      expect(record.calculationRuleId, isNull);
    });

    test('rejects invalid values and incompatible field combinations', () {
      expect(
        () => GradeRecord(
          id: _id,
          courseId: _courseId,
          status: LocalGradeStatus.recorded,
          method: LocalGradingMethod.percentage,
          rawScore: 100.1,
        ),
        throwsA(isA<LocalDataValidationError>()),
      );
      expect(
        () => GradeRecord(
          id: _id,
          courseId: _courseId,
          status: LocalGradeStatus.notRecorded,
          method: LocalGradingMethod.percentage,
          rawScore: 0,
        ),
        throwsA(isA<LocalDataValidationError>()),
      );
      expect(
        () => GradeRecord.fromJson({'id': _id}),
        throwsA(isA<LocalDataValidationError>()),
      );
    });
  });
}
