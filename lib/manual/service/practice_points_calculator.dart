import '../model/practice_record.dart';

/// The approved practice points shown by the manual-entry summary.
final class PracticePointsSummary {
  const PracticePointsSummary({
    required this.total,
    required this.includedCount,
    required this.excludedCount,
  });

  final double total;
  final int includedCount;
  final int excludedCount;
}

final class PracticePointsCalculator {
  const PracticePointsCalculator._();

  static PracticePointsSummary calculate(Iterable<PracticeRecord> records) {
    var total = 0.0;
    var includedCount = 0;
    var excludedCount = 0;
    for (final record in records) {
      final valid = record.category.trim().isNotEmpty &&
          record.points.isFinite &&
          record.points >= 0;
      if (!valid || record.status != PracticeReviewStatus.approved) {
        excludedCount++;
        continue;
      }
      total += record.points;
      if (!total.isFinite) throw ArgumentError('实践记点合计超出可表示范围');
      includedCount++;
    }
    return PracticePointsSummary(
      total: total,
      includedCount: includedCount,
      excludedCount: excludedCount,
    );
  }
}
