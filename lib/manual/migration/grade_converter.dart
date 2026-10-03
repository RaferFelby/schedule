import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:celechron/manual/migration/course_converter.dart';
import 'package:celechron/manual/migration/semester_converter.dart';
import 'package:celechron/manual/model/grade_record.dart';
import 'package:celechron/manual/model/local_course.dart';

final class LegacyGradeConversionResult {
  const LegacyGradeConversionResult({
    required this.grades,
    required this.gradeIdMappings,
    required this.unresolvedGrades,
    required this.reviewItems,
  });

  final List<GradeRecord> grades;
  final List<LegacyGradeIdMapping> gradeIdMappings;
  final List<Map<String, Object?>> unresolvedGrades;
  final List<String> reviewItems;
}

final class LegacyGradeIdMapping {
  const LegacyGradeIdMapping({
    required this.semesterIndex,
    required this.legacyGradeId,
    required this.courseId,
    required this.gradeId,
  });

  final int semesterIndex;
  final String legacyGradeId;
  final String courseId;
  final String gradeId;
}

/// Converts only grades with an explicit course relationship.
final class LegacyGradeConverter {
  const LegacyGradeConverter();

  LegacyGradeConversionResult convert({
    required Map<String, Object?> scholar,
    required Iterable<LegacyCourseIdMapping> courseMappings,
    required Iterable<LocalCourse> courses,
  }) {
    final grades = <GradeRecord>[];
    final gradeIdMappings = <LegacyGradeIdMapping>[];
    final unresolved = <Map<String, Object?>>[];
    final review = <String>[];
    final mappingByKey = {
      for (final mapping in courseMappings) mapping.legacyKey: mapping,
    };
    final targetCourses = {for (final course in courses) course.id: course};
    final convertedKeys = <String>{};
    final rawSemesters = scholar['semesters'];
    if (rawSemesters is! List) {
      return const LegacyGradeConversionResult(
        grades: [],
        gradeIdMappings: [],
        unresolvedGrades: [],
        reviewItems: ['旧 Scholar 数据缺少学期列表，无法转换成绩'],
      );
    }

    void addGrade({
      required int semesterIndex,
      required LegacyCourseIdMapping? mapping,
      required Object? rawGrade,
      required int gradeIndex,
      required Object? courseMapKey,
      required String sourceKind,
    }) {
      final grade =
          rawGrade is Map ? Map<String, Object?>.from(rawGrade) : null;
      String? reason;
      if (grade == null) {
        reason = '成绩记录格式无效';
      } else if (mapping == null) {
        reason = '缺少明确的旧课程 ID 映射';
      }
      if (reason == null && grade != null && mapping != null) {
        final key = jsonEncode([mapping.courseId, grade]);
        if (convertedKeys.contains(key)) return;
        convertedKeys.add(key);
      }
      final original = grade?['original'];
      if (reason == null && (original is! String || original.trim().isEmpty)) {
        reason = '原始成绩字段缺失';
      }
      final gpaIncluded = grade?['gpaIncluded'];
      final creditIncluded = grade?['creditIncluded'];
      if (reason == null && (gpaIncluded is! bool || creditIncluded is! bool)) {
        reason = 'GPA/学分计入标记缺失或格式无效';
      }
      final major = grade?['major'];
      if (reason == null && major != null && major is! bool) {
        reason = '主修标记格式无效';
      }

      LocalGradeStatus? status;
      LocalGradingMethod? method;
      double? rawScore;
      String? gradeLabel;
      double? gradePoint;
      if (reason == null && grade != null && original is String) {
        if (original.trim() == '待录') {
          status = LocalGradeStatus.notRecorded;
          // The legacy schema does not encode a grading method for pending work.
          method = LocalGradingMethod.percentage;
          review.add('成绩「$original」保留为未录状态；原评分方式不可确定');
        } else {
          status = LocalGradeStatus.recorded;
          final numeric = double.tryParse(original.trim());
          if (numeric != null) {
            if (!numeric.isFinite || numeric < 0 || numeric > 100) {
              reason = '数值成绩超出 0 至 100 范围';
            } else {
              method = LocalGradingMethod.percentage;
              rawScore = numeric;
            }
          } else if (_passFailLabels.contains(original.trim().toLowerCase())) {
            method = LocalGradingMethod.passFail;
            gradeLabel = original;
          } else {
            method = LocalGradingMethod.letter;
            gradeLabel = original;
          }

          if (reason == null) {
            final rawFivePoint = grade['fivePoint'];
            if (rawFivePoint is num) {
              final value = rawFivePoint.toDouble();
              if (!value.isFinite || value < 0) {
                reason = '原始五分绩点无效';
              } else {
                gradePoint = value;
              }
            } else {
              reason = '原始五分绩点字段缺失或格式无效';
            }
          }
        }
      }

      final rawCredits = grade?['credit'];
      final targetCourse =
          mapping == null ? null : targetCourses[mapping.courseId];
      if (reason == null && targetCourse == null) {
        reason = '目标课程记录不存在';
      }
      if (reason == null && targetCourse?.credits == null) {
        reason = '目标课程学分未知，无法保存该成绩的学分';
      }
      if (reason == null && rawCredits is! num) {
        reason = '成绩学分字段缺失或格式无效';
      }
      if (reason == null &&
          rawCredits is num &&
          (!rawCredits.isFinite || rawCredits < 0)) {
        reason = '成绩学分必须为非负有限值';
      }
      if (reason == null &&
          rawCredits is num &&
          targetCourse?.credits != null &&
          rawCredits.toDouble() != targetCourse!.credits) {
        reason = '成绩学分与课程学分不一致，目标成绩模型无法无损保存';
      }

      if (reason != null ||
          mapping == null ||
          status == null ||
          method == null) {
        unresolved.add({
          'semesterIndex': semesterIndex,
          'courseMapKey': courseMapKey,
          'legacyCourseId': mapping?.legacyCourseId,
          'gradeIndex': gradeIndex,
          'sourceKind': sourceKind,
          'legacyGradeId': grade?['id'],
          'original': original,
          'reason': reason ?? '成绩关联或格式无法确定',
        });
        review.add('旧成绩待核对：${reason ?? '关联或格式无法确定'}');
        return;
      }

      if (major == null) {
        review.add('旧成绩未保存逐科主修标记，目标记录按 false 填写并保留待审核信息');
      }
      final recordId = _stableGradeId(
        semesterIndex,
        mapping.courseId,
        gradeIndex,
        grade ?? const {},
      );
      final record = GradeRecord(
        id: recordId,
        courseId: mapping.courseId,
        status: status,
        method: method,
        rawScore: rawScore,
        gradeLabel: gradeLabel,
        gradePoint: gradePoint,
        isMajor: major is bool ? major : false,
        countsTowardGpa: gpaIncluded as bool,
        countsTowardCredits: creditIncluded as bool,
      );
      grades.add(record);
      final legacyGradeId = grade?['id'];
      if (legacyGradeId is String && legacyGradeId.trim().isNotEmpty) {
        gradeIdMappings.add(LegacyGradeIdMapping(
          semesterIndex: semesterIndex,
          legacyGradeId: legacyGradeId,
          courseId: mapping.courseId,
          gradeId: record.id,
        ));
      } else {
        review.add('旧成绩缺少 Grade.id，已保留成绩但无法迁移其 ID 级 GPA 偏好');
      }
      if (grade?['fourPoint'] != null || grade?['hundredPoint'] != null) {
        review.add('旧成绩展示换算值未单独保存；保留原始成绩与五分绩点供后续重新展示');
      }
    }

    final semesterGradeSignatures = <String>{};
    final nestedGradeSignatures = <String>{};
    for (var semesterIndex = 0;
        semesterIndex < rawSemesters.length;
        semesterIndex++) {
      final rawSemester = rawSemesters[semesterIndex];
      if (rawSemester is! Map) continue;
      final semester = Map<String, Object?>.from(rawSemester);
      final semesterId = LegacySemesterConverter.stableSemesterId(
        semester,
        semesterIndex,
      );
      final rawCourses = semester['courses'];
      final mappedByLegacyId =
          <String, List<MapEntry<Object?, LegacyCourseIdMapping>>>{};
      if (rawCourses is Map) {
        for (final courseEntry in rawCourses.entries) {
          final rawCourse = courseEntry.value;
          if (rawCourse is! Map) continue;
          final course = Map<String, Object?>.from(rawCourse);
          final legacyId = course['id'];
          final mapping = legacyId is String
              ? mappingByKey[jsonEncode([semesterId, legacyId])]
              : null;
          if (legacyId is String && mapping != null) {
            mappedByLegacyId.putIfAbsent(legacyId, () => []).add(
                  MapEntry(courseEntry.key, mapping),
                );
          }
          final nestedGrade = course['grade'];
          if (nestedGrade is Map) {
            final gradeMap = Map<String, Object?>.from(nestedGrade);
            final signature = jsonEncode([semesterIndex, gradeMap]);
            semesterGradeSignatures.add(signature);
            nestedGradeSignatures.add(signature);
            addGrade(
              semesterIndex: semesterIndex,
              mapping: mapping,
              rawGrade: gradeMap,
              gradeIndex: 0,
              courseMapKey: courseEntry.key,
              sourceKind: 'courseGrade',
            );
          }
        }
      }

      final rawGrades = semester['grades'];
      if (rawGrades is List) {
        for (var index = 0; index < rawGrades.length; index++) {
          final rawGrade = rawGrades[index];
          final gradeMap =
              rawGrade is Map ? Map<String, Object?>.from(rawGrade) : null;
          if (gradeMap == null) {
            addGrade(
              semesterIndex: semesterIndex,
              mapping: null,
              rawGrade: rawGrade,
              gradeIndex: index,
              courseMapKey: null,
              sourceKind: 'semesterGrades',
            );
            continue;
          }
          final signature = jsonEncode([semesterIndex, gradeMap]);
          if (nestedGradeSignatures.contains(signature)) continue;
          semesterGradeSignatures.add(signature);
          final legacyGradeId = gradeMap['id'];
          final candidates = legacyGradeId is String
              ? mappedByLegacyId[legacyGradeId] ?? const []
              : const <MapEntry<Object?, LegacyCourseIdMapping>>[];
          final exactCandidates = candidates
              .where((entry) => entry.value.legacyCourseId == legacyGradeId)
              .toList();
          if (exactCandidates.length == 1) {
            addGrade(
              semesterIndex: semesterIndex,
              mapping: exactCandidates.single.value,
              rawGrade: gradeMap,
              gradeIndex: index,
              courseMapKey: exactCandidates.single.key,
              sourceKind: 'semesterGrades',
            );
          } else {
            unresolved.add({
              'semesterIndex': semesterIndex,
              'gradeIndex': index,
              'sourceKind': 'semesterGrades',
              'legacyGradeId': legacyGradeId,
              'original': gradeMap['original'],
              'reason': '学期成绩无法通过完整旧课程 ID 唯一关联',
            });
            review.add('学期成绩「${gradeMap['name'] ?? ''}」无法唯一关联课程，待核对');
          }
        }
      }
    }

    final rawOverallGrades = scholar['grades'];
    if (rawOverallGrades is Map) {
      for (final entry in rawOverallGrades.entries) {
        if (entry.value is! List) continue;
        for (var index = 0; index < (entry.value as List).length; index++) {
          final rawGrade = (entry.value as List)[index];
          if (rawGrade is! Map) {
            unresolved.add({
              'legacyGradeGroupKey': entry.key,
              'gradeIndex': index,
              'sourceKind': 'globalGrades',
              'reason': '全局成绩记录格式无效',
            });
            continue;
          }
          final grade = Map<String, Object?>.from(rawGrade);
          final legacyId = grade['id'];
          final candidates = <(int, LegacyCourseIdMapping, Object?)>[];
          if (legacyId is String) {
            for (var semesterIndex = 0;
                semesterIndex < rawSemesters.length;
                semesterIndex++) {
              final rawSemester = rawSemesters[semesterIndex];
              if (rawSemester is! Map) continue;
              final coursesValue = rawSemester['courses'];
              if (coursesValue is! Map) continue;
              final semesterId = LegacySemesterConverter.stableSemesterId(
                Map<String, Object?>.from(rawSemester),
                semesterIndex,
              );
              for (final courseEntry in coursesValue.entries) {
                if (courseEntry.value is! Map) continue;
                final course =
                    Map<String, Object?>.from(courseEntry.value as Map);
                if (course['id'] != legacyId) continue;
                final mapping =
                    mappingByKey[jsonEncode([semesterId, legacyId])];
                if (mapping != null) {
                  candidates.add((semesterIndex, mapping, courseEntry.key));
                }
              }
            }
          }
          if (candidates.length == 1) {
            final candidate = candidates.single;
            if (!semesterGradeSignatures
                .contains(jsonEncode([candidate.$1, grade]))) {
              addGrade(
                semesterIndex: candidate.$1,
                mapping: candidate.$2,
                rawGrade: grade,
              gradeIndex: index,
              courseMapKey: candidate.$3,
              sourceKind: 'globalGrades',
              );
            }
          } else {
            unresolved.add({
              'legacyGradeGroupKey': entry.key,
              'gradeIndex': index,
              'sourceKind': 'globalGrades',
              'legacyGradeId': legacyId,
              'reason': '全局成绩无法通过完整旧课程 ID 唯一关联到学期课程',
            });
            review.add('全局成绩组「${entry.key}」包含无法唯一关联课程的成绩，待核对');
          }
        }
      }
    }

    review.add('旧 Scholar 未保存明确的重修组关系；未按课程名称或编号自动合并');
    return LegacyGradeConversionResult(
      grades: List.unmodifiable(grades),
      gradeIdMappings: List.unmodifiable(gradeIdMappings),
      unresolvedGrades: List.unmodifiable(unresolved),
      reviewItems: List.unmodifiable(review),
    );
  }

  static const _passFailLabels = {
    '合格',
    '不合格',
    '通过',
    '不通过',
    'pass',
    'passed',
    'fail',
    'failed',
  };

  static String _stableGradeId(
    int semesterIndex,
    String courseId,
    int gradeIndex,
    Map<String, Object?> grade,
  ) {
    final bytes = sha256
        .convert(utf8.encode(
          'legacy-grade:$semesterIndex:$courseId:$gradeIndex:${jsonEncode(grade)}',
        ))
        .bytes
        .take(16)
        .toList();
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
