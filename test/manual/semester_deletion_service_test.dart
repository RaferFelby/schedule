import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/grade_record.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/local_exam.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/model/session_rule.dart';
import 'package:celechron/manual/service/semester_deletion_service.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter_test/flutter_test.dart';

const _semesterA = '10000000-0000-4000-8000-000000000001';
const _semesterB = '10000000-0000-4000-8000-000000000002';
const _courseA = '20000000-0000-4000-8000-000000000001';
const _courseB = '20000000-0000-4000-8000-000000000002';

AcademicProfile _profile() => AcademicProfile(
      schemaVersion: 1,
      revision: 4,
      planningRevision: 2,
      currentSemesterId: _semesterA,
      semesters: [
        _semester(_semesterA, '秋季'),
        _semester(_semesterB, '春季'),
      ],
      courses: [
        LocalCourse(id: _courseA, semesterId: _semesterA, name: '课程甲'),
        LocalCourse(id: _courseB, semesterId: _semesterB, name: '课程乙'),
      ],
      sessionRules: [
        SessionRule(
          id: '30000000-0000-4000-8000-000000000001',
          courseId: _courseA,
          weekday: DateTime.monday,
          weekNumbers: [1],
          startSlotOrdinal: 1,
          endSlotOrdinal: 1,
        ),
        SessionRule(
          id: '30000000-0000-4000-8000-000000000002',
          courseId: _courseB,
          weekday: DateTime.tuesday,
          weekNumbers: [1],
          startSlotOrdinal: 2,
          endSlotOrdinal: 2,
        ),
      ],
      exams: [
        LocalExam(
          id: '40000000-0000-4000-8000-000000000001',
          courseId: _courseA,
          type: '期末',
          start: DateTime(2026, 12, 20, 9),
          end: DateTime(2026, 12, 20, 11),
        ),
      ],
      grades: [
        GradeRecord(
          id: '50000000-0000-4000-8000-000000000001',
          courseId: _courseA,
          status: LocalGradeStatus.notRecorded,
          method: LocalGradingMethod.percentage,
        ),
        GradeRecord(
          id: '50000000-0000-4000-8000-000000000002',
          courseId: _courseB,
          status: LocalGradeStatus.notRecorded,
          method: LocalGradingMethod.percentage,
        ),
      ],
    );

LocalSemester _semester(String id, String name) => LocalSemester(
      id: id,
      name: name,
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2027, 1, 31),
      weekOneStart: DateTime(2026, 8, 31),
    );

Task _task(String courseId) {
  final due = DateTime(2026, 12, 1, 23, 59);
  return Task(
    uid: 'task-semester-delete',
    summary: '课程作业',
    courseId: courseId,
    endTime: due,
    startTime: due.subtract(const Duration(days: 1)),
    repeatEndsTime: DateTime(2026, 12, 1),
    timeNeeded: const Duration(hours: 1),
    timeSpent: const Duration(minutes: 10),
    isCoursework: true,
    isTimeEstimated: true,
    isBreakable: false,
  );
}

void main() {
  test('impact counts dependencies and tasks by semester course IDs', () {
    final impact = SemesterDeletionService.impact(
      profile: _profile(),
      tasks: [_task(_courseA), _task(_courseB)],
      semesterId: _semesterA,
    );

    expect(impact, isNotNull);
    expect(impact!.courseIds, [_courseA]);
    expect(impact.sessionRuleCount, 1);
    expect(impact.examCount, 1);
    expect(impact.gradeCount, 1);
    expect(impact.taskCount, 1);
  });

  test('removes one semester cascade and keeps the other intact', () {
    final original = _profile();
    final updated = SemesterDeletionService.removeSemester(
      original,
      _semesterA,
    );

    expect(updated.currentSemesterId, isNull);
    expect(updated.semesters.map((item) => item.id), [_semesterB]);
    expect(updated.courses.map((item) => item.id), [_courseB]);
    expect(updated.sessionRules.map((item) => item.courseId), [_courseB]);
    expect(updated.exams, isEmpty);
    expect(updated.grades.map((item) => item.courseId), [_courseB]);
    expect(original.semesters, hasLength(2));
    expect(updated.revision, original.revision);
    expect(updated.planningRevision, original.planningRevision);
  });

  test('missing semester returns the same profile', () {
    final profile = _profile();
    expect(
      SemesterDeletionService.removeSemester(
        profile,
        '10000000-0000-4000-8000-000000000099',
      ),
      same(profile),
    );
  });
}
