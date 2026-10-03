import 'package:celechron/manual/data/local_data_error.dart';
import 'package:celechron/manual/model/time_slot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimeSlot', () {
    test('08:00–08:45 is valid and round-trips through JSON', () {
      final slot = TimeSlot(
        id: 'slot-1',
        ordinal: 1,
        startMinute: 8 * 60,
        endMinute: 8 * 60 + 45,
      );

      final restored = TimeSlot.fromJson(slot.toJson());
      expect(restored.id, 'slot-1');
      expect(restored.ordinal, 1);
      expect(restored.startMinute, 480);
      expect(restored.endMinute, 525);
    });

    test('rejects reversed and out-of-range times', () {
      expect(
        () => TimeSlot(
          id: 'slot-1',
          ordinal: 1,
          startMinute: 600,
          endMinute: 599,
        ),
        throwsA(isA<LocalDataValidationError>()),
      );
      expect(
        () => TimeSlot(
          id: 'slot-1',
          ordinal: 1,
          startMinute: 1440,
          endMinute: 1441,
        ),
        throwsA(isA<LocalDataValidationError>()),
      );
    });

    test('rejects duplicate ordinals in a template', () {
      final slots = [
        TimeSlot(id: 'slot-a', ordinal: 1, startMinute: 480, endMinute: 525),
        TimeSlot(id: 'slot-b', ordinal: 1, startMinute: 530, endMinute: 575),
      ];

      expect(
        () => TimeSlot.validateTemplate(slots),
        throwsA(isA<LocalDataValidationError>()),
      );
    });

    test('default template returns editable independent values', () {
      final firstCopy = TimeSlot.defaultTemplate();
      final secondCopy = TimeSlot.defaultTemplate();
      expect(firstCopy, hasLength(15));
      expect(firstCopy.first.startMinute, 480);
      expect(firstCopy.first.endMinute, 525);

      firstCopy[0] = TimeSlot(
        id: 'custom-slot',
        ordinal: 1,
        startMinute: 500,
        endMinute: 545,
      );

      expect(secondCopy.first.startMinute, 480);
      expect(secondCopy.first.endMinute, 525);
    });
  });
}
