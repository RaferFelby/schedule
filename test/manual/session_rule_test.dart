import 'package:celechron/manual/data/local_data_error.dart';
import 'package:celechron/manual/model/session_rule.dart';
import 'package:celechron/manual/model/session_extra_occurrence.dart';
import 'package:celechron/manual/model/session_reschedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionRule', () {
    test('explicit week numbers round-trip without reordering', () {
      final rule = SessionRule(
        id: 'rule-1',
        courseId: '20000000-0000-4000-8000-000000000001',
        weekday: DateTime.monday,
        weekNumbers: [1, 3, 5],
        startSlotOrdinal: 1,
        endSlotOrdinal: 2,
        location: '教室 A',
      );

      final withCancellation = SessionRule(
        id: rule.id,
        courseId: rule.courseId,
        weekday: rule.weekday,
        weekNumbers: rule.weekNumbers,
        startSlotOrdinal: rule.startSlotOrdinal,
        endSlotOrdinal: rule.endSlotOrdinal,
        location: rule.location,
        cancelledDates: [DateTime(2026, 9, 22)],
        extraOccurrences: [
          SessionExtraOccurrence(
            id: 'extra-1',
            date: DateTime(2026, 9, 26),
            startSlotOrdinal: 1,
            endSlotOrdinal: 2,
          )
        ],
        reschedules: [
          SessionReschedule(
            originalDate: DateTime(2026, 10, 1),
            targetDate: DateTime(2026, 10, 2),
            startMinute: 540,
            endMinute: 585,
          )
        ],
      );
      final restored = SessionRule.fromJson(withCancellation.toJson());
      expect(restored.weekNumbers, [1, 3, 5]);
      expect(restored.courseId, rule.courseId);
      expect(restored.location, '教室 A');
      expect(restored.teacher, isNull);
      expect(restored.cancelledDates, [DateTime(2026, 9, 22)]);
      expect(restored.extraOccurrences.single.date, DateTime(2026, 9, 26));
      expect(restored.extraOccurrences.single.id, 'extra-1');
      expect(restored.reschedules.single.originalDate, DateTime(2026, 10, 1));
      expect(restored.reschedules.single.targetDate, DateTime(2026, 10, 2));
      expect(SessionRule.fromJson(rule.toJson()).cancelledDates, isEmpty);
      final legacyJson = Map<String, dynamic>.from(rule.toJson())
        ..remove('teacher');
      expect(SessionRule.fromJson(legacyJson).teacher, isNull);
    });

    test('rejects empty/invalid weeks, invalid weekdays, and reversed slots',
        () {
      SessionRule build({
        int weekday = 1,
        List<int> weekNumbers = const [1],
        int startSlotOrdinal = 1,
        int endSlotOrdinal = 1,
      }) =>
          SessionRule(
            id: 'rule-1',
            courseId: '20000000-0000-4000-8000-000000000001',
            weekday: weekday,
            weekNumbers: weekNumbers,
            startSlotOrdinal: startSlotOrdinal,
            endSlotOrdinal: endSlotOrdinal,
          );

      expect(() => build(weekNumbers: []),
          throwsA(isA<LocalDataValidationError>()));
      expect(() => build(weekNumbers: [0, 1]),
          throwsA(isA<LocalDataValidationError>()));
      expect(() => build(weekday: 8), throwsA(isA<LocalDataValidationError>()));
      expect(
        () => build(startSlotOrdinal: 3, endSlotOrdinal: 2),
        throwsA(isA<LocalDataValidationError>()),
      );
    });

    test('week collection is immutable after construction', () {
      final weeks = [1, 3, 5];
      final rule = SessionRule(
        id: 'rule-1',
        courseId: '20000000-0000-4000-8000-000000000001',
        weekday: 1,
        weekNumbers: weeks,
        startSlotOrdinal: 1,
        endSlotOrdinal: 1,
      );
      weeks.add(7);

      expect(rule.weekNumbers, [1, 3, 5]);
      expect(
        () => rule.weekNumbers.add(7),
        throwsUnsupportedError,
      );
    });
  });
}
