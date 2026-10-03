import '../data/local_data_error.dart';

/// A semester with explicit calendar boundaries and week-one configuration.
final class LocalSemester {
  factory LocalSemester({
    required String id,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required DateTime weekOneStart,
    String timeZone = 'Asia/Shanghai',
  }) {
    if (id.trim().isEmpty) {
      throw const LocalDataValidationError('学期 ID 不能为空');
    }
    if (name.trim().isEmpty) {
      throw const LocalDataValidationError('学期名称不能为空');
    }
    if (timeZone.trim().isEmpty) {
      throw const LocalDataValidationError('时区不能为空');
    }
    _requireCalendarDate(startDate, '学期开始日期');
    _requireCalendarDate(endDate, '学期结束日期');
    _requireCalendarDate(weekOneStart, '第一周起点');
    if (_calendarDay(endDate) < _calendarDay(startDate)) {
      throw const LocalDataValidationError('学期结束日期不能早于开始日期');
    }
    if (weekOneStart.weekday != DateTime.monday) {
      throw const LocalDataValidationError('第一周起点必须是星期一');
    }

    return LocalSemester._(
      id: id,
      name: name,
      startDate: _dateOnly(startDate),
      endDate: _dateOnly(endDate),
      weekOneStart: _dateOnly(weekOneStart),
      timeZone: timeZone,
    );
  }

  const LocalSemester._({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.weekOneStart,
    required this.timeZone,
  });

  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime weekOneStart;
  final String timeZone;

  factory LocalSemester.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final timeZone = json['timeZone'];
    if (id is! String || name is! String || timeZone is! String) {
      throw const LocalDataValidationError('学期 ID、名称或时区格式无效');
    }

    return LocalSemester(
      id: id,
      name: name,
      startDate: _parseDate(json['startDate'], '学期开始日期'),
      endDate: _parseDate(json['endDate'], '学期结束日期'),
      weekOneStart: _parseDate(json['weekOneStart'], '第一周起点'),
      timeZone: timeZone,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startDate': _formatDate(startDate),
        'endDate': _formatDate(endDate),
        'weekOneStart': _formatDate(weekOneStart),
        'timeZone': timeZone,
      };

  static DateTime _parseDate(Object? value, String label) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw LocalDataValidationError('$label 格式必须为 YYYY-MM-DD');
    }
    try {
      final parsed = DateTime.parse(value);
      if (_formatDate(parsed) != value) {
        throw const FormatException('Date was normalized');
      }
      return parsed;
    } on FormatException {
      throw LocalDataValidationError('$label 不是有效日期');
    }
  }

  static void _requireCalendarDate(DateTime value, String label) {
    if (value.hour != 0 ||
        value.minute != 0 ||
        value.second != 0 ||
        value.millisecond != 0 ||
        value.microsecond != 0) {
      throw LocalDataValidationError('$label 必须使用日期，不包含时间');
    }
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static int _calendarDay(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day).millisecondsSinceEpoch;

  static String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
