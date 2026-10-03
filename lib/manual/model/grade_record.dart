import '../data/local_data_error.dart';

enum LocalGradeStatus { notRecorded, recorded }

enum LocalGradingMethod { percentage, letter, passFail, directGpa }

/// A raw course grade and its explicit calculation metadata.
final class GradeRecord {
  factory GradeRecord({
    required String id,
    required String courseId,
    required LocalGradeStatus status,
    required LocalGradingMethod method,
    double? rawScore,
    String? gradeLabel,
    double? gradePoint,
    String? calculationRuleId,
    bool isMajor = false,
    bool countsTowardGpa = true,
    bool countsTowardCredits = true,
  }) {
    _requireUuid(id, '成绩记录 ID');
    _requireUuid(courseId, '课程 ID');
    if (calculationRuleId != null && calculationRuleId.trim().isEmpty) {
      throw const LocalDataValidationError('计算规则 ID 为空时应保持未填写');
    }
    if (gradePoint != null && (!gradePoint.isFinite || gradePoint < 0)) {
      throw const LocalDataValidationError('绩点必须是非负有限数值');
    }

    if (status == LocalGradeStatus.notRecorded) {
      if (rawScore != null || gradeLabel != null || gradePoint != null) {
        throw const LocalDataValidationError('未录入成绩不能包含成绩数值或等级');
      }
    } else {
      switch (method) {
        case LocalGradingMethod.percentage:
          if (rawScore == null ||
              !rawScore.isFinite ||
              rawScore < 0 ||
              rawScore > 100 ||
              gradeLabel != null) {
            throw const LocalDataValidationError('百分制成绩须为 0 到 100 的数值');
          }
        case LocalGradingMethod.letter:
        case LocalGradingMethod.passFail:
          if (gradeLabel == null ||
              gradeLabel.trim().isEmpty ||
              rawScore != null) {
            throw const LocalDataValidationError('等级/通过制成绩须填写等级文本');
          }
        case LocalGradingMethod.directGpa:
          if (gradePoint == null || rawScore != null || gradeLabel != null) {
            throw const LocalDataValidationError('直接绩点方式须填写绩点且不能包含原始成绩');
          }
      }
    }

    return GradeRecord._(
      id: id,
      courseId: courseId,
      status: status,
      method: method,
      rawScore: rawScore,
      gradeLabel: gradeLabel,
      gradePoint: gradePoint,
      calculationRuleId: calculationRuleId,
      isMajor: isMajor,
      countsTowardGpa: countsTowardGpa,
      countsTowardCredits: countsTowardCredits,
    );
  }

  const GradeRecord._({
    required this.id,
    required this.courseId,
    required this.status,
    required this.method,
    required this.rawScore,
    required this.gradeLabel,
    required this.gradePoint,
    required this.calculationRuleId,
    required this.isMajor,
    required this.countsTowardGpa,
    required this.countsTowardCredits,
  });

  final String id;
  final String courseId;
  final LocalGradeStatus status;
  final LocalGradingMethod method;
  final double? rawScore;
  final String? gradeLabel;
  final double? gradePoint;
  final String? calculationRuleId;
  final bool isMajor;
  final bool countsTowardGpa;
  final bool countsTowardCredits;

  factory GradeRecord.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final courseId = json['courseId'];
    final status = _enumValue(LocalGradeStatus.values, json['status']);
    final method = _enumValue(LocalGradingMethod.values, json['method']);
    final rawScore = json['rawScore'];
    final gradeLabel = json['gradeLabel'];
    final gradePoint = json['gradePoint'];
    final calculationRuleId = json['calculationRuleId'];
    final isMajor = json['isMajor'];
    final countsTowardGpa = json['countsTowardGpa'];
    final countsTowardCredits = json['countsTowardCredits'];
    if (id is! String ||
        courseId is! String ||
        status == null ||
        method == null ||
        (rawScore != null && rawScore is! num) ||
        (gradeLabel != null && gradeLabel is! String) ||
        (gradePoint != null && gradePoint is! num) ||
        (calculationRuleId != null && calculationRuleId is! String) ||
        isMajor is! bool ||
        countsTowardGpa is! bool ||
        countsTowardCredits is! bool) {
      throw const LocalDataValidationError('成绩记录数据格式无效');
    }
    return GradeRecord(
      id: id,
      courseId: courseId,
      status: status,
      method: method,
      rawScore: (rawScore as num?)?.toDouble(),
      gradeLabel: gradeLabel as String?,
      gradePoint: (gradePoint as num?)?.toDouble(),
      calculationRuleId: calculationRuleId as String?,
      isMajor: isMajor,
      countsTowardGpa: countsTowardGpa,
      countsTowardCredits: countsTowardCredits,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'status': status.name,
        'method': method.name,
        'rawScore': rawScore,
        'gradeLabel': gradeLabel,
        'gradePoint': gradePoint,
        'calculationRuleId': calculationRuleId,
        'isMajor': isMajor,
        'countsTowardGpa': countsTowardGpa,
        'countsTowardCredits': countsTowardCredits,
      };

  static T? _enumValue<T extends Enum>(List<T> values, Object? name) {
    if (name is! String) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static void _requireUuid(String value, String label) {
    if (!_uuidPattern.hasMatch(value)) {
      throw LocalDataValidationError('$label 必须是 UUID');
    }
  }

  static final _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
}
