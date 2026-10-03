import 'package:celechron/manual/data/local_data_error.dart';
import 'package:celechron/manual/model/practice_record.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = '60000000-0000-4000-8000-000000000001';

void main() {
  group('PracticeRecord', () {
    test('pending practice with unknown requirement states round-trips', () {
      final record = PracticeRecord(
        id: _id,
        category: '志愿服务',
        projectName: '校园服务示例',
        date: DateTime(2026, 9, 20),
        points: 1.5,
        status: PracticeReviewStatus.pending,
      );

      final restored = PracticeRecord.fromJson(record.toJson());
      expect(restored.status, PracticeReviewStatus.pending);
      expect(restored.points, 1.5);
      expect(restored.date, DateTime(2026, 9, 20));
      expect(restored.artsStatus, RequirementStatus.unknown);
      expect(restored.laborStatus, RequirementStatus.unknown);
      expect(restored.note, isNull);
    });

    test('arts and labor states are independent and distinguish unknown', () {
      final record = PracticeRecord(
        id: _id,
        category: '学术活动',
        projectName: '学术讲座示例',
        date: DateTime(2026, 9, 21),
        points: 0,
        status: PracticeReviewStatus.approved,
        artsStatus: RequirementStatus.notPassed,
        laborStatus: RequirementStatus.passed,
      );

      final restored = PracticeRecord.fromJson(record.toJson());
      expect(restored.artsStatus, RequirementStatus.notPassed);
      expect(restored.laborStatus, RequirementStatus.passed);
      expect(restored.points, 0);
    });

    test('rejects negative points, invalid dates, and blank fields', () {
      expect(
        () => PracticeRecord(
          id: _id,
          category: '志愿服务',
          projectName: '服务示例',
          date: DateTime(2026, 9, 20),
          points: -0.1,
          status: PracticeReviewStatus.pending,
        ),
        throwsA(isA<LocalDataValidationError>()),
      );
      expect(
        () => PracticeRecord.fromJson({
          'id': _id,
          'category': '志愿服务',
          'projectName': '服务示例',
          'date': '2026-02-30',
          'points': 1,
          'status': 'pending',
          'note': null,
          'artsStatus': 'unknown',
          'laborStatus': 'unknown',
        }),
        throwsA(isA<LocalDataValidationError>()),
      );
      expect(
        () => PracticeRecord(
          id: _id,
          category: ' ',
          projectName: '服务示例',
          date: DateTime(2026, 9, 20),
          points: 1,
          status: PracticeReviewStatus.pending,
        ),
        throwsA(isA<LocalDataValidationError>()),
      );
    });
  });
}
