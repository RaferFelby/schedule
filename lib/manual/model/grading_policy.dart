import 'grade_record.dart';

/// Describes which grade value a method can provide without conversion.
///
/// GPA is available only when entered directly or derived from an explicit
/// conversion rule. Legacy server-provided mappings are not manual defaults.
final class GradingMethodPolicy {
  /// Label values used only by the legacy imported Grade display model.
  static const importedLabelHundredPointValues = <String, int>{
    'A+': 95,
    'A': 90,
    'A-': 87,
    'B+': 83,
    'B': 80,
    'B-': 77,
    'C+': 73,
    'C': 70,
    'C-': 67,
    'D': 60,
    'F': 0,
    '优秀': 90,
    '良好': 80,
    '中等': 70,
    '及格': 60,
    '不及格': 0,
    '合格': 75,
    '不合格': 0,
    '弃修': 0,
    '缺考': 0,
    '缓考': 0,
    '待录': 0,
    '无效': 0,
  };

  /// Four-point display values for exact server-supplied five-point values.
  static const importedFivePointToFourPoint = <MapEntry<double, double>>[
    MapEntry(5.0, 4.3),
    MapEntry(4.8, 4.2),
    MapEntry(4.5, 4.1),
    MapEntry(4.2, 4.0),
  ];

  const GradingMethodPolicy({
    required this.method,
    required this.example,
    required this.retainsNumericScore,
    required this.retainsGradeLabel,
    required this.providesGradePointDirectly,
    required this.requiresExplicitRuleForGradePoint,
  });

  final LocalGradingMethod method;
  final String example;
  final bool retainsNumericScore;
  final bool retainsGradeLabel;
  final bool providesGradePointDirectly;
  final bool requiresExplicitRuleForGradePoint;

  static const values = <GradingMethodPolicy>[
    GradingMethodPolicy(
      method: LocalGradingMethod.percentage,
      example: '89.5 分保留为原始分；没有换算规则时绩点缺失。',
      retainsNumericScore: true,
      retainsGradeLabel: false,
      providesGradePointDirectly: false,
      requiresExplicitRuleForGradePoint: true,
    ),
    GradingMethodPolicy(
      method: LocalGradingMethod.letter,
      example: 'A- 保留为原始等级；没有等级映射时绩点缺失。',
      retainsNumericScore: false,
      retainsGradeLabel: true,
      providesGradePointDirectly: false,
      requiresExplicitRuleForGradePoint: true,
    ),
    GradingMethodPolicy(
      method: LocalGradingMethod.passFail,
      example: '合格/不合格保留为原始结果；默认不推导绩点。',
      retainsNumericScore: false,
      retainsGradeLabel: true,
      providesGradePointDirectly: false,
      requiresExplicitRuleForGradePoint: true,
    ),
    GradingMethodPolicy(
      method: LocalGradingMethod.directGpa,
      example: '4.0 作为手填绩点；百分分数和等级保持缺失。',
      retainsNumericScore: false,
      retainsGradeLabel: false,
      providesGradePointDirectly: true,
      requiresExplicitRuleForGradePoint: false,
    ),
  ];

  static GradingMethodPolicy forMethod(LocalGradingMethod method) =>
      values.singleWhere((policy) => policy.method == method);

  /// Preserves the old imported Grade display fallback, not a GPA rule.
  static int importedLabelToHundredPoint(String original) {
    final mapped = importedLabelHundredPointValues[original];
    if (mapped != null) return mapped;
    final numericScore = RegExp(r'\d+').firstMatch(original)?.group(0);
    return int.tryParse(numericScore ?? '') ?? 0;
  }

  /// Preserves conversion of a server-supplied five-point value for display.
  static double importedFivePointToFourPointValue(double fivePoint) {
    if (fivePoint <= 4.0) return fivePoint;
    for (final mapping in importedFivePointToFourPoint) {
      if (mapping.key == fivePoint) return mapping.value;
    }
    return 4.0;
  }
}
