import 'package:celechron/manual/migration/semester_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const converter = LegacySemesterConverter();

  test('keeps explicitly dated short and empty semesters', () {
    final result = converter.convert({
      'semesters': [
        {
          'name': 'S',
          'startDate': '2026-09-01',
          'endDate': '2027-01-31',
          'weekOneStart': '2026-08-31',
          'courses': <String, Object?>{},
        },
      ],
    });

    expect(result.semesters, hasLength(1));
    expect(result.semesters.single.name, 'S');
    expect(
      result.semesters.single.id,
      matches(RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      )),
    );
    expect(result.semesters.single.startDate, DateTime(2026, 9, 1));
    expect(result.unresolvedSemesters, isEmpty);
  });

  test('preserves empty-course semesters for review without inventing dates',
      () {
    final result = converter.convert({
      'semesters': [
        {'name': '短学期', 'courses': <String, Object?>{}},
      ],
    });

    expect(result.semesters, isEmpty);
    expect(result.unresolvedSemesters.single['name'], '短学期');
    expect(result.unresolvedSemesters.single['courseCount'], 0);
    expect(result.unresolvedSemesters.single['missingFields'],
        ['startDate', 'endDate', 'weekOneStart']);
    expect(result.reviewItems, hasLength(1));
  });

  test('imports explicit legacy time ranges and reports invalid ranges', () {
    final result = converter.convert({
      'semesters': [
        {
          'name': 'S',
          'startDate': '2026-09-01',
          'endDate': '2027-01-31',
          'weekOneStart': '2026-08-31',
          'sessionToTime': [
            <int>[],
            [480, 525],
            [525, 520],
            ['bad', 600],
          ],
        },
      ],
    });

    expect(result.timeSlots, hasLength(1));
    expect(result.timeSlots.single.ordinal, 1);
    expect(result.timeSlots.single.startMinute, 480);
    expect(result.timeSlots.single.endMinute, 525);
    expect(result.reviewItems, hasLength(2));
  });

  test('uses stable unique IDs even for duplicate semester names and data', () {
    const rawSemester = {'name': 'S'};
    final result = converter.convert({
      'semesters': [rawSemester, rawSemester],
    });

    final ids = result.unresolvedSemesters.map((item) => item['id']).toSet();
    expect(ids, hasLength(2));
    final repeated = converter.convert({
      'semesters': [rawSemester]
    });
    expect(repeated.unresolvedSemesters.single['id'],
        result.unresolvedSemesters.first['id']);
  });

  test('rejects malformed explicit dates without deriving them from the name',
      () {
    final result = converter.convert({
      'semesters': [
        {
          'name': '2026-2027秋冬',
          'startDate': '2026-02-30',
          'endDate': '2027-01-31',
          'weekOneStart': '2026-08-31',
        },
      ],
    });

    expect(result.semesters, isEmpty);
    expect(result.unresolvedSemesters.single['missingFields'], ['startDate']);
  });
}
