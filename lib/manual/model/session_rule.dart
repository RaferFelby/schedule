import '../data/local_data_error.dart';
import 'session_reschedule.dart';
import 'session_extra_occurrence.dart';

/// A weekly course rule; it does not expand into calendar dates.
final class SessionRule {
  factory SessionRule({
    required String id,
    required String courseId,
    required int weekday,
    required List<int> weekNumbers,
    required int startSlotOrdinal,
    required int endSlotOrdinal,
    String? location,
    String? teacher,
    List<DateTime> cancelledDates = const [],
    List<SessionReschedule> reschedules = const [],
    List<SessionExtraOccurrence> extraOccurrences = const [],
  }) {
    if (id.trim().isEmpty || courseId.trim().isEmpty) {
      throw const LocalDataValidationError('上课规则 ID 和课程 ID 不能为空');
    }
    if (weekday < DateTime.monday || weekday > DateTime.sunday) {
      throw const LocalDataValidationError('星期必须在 1 至 7 之间');
    }
    if (weekNumbers.isEmpty) {
      throw const LocalDataValidationError('上课周次不能为空');
    }
    if (weekNumbers.any((week) => week < 1)) {
      throw const LocalDataValidationError('上课周次必须是正整数');
    }
    if (weekNumbers.toSet().length != weekNumbers.length) {
      throw const LocalDataValidationError('上课周次不能重复');
    }
    if (startSlotOrdinal < 1 || endSlotOrdinal < startSlotOrdinal) {
      throw const LocalDataValidationError('节次范围无效');
    }
    if (location != null && location.trim().isEmpty) {
      throw const LocalDataValidationError('地点为空时应保持未填写');
    }
    if (teacher != null && teacher.trim().isEmpty) {
      throw const LocalDataValidationError('教师为空时应保持未填写');
    }
    final normalizedDates = cancelledDates.map(_dateOnly).toList();
    if (cancelledDates.any((date) => !_isDateOnly(date)) ||
        normalizedDates.map(_dateKey).toSet().length !=
            normalizedDates.length) {
      throw const LocalDataValidationError('停课日期必须是唯一的有效日期');
    }

    final rescheduleKeys =
        reschedules.map((item) => _dateKey(item.originalDate)).toList();
    if (rescheduleKeys.toSet().length != rescheduleKeys.length ||
        normalizedDates.any(rescheduleKeys.toSet().contains)) {
      throw const LocalDataValidationError(
        '调课例外日期不能重复或与停课日期冲突',
      );
    }

    if (extraOccurrences.map((item) => item.id).toSet().length !=
        extraOccurrences.length) {
      throw const LocalDataValidationError('补课 ID 不能重复');
    }

    return SessionRule._(
      id: id,
      courseId: courseId,
      weekday: weekday,
      weekNumbers: List.unmodifiable(weekNumbers),
      startSlotOrdinal: startSlotOrdinal,
      endSlotOrdinal: endSlotOrdinal,
      location: location,
      teacher: teacher,
      cancelledDates: List.unmodifiable(normalizedDates),
      reschedules: List.unmodifiable(reschedules),
      extraOccurrences: List.unmodifiable(extraOccurrences),
    );
  }

  const SessionRule._({
    required this.id,
    required this.courseId,
    required this.weekday,
    required this.weekNumbers,
    required this.startSlotOrdinal,
    required this.endSlotOrdinal,
    required this.location,
    required this.teacher,
    required this.cancelledDates,
    required this.reschedules,
    required this.extraOccurrences,
  });

  final String id;
  final String courseId;
  final int weekday;
  final List<int> weekNumbers;
  final int startSlotOrdinal;
  final int endSlotOrdinal;
  final String? location;
  final String? teacher;
  final List<DateTime> cancelledDates;
  final List<SessionReschedule> reschedules;
  final List<SessionExtraOccurrence> extraOccurrences;

  factory SessionRule.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final courseId = json['courseId'];
    final weekday = json['weekday'];
    final weekNumbers = json['weekNumbers'];
    final startSlotOrdinal = json['startSlotOrdinal'];
    final endSlotOrdinal = json['endSlotOrdinal'];
    final location = json['location'];
    final teacher = json['teacher'];
    final cancelledDates = json['cancelledDates'] ?? const <dynamic>[];
    final reschedules = json['reschedules'] ?? const <dynamic>[];
    final extraOccurrences = json['extraOccurrences'] ?? const <dynamic>[];
    if (id is! String ||
        courseId is! String ||
        weekday is! int ||
        weekNumbers is! List ||
        weekNumbers.any((week) => week is! int) ||
        startSlotOrdinal is! int ||
        endSlotOrdinal is! int ||
        (location != null && location is! String) ||
        (teacher != null && teacher is! String) ||
        cancelledDates is! List ||
        cancelledDates.any((date) => date is! String) ||
        reschedules is! List ||
        reschedules.any((item) => item is! Map) ||
        extraOccurrences is! List ||
        extraOccurrences.any((item) => item is! Map)) {
      throw const LocalDataValidationError('上课规则数据格式无效');
    }

    return SessionRule(
      id: id,
      courseId: courseId,
      weekday: weekday,
      weekNumbers: weekNumbers.cast<int>(),
      startSlotOrdinal: startSlotOrdinal,
      endSlotOrdinal: endSlotOrdinal,
      location: location as String?,
      teacher: teacher as String?,
      cancelledDates: cancelledDates.cast<String>().map(_parseDate).toList(),
      reschedules: reschedules
          .map((item) => SessionReschedule.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(),
      extraOccurrences: extraOccurrences
          .map((item) => SessionExtraOccurrence.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'weekday': weekday,
        'weekNumbers': List<int>.of(weekNumbers),
        'startSlotOrdinal': startSlotOrdinal,
        'endSlotOrdinal': endSlotOrdinal,
        'location': location,
        'teacher': teacher,
        'cancelledDates': cancelledDates.map(_dateKey).toList(),
        'reschedules': reschedules.map((item) => item.toJson()).toList(),
        'extraOccurrences':
            extraOccurrences.map((item) => item.toJson()).toList(),
      };
}

DateTime _parseDate(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null || _dateKey(parsed) != value || !_isDateOnly(parsed)) {
    throw const LocalDataValidationError('停课日期格式无效');
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
