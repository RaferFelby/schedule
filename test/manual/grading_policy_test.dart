import 'package:celechron/manual/model/grade_record.dart';
import 'package:celechron/manual/model/grading_policy.dart';
import 'package:celechron/model/grade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every grading method documents raw input and GPA availability', () {
    expect(GradingMethodPolicy.values, hasLength(4));
    for (final method in LocalGradingMethod.values) {
      final policy = GradingMethodPolicy.forMethod(method);
      expect(policy.example, isNotEmpty);
      expect(
        policy.providesGradePointDirectly,
        method == LocalGradingMethod.directGpa,
      );
      expect(
        policy.requiresExplicitRuleForGradePoint,
        method != LocalGradingMethod.directGpa,
      );
    }
  });

  test('percentage policy does not invent GPA for a decimal score', () {
    final policy = GradingMethodPolicy.forMethod(LocalGradingMethod.percentage);

    expect(policy.retainsNumericScore, isTrue);
    expect(policy.providesGradePointDirectly, isFalse);
    expect(policy.requiresExplicitRuleForGradePoint, isTrue);
    expect(policy.example, contains('89.5'));
    expect(policy.example, contains('绩点缺失'));
  });

  test('legacy label mappings and numeric fallback remain exact', () {
    const expected = <String, int>{
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
    expect(GradingMethodPolicy.importedLabelHundredPointValues, expected);
    for (final entry in expected.entries) {
      expect(GradingMethodPolicy.importedLabelToHundredPoint(entry.key),
          entry.value);
    }
    expect(GradingMethodPolicy.importedLabelToHundredPoint('89.5'), 89);
    expect(GradingMethodPolicy.importedLabelToHundredPoint('未识别'), 0);
  });

  test('legacy imported five-point display mappings remain exact', () {
    expect(
      GradingMethodPolicy.importedFivePointToFourPoint,
      const [
        MapEntry(5.0, 4.3),
        MapEntry(4.8, 4.2),
        MapEntry(4.5, 4.1),
        MapEntry(4.2, 4.0),
      ],
    );
    expect(GradingMethodPolicy.importedFivePointToFourPointValue(3.8), 3.8);
    expect(GradingMethodPolicy.importedFivePointToFourPointValue(4.6), 4.0);

    final legacyGrade = Grade({
      'xkkh': 'legacy-course-id',
      'kcmc': '旧成绩',
      'xf': 3,
      'cj': 'A-',
      'jd': 4.5,
    });
    expect(legacyGrade.hundredPoint, 87);
    expect(legacyGrade.fourPoint, 4.1);
  });
}
