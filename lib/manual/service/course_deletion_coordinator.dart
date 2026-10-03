import 'dart:convert';

import 'package:hive/hive.dart';

import '../../debug/manual_preview_storage.dart';
import '../../debug/manual_preview_task_store.dart';
import '../data/academic_repository.dart';
import 'course_deletion_service.dart';
import 'semester_deletion_service.dart';

typedef CourseTaskUnlinker = Future<int> Function(String courseId);

/// Resumes a preview course deletion if either local save was interrupted.
final class CourseDeletionCoordinator {
  CourseDeletionCoordinator({
    required AcademicRepository repository,
    required Box<String> previewBox,
    CourseTaskUnlinker? unlinkCourse,
  })  : _repository = repository,
        _previewBox = previewBox,
        _unlinkCourse =
            unlinkCourse ?? ManualPreviewTaskStore(previewBox).unlinkCourse;

  static const journalKey = ManualPreviewStorage.courseDeletionJournalKey;

  final AcademicRepository _repository;
  final Box<String> _previewBox;
  final CourseTaskUnlinker _unlinkCourse;

  Future<void> removeCourse(String courseId) async {
    await recoverPending();
    await _previewBox.put(
      journalKey,
      jsonEncode({
        'type': 'course',
        'id': courseId,
        'courseIds': [courseId],
      }),
    );
    await recoverPending();
  }

  Future<void> removeSemester(String semesterId) async {
    await recoverPending();
    final current = await _repository.read();
    final courseIds = current.courses
        .where((course) => course.semesterId == semesterId)
        .map((course) => course.id)
        .toList()
      ..sort();
    await _previewBox.put(
      journalKey,
      jsonEncode({
        'type': 'semester',
        'id': semesterId,
        'courseIds': courseIds,
      }),
    );
    await recoverPending();
  }

  Future<void> recoverPending() async {
    final encoded = _previewBox.get(journalKey);
    if (encoded == null) return;

    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      rethrow;
    }
    if (decoded is! Map) {
      throw const FormatException('课程删除恢复标记格式无效');
    }
    final type = decoded['type'] ?? 'course';
    final id = decoded['id'] ?? decoded['courseId'];
    final rawCourseIds = decoded['courseIds'];
    if ((type != 'course' && type != 'semester') ||
        id is! String ||
        (rawCourseIds != null &&
            (rawCourseIds is! List ||
                rawCourseIds.any((value) => value is! String)))) {
      throw const FormatException('课程删除恢复标记格式无效');
    }
    final courseIds =
        rawCourseIds == null ? [id] : (rawCourseIds as List).cast<String>();

    final current = await _repository.read();
    if (type == 'course') {
      if (current.courses.any((course) => course.id == id)) {
        await _repository.save(CourseDeletionService.removeCourse(current, id));
      }
    } else if (current.semesters.any((semester) => semester.id == id)) {
      await _repository
          .save(SemesterDeletionService.removeSemester(current, id));
    }
    for (final courseId in courseIds) {
      await _unlinkCourse(courseId);
    }
    await _previewBox.delete(journalKey);
  }
}
