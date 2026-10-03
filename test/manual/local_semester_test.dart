import 'package:celechron/manual/data/local_data_error.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalSemester', () {
    test('free-form name and explicit dates round-trip through JSON', () {
      final semester = LocalSemester(
        id: 'semester-summer-2026',
        name: '暑期班',
        startDate: DateTime(2026, 7, 8),
        endDate: DateTime(2026, 9, 1),
        weekOneStart: DateTime(2026, 7, 6),
      );

      final restored = LocalSemester.fromJson(semester.toJson());

      expect(restored.id, 'semester-summer-2026');
      expect(restored.name, '暑期班');
      expect(restored.startDate, DateTime(2026, 7, 8));
      expect(restored.endDate, DateTime(2026, 9, 1));
      expect(restored.weekOneStart, DateTime(2026, 7, 6));
      expect(restored.timeZone, 'Asia/Shanghai');
    });

    test('rejects an end date before the start date', () {
      expect(
        () => LocalSemester(
          id: 'semester-1',
          name: '暑期班',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 7, 8),
          weekOneStart: DateTime(2026, 8, 31),
        ),
        throwsA(isA<LocalDataValidationError>()),
      );
    });

    test('requires date-only values and a Monday week-one start', () {
      expect(
        () => LocalSemester(
          id: 'semester-1',
          name: '暑期班',
          startDate: DateTime(2026, 7, 8, 9),
          endDate: DateTime(2026, 9, 1),
          weekOneStart: DateTime(2026, 7, 6),
        ),
        throwsA(isA<LocalDataValidationError>()),
      );
      expect(
        () => LocalSemester(
          id: 'semester-1',
          name: '暑期班',
          startDate: DateTime(2026, 7, 8),
          endDate: DateTime(2026, 9, 1),
          weekOneStart: DateTime(2026, 7, 7),
        ),
        throwsA(isA<LocalDataValidationError>()),
      );
    });

    test('rejects malformed date fields while reading JSON', () {
      expect(
        () => LocalSemester.fromJson({
          'id': 'semester-1',
          'name': '暑期班',
          'startDate': '2026-02-30',
          'endDate': '2026-09-01',
          'weekOneStart': '2026-07-06',
          'timeZone': 'Asia/Shanghai',
        }),
        throwsA(isA<LocalDataValidationError>()),
      );
    });
  });
}
