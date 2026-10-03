import '../data/local_data_error.dart';

/// An exam linked to a course; its schedule may remain explicitly unknown.
final class LocalExam {
  factory LocalExam({
    required String id,
    required String courseId,
    required String type,
    DateTime? start,
    DateTime? end,
    String? location,
    String? seat,
  }) {
    if (id.trim().isEmpty || courseId.trim().isEmpty) {
      throw const LocalDataValidationError('考试 ID 和课程 ID 不能为空');
    }
    if (type.trim().isEmpty) {
      throw const LocalDataValidationError('考试类型不能为空');
    }
    if ((start == null) != (end == null)) {
      throw const LocalDataValidationError('考试开始和结束时间必须同时填写');
    }
    if (start != null && !end!.isAfter(start)) {
      throw const LocalDataValidationError('考试结束时间必须晚于开始时间');
    }
    if (location != null && location.trim().isEmpty) {
      throw const LocalDataValidationError('地点为空时应保持未填写');
    }
    if (seat != null && seat.trim().isEmpty) {
      throw const LocalDataValidationError('座位为空时应保持未填写');
    }

    return LocalExam._(
      id: id,
      courseId: courseId,
      type: type,
      start: start,
      end: end,
      location: location,
      seat: seat,
    );
  }

  const LocalExam._({
    required this.id,
    required this.courseId,
    required this.type,
    required this.start,
    required this.end,
    required this.location,
    required this.seat,
  });

  final String id;
  final String courseId;
  final String type;
  final DateTime? start;
  final DateTime? end;
  final String? location;
  final String? seat;

  factory LocalExam.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final courseId = json['courseId'];
    final type = json['type'];
    final rawStart = json['start'];
    final rawEnd = json['end'];
    final location = json['location'];
    final seat = json['seat'];
    if (id is! String ||
        courseId is! String ||
        type is! String ||
        (rawStart != null && rawStart is! String) ||
        (rawEnd != null && rawEnd is! String) ||
        (location != null && location is! String) ||
        (seat != null && seat is! String)) {
      throw const LocalDataValidationError('考试数据格式无效');
    }

    return LocalExam(
      id: id,
      courseId: courseId,
      type: type,
      start: _parseDateTime(rawStart),
      end: _parseDateTime(rawEnd),
      location: location as String?,
      seat: seat as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'type': type,
        'start': start?.toIso8601String(),
        'end': end?.toIso8601String(),
        'location': location,
        'seat': seat,
      };

  static DateTime? _parseDateTime(Object? value) {
    if (value == null) return null;
    if (value is! String) {
      throw const LocalDataValidationError('考试时间格式无效');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw const LocalDataValidationError('考试时间不是有效日期');
    }
    return parsed;
  }
}
