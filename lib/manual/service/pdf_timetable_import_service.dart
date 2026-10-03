import 'package:uuid/uuid.dart';

import '../data/academic_repository.dart';
import '../data/local_data_error.dart';
import '../model/academic_profile.dart';
import '../model/local_course.dart';
import '../model/session_rule.dart';
import '../model/time_slot.dart';
import 'pdf_timetable_parser.dart';

/// Saves a reviewed PDF draft as one additive academic snapshot update.
final class PdfTimetableImportService {
  PdfTimetableImportService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  Future<AcademicProfile> importReviewedDraft({
    required AcademicRepository repository,
    required String semesterId,
    required TimetableImportDraft draft,
  }) async {
    final included = draft.courses.where((course) => course.include).toList();
    if (included.isEmpty || included.any((course) => !course.isComplete)) {
      throw const LocalDataValidationError('请先补齐课程名称、星期、周次和节次');
    }

    return repository.update((current) {
      final semester = current.semesters.where((item) => item.id == semesterId);
      if (semester.length != 1) {
        throw const LocalDataValidationError('所选学期已不存在');
      }
      final maxWeek = semester.single.endDate
                  .difference(semester.single.weekOneStart)
                  .inDays ~/
              7 +
          1;
      if (included.any((course) => course.sessions.any(
          (session) => session.weekNumbers.any((week) => week > maxWeek)))) {
        throw const LocalDataValidationError('上课周次超出所选学期范围');
      }
      final slots = current.timeSlots.isEmpty
          ? TimeSlot.defaultTemplate()
          : current.timeSlots;
      final ordinals = slots.map((slot) => slot.ordinal).toSet();
      for (final course in included) {
        for (final session in course.sessions) {
          for (var slot = session.startSlot!;
              slot <= session.endSlot!;
              slot++) {
            if (!ordinals.contains(slot)) {
              throw LocalDataValidationError('请先为第 $slot 节配置上课时间');
            }
          }
        }
      }

      final addedCourses = <LocalCourse>[];
      final addedRules = <SessionRule>[];
      for (final draftCourse in included) {
        final courseId = _uuid.v4();
        addedCourses.add(LocalCourse(
          id: courseId,
          semesterId: semesterId,
          name: draftCourse.name.trim(),
          courseNumber: _optional(draftCourse.courseNumber),
          credits: draftCourse.credits,
          teacher: _optional(draftCourse.teacher),
        ));
        for (final session in draftCourse.sessions) {
          addedRules.add(SessionRule(
            id: _uuid.v4(),
            courseId: courseId,
            weekday: session.weekday!,
            weekNumbers: session.weekNumbers.toSet().toList()..sort(),
            startSlotOrdinal: session.startSlot!,
            endSlotOrdinal: session.endSlot!,
            teacher: _optional(session.teacher),
            location: _optional(session.location),
          ));
        }
      }
      return AcademicProfile(
        schemaVersion: current.schemaVersion,
        revision: current.revision,
        planningRevision: current.planningRevision,
        currentSemesterId: current.currentSemesterId,
        semesters: current.semesters,
        timeSlots: current.timeSlots,
        courses: [...current.courses, ...addedCourses],
        sessionRules: [...current.sessionRules, ...addedRules],
        exams: current.exams,
        grades: current.grades,
        practiceRecords: current.practiceRecords,
      );
    });
  }

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
