import '../data/local_data_error.dart';

/// Moves one occurrence while retaining its original weekly-rule date as ID.
final class SessionReschedule {
  factory SessionReschedule({
    required DateTime originalDate,
    required DateTime targetDate,
    required int startMinute,
    required int endMinute,
  }) {
    if (!_isDateOnly(originalDate) || !_isDateOnly(targetDate)) {
      throw const LocalDataValidationError('调课日期必须不包含时间');
    }
    if (startMinute < 0 ||
        startMinute >= 24 * 60 ||
        endMinute <= startMinute ||
        endMinute >= 24 * 60) {
      throw const LocalDataValidationError('调课时间范围无效');
    }
    return SessionReschedule._(
      originalDate: _dateOnly(originalDate),
      targetDate: _dateOnly(targetDate),
      startMinute: startMinute,
      endMinute: endMinute,
    );
  }

  const SessionReschedule._({
    required this.originalDate,
    required this.targetDate,
    required this.startMinute,
    required this.endMinute,
  });

  final DateTime originalDate;
  final DateTime targetDate;
  final int startMinute;
  final int endMinute;

  factory SessionReschedule.fromJson(Map<String, dynamic> json) {
    final original = json['originalDate'];
    final target = json['targetDate'];
    final start = json['startMinute'];
    final end = json['endMinute'];
    if (original is! String ||
        target is! String ||
        start is! int ||
        end is! int) {
      throw const LocalDataValidationError('调课例外数据格式无效');
    }
    return SessionReschedule(
      originalDate: _parseDate(original),
      targetDate: _parseDate(target),
      startMinute: start,
      endMinute: end,
    );
  }

  Map<String, dynamic> toJson() => {
        'originalDate': _dateKey(originalDate),
        'targetDate': _dateKey(targetDate),
        'startMinute': startMinute,
        'endMinute': endMinute,
      };
}

DateTime _parseDate(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !_isDateOnly(parsed) || _dateKey(parsed) != value) {
    throw const LocalDataValidationError('调课日期格式无效');
  }
  return parsed;
}

bool _isDateOnly(DateTime value) =>
    value.hour == 0 &&
    value.minute == 0 &&
    value.second == 0 &&
    value.millisecond == 0 &&
    value.microsecond == 0;

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
