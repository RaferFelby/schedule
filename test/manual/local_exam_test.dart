import 'package:celechron/manual/data/local_data_error.dart';
import 'package:celechron/manual/model/local_exam.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalExam', () {
    test('an exam with an unknown time round-trips as null', () {
      final exam = LocalExam(
        id: 'exam-1',
        courseId: '20000000-0000-4000-8000-000000000001',
        type: '期末考试',
        location: '教学楼示例教室',
      );

      final restored = LocalExam.fromJson(exam.toJson());
      expect(restored.start, isNull);
      expect(restored.end, isNull);
      expect(restored.location, '教学楼示例教室');
      expect(restored.seat, isNull);
    });

    test('a complete exam time round-trips', () {
      final exam = LocalExam(
        id: 'exam-2',
        courseId: '20000000-0000-4000-8000-000000000001',
        type: '期中考试',
        start: DateTime(2026, 11, 12, 9),
        end: DateTime(2026, 11, 12, 11),
        location: '教学楼',
        seat: 'A01',
      );

      final restored = LocalExam.fromJson(exam.toJson());
      expect(restored.start, DateTime(2026, 11, 12, 9));
      expect(restored.end, DateTime(2026, 11, 12, 11));
      expect(restored.seat, 'A01');
    });

    test('rejects a partial or reversed time range', () {
      expect(
        () => LocalExam(
          id: 'exam-1',
          courseId: '20000000-0000-4000-8000-000000000001',
          type: '期末考试',
          start: DateTime(2026, 11, 12, 9),
        ),
        throwsA(isA<LocalDataValidationError>()),
      );
      expect(
        () => LocalExam(
          id: 'exam-1',
          courseId: '20000000-0000-4000-8000-000000000001',
          type: '期末考试',
          start: DateTime(2026, 11, 12, 11),
          end: DateTime(2026, 11, 12, 9),
        ),
        throwsA(isA<LocalDataValidationError>()),
      );
    });
  });
}
