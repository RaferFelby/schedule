import '../data/local_data_error.dart';

/// An additional, one-time meeting that is independent of weekly weeks.
final class SessionExtraOccurrence {
  factory SessionExtraOccurrence({
    required String id,
    required DateTime date,
    required int startSlotOrdinal,
    required int endSlotOrdinal,
  }) {
    if (id.trim().isEmpty || !_isDateOnly(date)) {
      throw const LocalDataValidationError('补课 ID 或日期无效');
    }
    if (startSlotOrdinal < 1 || endSlotOrdinal < startSlotOrdinal) {
      throw const LocalDataValidationError('补课节次范围无效');
    }
    return SessionExtraOccurrence._(
      id: id,
      date: DateTime(date.year, date.month, date.day),
      startSlotOrdinal: startSlotOrdinal,
      endSlotOrdinal: endSlotOrdinal,
    );
  }

  const SessionExtraOccurrence._({
    required this.id,
    required this.date,
    required this.startSlotOrdinal,
    required this.endSlotOrdinal,
  });

  final String id;
  final DateTime date;
  final int startSlotOrdinal;
  final int endSlotOrdinal;

  factory SessionExtraOccurrence.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final date = json['date'];
    final start = json['startSlotOrdinal'];
    final end = json['endSlotOrdinal'];
    if (id is! String || date is! String || start is! int || end is! int) {
      throw const LocalDataValidationError('补课数据格式无效');
    }
    final parsedDate = DateTime.tryParse(date);
    if (parsedDate == null || _dateKey(parsedDate) != date) {
      throw const LocalDataValidationError('补课日期格式无效');
    }
    return SessionExtraOccurrence(
      id: id,
      date: parsedDate,
      startSlotOrdinal: start,
      endSlotOrdinal: end,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': _dateKey(date),
        'startSlotOrdinal': startSlotOrdinal,
        'endSlotOrdinal': endSlotOrdinal,
      };
}

bool _isDateOnly(DateTime value) =>
    value.hour == 0 &&
    value.minute == 0 &&
    value.second == 0 &&
    value.millisecond == 0 &&
    value.microsecond == 0;

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
