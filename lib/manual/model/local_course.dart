import '../data/local_data_error.dart';
import 'retake_selection_strategy.dart';

/// A course offering that belongs to one explicitly identified semester.
final class LocalCourse {
  factory LocalCourse({
    required String id,
    required String semesterId,
    required String name,
    String? courseNumber,
    double? credits,
    String? teacher,
    bool isMajor = false,
    bool selectedForGpa = true,
    double gpaWeight = 1,
    String? retakeGroupId,
    RetakeSelectionStrategy retakeStrategy = RetakeSelectionStrategy.highestGpa,
  }) {
    _requireUuid(id, '课程 ID');
    _requireUuid(semesterId, '学期 ID');
    if (retakeGroupId != null) _requireUuid(retakeGroupId, '重修组 ID');
    if (name.trim().isEmpty) {
      throw const LocalDataValidationError('课程名称不能为空');
    }
    if (courseNumber != null && courseNumber.trim().isEmpty) {
      throw const LocalDataValidationError('课程号为空时应保持未填写');
    }
    if (teacher != null && teacher.trim().isEmpty) {
      throw const LocalDataValidationError('教师为空时应保持未填写');
    }
    if (credits != null && (!credits.isFinite || credits < 0)) {
      throw const LocalDataValidationError('课程学分必须是非负有限数值');
    }
    if (!gpaWeight.isFinite || gpaWeight < 0) {
      throw const LocalDataValidationError('GPA 权重必须是非负有限数值');
    }

    return LocalCourse._(
      id: id,
      semesterId: semesterId,
      name: name,
      courseNumber: courseNumber,
      credits: credits,
      teacher: teacher,
      isMajor: isMajor,
      selectedForGpa: selectedForGpa,
      gpaWeight: gpaWeight,
      retakeGroupId: retakeGroupId,
      retakeStrategy: retakeStrategy,
    );
  }

  const LocalCourse._({
    required this.id,
    required this.semesterId,
    required this.name,
    required this.courseNumber,
    required this.credits,
    required this.teacher,
    required this.isMajor,
    required this.selectedForGpa,
    required this.gpaWeight,
    required this.retakeGroupId,
    required this.retakeStrategy,
  });

  final String id;
  final String semesterId;
  final String name;
  final String? courseNumber;
  final double? credits;
  final String? teacher;
  final bool isMajor;
  final bool selectedForGpa;
  final double gpaWeight;
  final String? retakeGroupId;
  final RetakeSelectionStrategy retakeStrategy;

  factory LocalCourse.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final semesterId = json['semesterId'];
    final name = json['name'];
    final courseNumber = json['courseNumber'];
    final rawCredits = json['credits'];
    final teacher = json['teacher'];
    final isMajor = json['isMajor'];
    final selectedForGpa = json['selectedForGpa'];
    final gpaWeight = json['gpaWeight'];
    final retakeGroupId = json['retakeGroupId'];
    final retakeStrategyName = json['retakeStrategy'];
    if (id is! String ||
        semesterId is! String ||
        name is! String ||
        (courseNumber != null && courseNumber is! String) ||
        (rawCredits != null && rawCredits is! num) ||
        (teacher != null && teacher is! String) ||
        (isMajor is! bool) ||
        (selectedForGpa != null && selectedForGpa is! bool) ||
        (gpaWeight != null && gpaWeight is! num) ||
        (retakeGroupId != null && retakeGroupId is! String) ||
        (retakeStrategyName != null && retakeStrategyName is! String)) {
      throw const LocalDataValidationError('课程数据格式无效');
    }
    final retakeStrategy = switch (retakeStrategyName) {
      null || 'highestGpa' => RetakeSelectionStrategy.highestGpa,
      'firstAttempt' => RetakeSelectionStrategy.firstAttempt,
      _ => throw const LocalDataValidationError('重修成绩选择策略无效'),
    };

    return LocalCourse(
      id: id,
      semesterId: semesterId,
      name: name,
      courseNumber: courseNumber as String?,
      credits: (rawCredits as num?)?.toDouble(),
      teacher: teacher as String?,
      isMajor: isMajor,
      selectedForGpa: selectedForGpa as bool? ?? true,
      gpaWeight: (gpaWeight as num?)?.toDouble() ?? 1,
      retakeGroupId: retakeGroupId as String?,
      retakeStrategy: retakeStrategy,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'semesterId': semesterId,
        'name': name,
        'courseNumber': courseNumber,
        'credits': credits,
        'teacher': teacher,
        'isMajor': isMajor,
        'selectedForGpa': selectedForGpa,
        'gpaWeight': gpaWeight,
        'retakeGroupId': retakeGroupId,
        'retakeStrategy': retakeStrategy.name,
      };

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
