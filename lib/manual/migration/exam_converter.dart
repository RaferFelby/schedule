import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:celechron/manual/migration/course_converter.dart';
import 'package:celechron/manual/migration/semester_converter.dart';
import 'package:celechron/manual/model/local_exam.dart';

final class LegacyExamConversionResult {
  const LegacyExamConversionResult({
    required this.exams,
    required this.unresolvedExams,
    required this.reviewItems,
  });

  final List<LocalExam> exams;
  final List<Map<String, Object?>> unresolvedExams;
  final List<String> reviewItems;
}

/// Converts course-owned exams without inferring associations from names.
final class LegacyExamConverter {
  const LegacyExamConverter();

  LegacyExamConversionResult convert({
    required Map<String, Object?> scholar,
    required Iterable<LegacyCourseIdMapping> courseMappings,
  }) {
    final exams = <LocalExam>[];
    final unresolved = <Map<String, Object?>>[];
    final review = <String>[];
    final mappingByKey = {
      for (final mapping in courseMappings) mapping.legacyKey: mapping,
    };
    final rawSemesters = scholar['semesters'];
    if (rawSemesters is! List) {
      return const LegacyExamConversionResult(
        exams: [],
        unresolvedExams: [],
        reviewItems: ['旧 Scholar 数据缺少学期列表，无法转换考试'],
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
      final nestedSignatures = <String>{};
      final rawCourses = semester['courses'];
      if (rawCourses is Map) {
        for (final courseEntry in rawCourses.entries) {
          final rawCourse = courseEntry.value;
          if (rawCourse is! Map) continue;
          final course = Map<String, Object?>.from(rawCourse);
          final legacyCourseId = course['id'];
          final mapping = legacyCourseId is String
              ? mappingByKey[jsonEncode([semesterId, legacyCourseId])]
              : null;
          final rawExams = course['exams'];
          if (rawExams is! List) continue;
          for (var examIndex = 0; examIndex < rawExams.length; examIndex++) {
            final rawExam = rawExams[examIndex];
            if (rawExam is! Map) {
              unresolved.add(_unresolved(
                semesterIndex,
                courseEntry.key,
                legacyCourseId,
                examIndex,
                null,
                '考试记录格式无效',
              ));
              review.add('课程「${course['name'] ?? ''}」包含格式无效考试记录');
              continue;
            }
            final exam = Map<String, Object?>.from(rawExam);
            nestedSignatures.add(jsonEncode(exam));
            String? reason;
            if (mapping == null) {
              reason = '缺少明确的旧课程 ID 映射';
            }
            if (reason == null &&
                exam['id'] != null &&
                exam['id'] != legacyCourseId) {
              reason = '考试 ID 与所属课程 ID 不一致';
            }
            final typeIndex = exam['type'];
            if (reason == null &&
                (typeIndex is! int || typeIndex < 0 || typeIndex > 1)) {
              reason = '考试类型缺失或不受支持';
            }
            final timeValue = exam['time'];
            DateTime? start;
            DateTime? end;
            if (reason == null) {
              if (timeValue is List && timeValue.isEmpty) {
                // An explicitly unknown time is a valid migrated exam.
              } else if (timeValue is! List ||
                  timeValue.length != 2 ||
                  timeValue.any((value) => value is! String)) {
                reason = '考试时间必须是两个有效端点或明确未定';
              } else {
                start = DateTime.tryParse(timeValue[0] as String);
                end = DateTime.tryParse(timeValue[1] as String);
                if (start == null || end == null || !end.isAfter(start)) {
                  reason = '考试时间无效或结束不晚于开始';
                }
              }
            }
            final location = exam['location'];
            final seat = exam['seat'];
            if (reason == null &&
                ((location != null && location is! String) ||
                    (seat != null && seat is! String))) {
              reason = '考场或座位字段格式无效';
            }
            if (reason != null || mapping == null || typeIndex is! int) {
              unresolved.add(_unresolved(
                semesterIndex,
                courseEntry.key,
                legacyCourseId,
                examIndex,
                exam,
                reason ?? '考试关联无法确定',
              ));
              review.add('课程「${course['name'] ?? ''}」的考试待核对：$reason');
              continue;
            }
            final type = typeIndex == 0 ? 'midterm' : 'finalExam';
            final dateLabel = exam['dateLabel'];
            if (dateLabel is String && dateLabel.isNotEmpty && start == null) {
              review.add('课程「${course['name'] ?? ''}」的考试仅有日期标签，日期/时间仍未定');
            }
            exams.add(LocalExam(
              id: _stableExamId(
                semesterIndex,
                mapping.courseId,
                examIndex,
                exam,
              ),
              courseId: mapping.courseId,
              type: type,
              start: start,
              end: end,
              location: location is String && location.trim().isNotEmpty
                  ? location
                  : null,
              seat: seat is String && seat.trim().isNotEmpty ? seat : null,
            ));
          }
        }
      }

      final rawExams = semester['exams'];
      if (rawExams is List) {
        for (var index = 0; index < rawExams.length; index++) {
          final rawExam = rawExams[index];
          if (rawExam is Map &&
              nestedSignatures.contains(jsonEncode(rawExam))) {
            continue;
          }
          unresolved.add(_unresolved(
            semesterIndex,
            null,
            rawExam is Map ? rawExam['id'] : null,
            index,
            rawExam is Map ? Map<String, Object?>.from(rawExam) : null,
            '学期级考试未能对应到明确课程记录',
          ));
          review.add('学期「${semester['name'] ?? ''}」有未关联课程的考试，保留待处理');
        }
      }
    }

    return LegacyExamConversionResult(
      exams: List.unmodifiable(exams),
      unresolvedExams: List.unmodifiable(unresolved),
      reviewItems: List.unmodifiable(review),
    );
  }

  static Map<String, Object?> _unresolved(
    int semesterIndex,
    Object? courseMapKey,
    Object? legacyCourseId,
    int examIndex,
    Map<String, Object?>? exam,
    String reason,
  ) =>
      {
        'semesterIndex': semesterIndex,
        'courseMapKey': courseMapKey,
        'legacyCourseId': legacyCourseId,
        'examIndex': examIndex,
        'legacyExamId': exam?['id'],
        'name': exam?['name'],
        'type': exam?['type'],
        'reason': reason,
      };

  static String _stableExamId(
    int semesterIndex,
    String courseId,
    int examIndex,
    Map<String, Object?> exam,
  ) {
    final bytes = sha256
        .convert(utf8.encode(
          'legacy-exam:$semesterIndex:$courseId:$examIndex:${jsonEncode(exam)}',
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
