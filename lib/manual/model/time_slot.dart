import '../data/local_data_error.dart';

/// An editable daily teaching period represented with minutes after midnight.
final class TimeSlot {
  factory TimeSlot({
    required String id,
    required int ordinal,
    required int startMinute,
    required int endMinute,
  }) {
    if (id.trim().isEmpty) {
      throw const LocalDataValidationError('节次 ID 不能为空');
    }
    if (ordinal < 1) {
      throw const LocalDataValidationError('节次序号必须大于零');
    }
    if (startMinute < 0 || startMinute >= minutesPerDay) {
      throw const LocalDataValidationError('开始分钟数超出一天范围');
    }
    if (endMinute < 1 || endMinute > minutesPerDay) {
      throw const LocalDataValidationError('结束分钟数超出一天范围');
    }
    if (endMinute <= startMinute) {
      throw const LocalDataValidationError('节次结束时间必须晚于开始时间');
    }

    return TimeSlot._(
      id: id,
      ordinal: ordinal,
      startMinute: startMinute,
      endMinute: endMinute,
    );
  }

  const TimeSlot._({
    required this.id,
    required this.ordinal,
    required this.startMinute,
    required this.endMinute,
  });

  static const minutesPerDay = 24 * 60;

  /// Existing fallback periods, returned as fresh values users can edit.
  static List<TimeSlot> defaultTemplate() => [
        (480, 525),
        (530, 575),
        (600, 645),
        (650, 695),
        (700, 745),
        (805, 850),
        (855, 900),
        (905, 950),
        (975, 1020),
        (1025, 1070),
        (1130, 1175),
        (1180, 1225),
        (1230, 1275),
        (1280, 1325),
        (1330, 1375),
      ]
          .indexed
          .map(
            (entry) => TimeSlot(
              id: 'default-time-slot-${(entry.$1 + 1).toString().padLeft(2, '0')}',
              ordinal: entry.$1 + 1,
              startMinute: entry.$2.$1,
              endMinute: entry.$2.$2,
            ),
          )
          .toList();

  final String id;
  final int ordinal;
  final int startMinute;
  final int endMinute;

  static void validateTemplate(Iterable<TimeSlot> slots) {
    final ids = <String>{};
    final ordinals = <int>{};
    for (final slot in slots) {
      if (!ids.add(slot.id)) {
        throw LocalDataValidationError('节次 ID 重复：${slot.id}');
      }
      if (!ordinals.add(slot.ordinal)) {
        throw LocalDataValidationError('节次序号重复：${slot.ordinal}');
      }
    }
  }

  factory TimeSlot.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final ordinal = json['ordinal'];
    final startMinute = json['startMinute'];
    final endMinute = json['endMinute'];
    if (id is! String ||
        ordinal is! int ||
        startMinute is! int ||
        endMinute is! int) {
      throw const LocalDataValidationError('节次数据格式无效');
    }
    return TimeSlot(
      id: id,
      ordinal: ordinal,
      startMinute: startMinute,
      endMinute: endMinute,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'ordinal': ordinal,
        'startMinute': startMinute,
        'endMinute': endMinute,
      };
}
