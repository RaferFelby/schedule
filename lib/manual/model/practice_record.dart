import '../data/local_data_error.dart';

enum PracticeReviewStatus { pending, approved, rejected }

enum RequirementStatus { unknown, notPassed, passed }

/// A user-maintained practice item, separate from requirement completion.
final class PracticeRecord {
  factory PracticeRecord({
    required String id,
    required String category,
    required String projectName,
    required DateTime date,
    required double points,
    required PracticeReviewStatus status,
    String? note,
    RequirementStatus artsStatus = RequirementStatus.unknown,
    RequirementStatus laborStatus = RequirementStatus.unknown,
  }) {
    _requireUuid(id);
    if (category.trim().isEmpty || projectName.trim().isEmpty) {
      throw const LocalDataValidationError('实践类别和项目名称不能为空');
    }
    if (!_isCalendarDate(date)) {
      throw const LocalDataValidationError('实践日期必须是有效的日历日期');
    }
    if (!points.isFinite || points < 0) {
      throw const LocalDataValidationError('实践记点必须是非负有限数值');
    }
    if (note != null && note.trim().isEmpty) {
      throw const LocalDataValidationError('备注为空时应保持未填写');
    }

    return PracticeRecord._(
      id: id,
      category: category,
      projectName: projectName,
      date: date,
      points: points,
      status: status,
      note: note,
      artsStatus: artsStatus,
      laborStatus: laborStatus,
    );
  }

  const PracticeRecord._({
    required this.id,
    required this.category,
    required this.projectName,
    required this.date,
    required this.points,
    required this.status,
    required this.note,
    required this.artsStatus,
    required this.laborStatus,
  });

  final String id;
  final String category;
  final String projectName;
  final DateTime date;
  final double points;
  final PracticeReviewStatus status;
  final String? note;
  final RequirementStatus artsStatus;
  final RequirementStatus laborStatus;

  factory PracticeRecord.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final category = json['category'];
    final projectName = json['projectName'];
    final rawDate = json['date'];
    final points = json['points'];
    final status = _enumValue(PracticeReviewStatus.values, json['status']);
    final note = json['note'];
    final artsStatus = _enumValue(RequirementStatus.values, json['artsStatus']);
    final laborStatus =
        _enumValue(RequirementStatus.values, json['laborStatus']);
    if (id is! String ||
        category is! String ||
        projectName is! String ||
        rawDate is! String ||
        points is! num ||
        status == null ||
        (note != null && note is! String) ||
        artsStatus == null ||
        laborStatus == null) {
      throw const LocalDataValidationError('实践记录数据格式无效');
    }

    return PracticeRecord(
      id: id,
      category: category,
      projectName: projectName,
      date: _parseDate(rawDate),
      points: points.toDouble(),
      status: status,
      note: note as String?,
      artsStatus: artsStatus,
      laborStatus: laborStatus,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'projectName': projectName,
        'date': _formatDate(date),
        'points': points,
        'status': status.name,
        'note': note,
        'artsStatus': artsStatus.name,
        'laborStatus': laborStatus.name,
      };

  static T? _enumValue<T extends Enum>(List<T> values, Object? name) {
    if (name is! String) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static DateTime _parseDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) {
      throw const LocalDataValidationError('实践日期格式必须为 YYYY-MM-DD');
    }
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      throw const LocalDataValidationError('实践日期不是有效日历日期');
    }
    return date;
  }

  static String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static bool _isCalendarDate(DateTime date) =>
      date.hour == 0 &&
      date.minute == 0 &&
      date.second == 0 &&
      date.millisecond == 0 &&
      date.microsecond == 0;

  static void _requireUuid(String value) {
    if (!_uuidPattern.hasMatch(value)) {
      throw const LocalDataValidationError('实践记录 ID 必须是 UUID');
    }
  }

  static final _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
}
