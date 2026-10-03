import 'dart:convert';

import 'package:celechron/manual/migration/grade_converter.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/retake_selection_strategy.dart';

final class LegacyGradePreferenceConversionResult {
  const LegacyGradePreferenceConversionResult({
    required this.courses,
    required this.unresolvedPreferences,
    required this.reviewItems,
  });

  final List<LocalCourse> courses;
  final List<Map<String, Object?>> unresolvedPreferences;
  final List<String> reviewItems;
}

/// Applies only legacy preferences with a unique Grade.id → course mapping.
final class LegacyGradePreferenceConverter {
  const LegacyGradePreferenceConverter();

  LegacyGradePreferenceConversionResult convert({
    required Iterable<LocalCourse> courses,
    required Iterable<LegacyGradeIdMapping> gradeIdMappings,
    required Map<String, Object?> legacyOptions,
    required Map<String, Object?> legacyCustomGpa,
  }) {
    final courseList = courses.toList();
    final knownCourseIds = courseList.map((course) => course.id).toSet();
    final mappings = gradeIdMappings.toList();
    final unresolved = <Map<String, Object?>>[];
    final review = <String>[];
    final selectedByCourse = <String, List<bool>>{};
    final weightByCourse = <String, List<double>>{};

    void readGradePreference({
      required Object? rawPreferences,
      required String field,
      required bool isWeight,
    }) {
      if (rawPreferences == null) return;
      if (rawPreferences is! Map) {
        unresolved.add({'field': field, 'reason': '偏好值必须是映射表'});
        review.add('$field 不是映射表，未应用');
        return;
      }
      for (final entry in rawPreferences.entries) {
        final gradeId = entry.key;
        final value = entry.value;
        if (gradeId is! String || gradeId.trim().isEmpty) {
          unresolved.add({'field': field, 'reason': '偏好包含空/无效 Grade.id'});
          continue;
        }
        if (isWeight) {
          if (value is! num || !value.isFinite || value < 0) {
            unresolved.add({
              'field': field,
              'legacyGradeId': gradeId,
              'reason': '权重必须是非负有限数值',
            });
            review.add('Grade.id「$gradeId」的权重无效，未应用');
            continue;
          }
        } else if (value is! bool) {
          unresolved.add({
            'field': field,
            'legacyGradeId': gradeId,
            'reason': '自选状态必须是布尔值',
          });
          review.add('Grade.id「$gradeId」的自选状态无效，未应用');
          continue;
        }
        final matches = mappings
            .where((mapping) => mapping.legacyGradeId == gradeId)
            .toList();
        if (matches.length != 1) {
          unresolved.add({
            'field': field,
            'legacyGradeId': gradeId,
            'reason':
                matches.isEmpty ? '没有对应的已迁移成绩' : 'Grade.id 对应多条迁移成绩，无法唯一映射',
          });
          review.add('Grade.id「$gradeId」的 $field 无法唯一映射');
          continue;
        }
        final courseId = matches.single.courseId;
        if (!knownCourseIds.contains(courseId)) {
          unresolved.add({
            'field': field,
            'legacyGradeId': gradeId,
            'reason': '成绩映射引用了不存在的目标课程',
          });
          review.add('Grade.id「$gradeId」映射到不存在的目标课程，偏好未应用');
          continue;
        }
        if (isWeight) {
          weightByCourse.putIfAbsent(courseId, () => []).add(value.toDouble());
        } else {
          selectedByCourse.putIfAbsent(courseId, () => []).add(value as bool);
        }
      }
    }

    final rawSelection = legacyCustomGpa['selectList'];
    final rawWeights = legacyCustomGpa['weightedGpa'];
    readGradePreference(
      rawPreferences: rawSelection,
      field: 'selectList',
      isWeight: false,
    );
    readGradePreference(
      rawPreferences: rawWeights,
      field: 'weightedGpa',
      isWeight: true,
    );

    RetakeSelectionStrategy? globalStrategy;
    final rawStrategy = legacyOptions['gpaStrategy'];
    if (rawStrategy == 0) {
      globalStrategy = RetakeSelectionStrategy.highestGpa;
    } else if (rawStrategy == 1) {
      globalStrategy = RetakeSelectionStrategy.firstAttempt;
    } else if (rawStrategy != null) {
      unresolved.add({
        'field': 'gpaStrategy',
        'value': rawStrategy,
        'reason': '仅支持旧值 0(best) 或 1(first)',
      });
      review.add('旧 GPA 策略无效，未应用');
    }

    final updatedCourses = <LocalCourse>[];
    for (final course in courseList) {
      final selections = selectedByCourse[course.id] ?? const <bool>[];
      final weights = weightByCourse[course.id] ?? const <double>[];
      final selectedValues = selections.toSet();
      final weightValues = weights.toSet();
      final selectedForGpa = selectedValues.length == 1
          ? selectedValues.single
          : course.selectedForGpa;
      final gpaWeight =
          weightValues.length == 1 ? weightValues.single : course.gpaWeight;
      if (selectedValues.length > 1) {
        review.add('课程「${course.name}」对应的旧成绩自选状态冲突，保持现值');
      }
      if (weightValues.length > 1) {
        review.add('课程「${course.name}」对应的旧成绩权重冲突，保持现值');
      }
      updatedCourses.add(LocalCourse(
        id: course.id,
        semesterId: course.semesterId,
        name: course.name,
        courseNumber: course.courseNumber,
        credits: course.credits,
        teacher: course.teacher,
        isMajor: course.isMajor,
        selectedForGpa: selectedForGpa,
        gpaWeight: gpaWeight,
        retakeGroupId: course.retakeGroupId,
        retakeStrategy: globalStrategy ?? course.retakeStrategy,
      ));
    }

    if (rawSelection is Map && rawSelection.isNotEmpty) {
      review.add('旧成绩级自选结果仅在同一新课程映射唯一时应用；未列出的新课程保留默认状态');
    }
    if (rawWeights is Map && rawWeights.isNotEmpty) {
      review.add('旧成绩级权重已汇总到课程；同一课程多条成绩权重冲突时保持默认值');
    }
    return LegacyGradePreferenceConversionResult(
      courses: List.unmodifiable(updatedCourses),
      unresolvedPreferences: List.unmodifiable(unresolved),
      reviewItems: List.unmodifiable(review),
    );
  }
}

/// Parses a copied Hive preference map without opening or mutating its box.
Map<String, Object?> decodeLegacyCustomGpaProjection(Object? value) {
  if (value is! Map) return const {};
  return Map<String, Object?>.fromEntries(
    value.entries.where((entry) => entry.key is String).map(
          (entry) => MapEntry(entry.key as String, entry.value),
        ),
  );
}

/// Creates a stable key for identifying old-grade preferences in reports.
String legacyGradePreferenceKey(int semesterIndex, String legacyGradeId) =>
    jsonEncode([semesterIndex, legacyGradeId]);
