import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:celechron/manual/migration/semester_converter.dart';
import 'package:celechron/manual/model/local_course.dart';

final class LegacyCourseIdMapping {
  const LegacyCourseIdMapping({
    required this.semesterId,
    required this.legacyCourseId,
    required this.courseId,
  });

  final String semesterId;
  final String legacyCourseId;
  final String courseId;

  String get legacyKey => jsonEncode([semesterId, legacyCourseId]);
}

final class LegacyCourseConversionResult {
  const LegacyCourseConversionResult({
    required this.courses,
    required this.idMappings,
    required this.unresolvedCourses,
    required this.reviewItems,
  });

  final List<LocalCourse> courses;
  final List<LegacyCourseIdMapping> idMappings;
  final List<Map<String, Object?>> unresolvedCourses;
  final List<String> reviewItems;
}

/// Converts legacy course basics without merging by name or converting
/// sessions, exams, or grades.
final class LegacyCourseConverter {
  const LegacyCourseConverter();

  LegacyCourseConversionResult convert({
    required Map<String, Object?> scholar,
    required Set<String> convertedSemesterIds,
  }) {
    final courses = <LocalCourse>[];
    final mappings = <LegacyCourseIdMapping>[];
    final unresolved = <Map<String, Object?>>[];
    final review = <String>[];
    final rawSemesters = scholar['semesters'];
    if (rawSemesters is! List) {
      return const LegacyCourseConversionResult(
        courses: [],
        idMappings: [],
        unresolvedCourses: [],
        reviewItems: ['旧 Scholar 数据缺少学期列表，无法关联课程'],
      );
    }

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
      if (rawCourses is! Map || rawCourses.isEmpty) continue;
      if (!convertedSemesterIds.contains(semesterId)) {
        review.add('学期「${semester['name'] ?? ''}」尚未转换，所含课程保留待处理');
        for (final entry in rawCourses.entries) {
          unresolved.add(_unresolved(
            semesterIndex,
            entry.key,
            entry.value,
            '所属学期未能确定日期',
          ));
        }
        continue;
      }

      final seenLegacyIds = <String>{};
      for (final entry in rawCourses.entries) {
        final rawCourse = entry.value;
        if (rawCourse is! Map) {
          review.add('学期「${semester['name'] ?? ''}」含格式无效课程，未转换');
          unresolved.add(_unresolved(
            semesterIndex,
            entry.key,
            rawCourse,
            '课程记录格式无效',
          ));
          continue;
        }
        final course = Map<String, Object?>.from(rawCourse);
        final legacyId = course['id'];
        final name = course['name'];
        if (legacyId is! String || legacyId.trim().isEmpty) {
          review.add('课程「${name ?? ''}」缺少旧课程 ID，未按名称生成关联');
          unresolved.add(_unresolved(
            semesterIndex,
            entry.key,
            course,
            '缺少明确的旧课程 ID',
          ));
          continue;
        }
        if (!seenLegacyIds.add(legacyId)) {
          review.add('学期「${semester['name'] ?? ''}」存在重复旧课程 ID，重复记录待核对');
          unresolved.add(_unresolved(
            semesterIndex,
            entry.key,
            course,
            '同一学期内旧课程 ID 重复',
          ));
          continue;
        }
        if (name is! String || name.trim().isEmpty) {
          review.add('旧课程 ID「$legacyId」缺少课程名称，未转换');
          unresolved.add(_unresolved(
            semesterIndex,
            entry.key,
            course,
            '缺少课程名称',
          ));
          continue;
        }

        final rawCredits = course['credit'];
        double? credits;
        if (rawCredits is num && rawCredits.isFinite && rawCredits >= 0) {
          credits = rawCredits.toDouble();
        } else if (rawCredits != null) {
          review.add('课程「$name」学分格式/范围无效，按未知学分保留');
        }
        final rawTeacher = course['teacher'];
        final teacher = rawTeacher is String && rawTeacher.trim().isNotEmpty
            ? rawTeacher
            : null;
        if (rawTeacher != null && rawTeacher is! String) {
          review.add('课程「$name」教师字段格式无效，按未填写处理');
        }

        final targetId = _stableCourseId(semesterId, legacyId);
        courses.add(LocalCourse(
          id: targetId,
          semesterId: semesterId,
          name: name,
          credits: credits,
          teacher: teacher,
        ));
        mappings.add(LegacyCourseIdMapping(
          semesterId: semesterId,
          legacyCourseId: legacyId,
          courseId: targetId,
        ));
        final unsupported = [
          if (course['confirmed'] != null) 'confirmed',
          if (course['online'] != null) 'online',
          if (course['type'] != null) 'type',
        ];
        if (unsupported.isNotEmpty) {
          review.add('课程「$name」的 ${unsupported.join('/')} 属性未映射，保留在旧快照中供后续处理');
        }
      }
    }

    return LegacyCourseConversionResult(
      courses: List.unmodifiable(courses),
      idMappings: List.unmodifiable(mappings),
      unresolvedCourses: List.unmodifiable(unresolved),
      reviewItems: List.unmodifiable(review),
    );
  }

  static Map<String, Object?> _unresolved(
    int semesterIndex,
    Object? sourceMapKey,
    Object? rawCourse,
    String reason,
  ) {
    final course = rawCourse is Map ? rawCourse : const <Object?, Object?>{};
    return {
      'semesterIndex': semesterIndex,
      'sourceMapKey': sourceMapKey,
      'legacyCourseId': course['id'],
      'name': course['name'],
      'reason': reason,
    };
  }

  static String _stableCourseId(String semesterId, String legacyCourseId) {
    final bytes = sha256
        .convert(utf8.encode('legacy-course:$semesterId:$legacyCourseId'))
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
