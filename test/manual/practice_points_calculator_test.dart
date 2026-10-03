import 'package:celechron/manual/model/practice_record.dart';
import 'package:celechron/manual/service/practice_points_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

PracticeRecord _record({
  required String id,
  required double points,
  required PracticeReviewStatus status,
}) =>
    PracticeRecord(
      id: id,
      category: '志愿服务',
      projectName: '项目$id',
      date: DateTime(2026, 9, 10),
      points: points,
      status: status,
    );

void main() {
  test('counts approved valid records only', () {
    final summary = PracticePointsCalculator.calculate([
      _record(
        id: '60000000-0000-4000-8000-000000000001',
        points: 1.5,
        status: PracticeReviewStatus.approved,
      ),
      _record(
        id: '60000000-0000-4000-8000-000000000002',
        points: 2,
        status: PracticeReviewStatus.pending,
      ),
      _record(
        id: '60000000-0000-4000-8000-000000000003',
        points: 4,
        status: PracticeReviewStatus.rejected,
      ),
    ]);

    expect(summary.total, 1.5);
    expect(summary.includedCount, 1);
    expect(summary.excludedCount, 2);
  });

  test('returns zero for no practice records', () {
    final summary = PracticePointsCalculator.calculate(const []);
    expect(summary.total, 0);
    expect(summary.includedCount, 0);
  });
}
