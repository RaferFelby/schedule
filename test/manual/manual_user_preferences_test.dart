import 'package:celechron/manual/model/manual_user_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imports legacy theme, durations and sorted daily time windows', () {
    final value = ManualUserPreferences.fromLegacy({
      'brightnessMode': 2,
      'workTime': const Duration(minutes: 50),
      'restTime': const Duration(minutes: 10),
      'allowTime': {
        DateTime(0, 1, 1, 14, 15): DateTime(0, 1, 1, 23),
        DateTime(0, 1, 1, 8): DateTime(0, 1, 1, 11, 35),
      },
      'asyncRefresh': true,
    });

    expect(value.toJson(), {
      'theme': 'dark',
      'workMinutes': 50,
      'restMinutes': 10,
      'availableWindows': [
        {'startMinutes': 480, 'endMinutes': 695},
        {'startMinutes': 855, 'endMinutes': 1380},
      ],
    });
  });

  test('uses manual defaults for invalid legacy preference values', () {
    final value = ManualUserPreferences.fromLegacy({
      'brightnessMode': 99,
      'workTime': 'invalid',
      'restTime': const Duration(seconds: 30),
      'allowTime': {'invalid': 'input'},
    });
    expect(value.toJson(), const ManualUserPreferences().toJson());
  });

  test('rejects overlapping or malformed restored windows', () {
    expect(
      () => ManualUserPreferences.fromJson({
        'theme': 'system',
        'workMinutes': 25,
        'restMinutes': 5,
        'availableWindows': [
          {'startMinutes': 480, 'endMinutes': 600},
          {'startMinutes': 590, 'endMinutes': 700},
        ],
      }),
      throwsFormatException,
    );
  });
}
