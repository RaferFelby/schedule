import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/grade_record.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/local_exam.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/model/session_rule.dart';
import 'package:celechron/manual/service/course_deletion_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _semesterId = '10000000-0000-4000-8000-000000000001';
const _courseA = '20000000-0000-4000-8000-000000000001';
const _courseB = '20000000-0000-4000-8000-000000000002';

AcademicProfile _profile() => AcademicProfile(
      schemaVersion: 1,
      revision: 8,
      planningRevision: 3,
      currentSemesterId: _semesterId,
      semesters: [
        LocalSemester(
          id: _semesterId,
          name: '秋季学期',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2027, 1, 31),
          weekOneStart: DateTime(2026, 8, 31),
        ),
      ],
      courses: [
        LocalCourse(id: _courseA, semesterId: _semesterId, name: '课程甲'),
        LocalCourse(id: _courseB, semesterId: _semesterId, name: '课程乙'),
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
        LocalExam(
          id: '40000000-0000-4000-8000-000000000002',
          courseId: _courseB,
          type: '期中',
          start: DateTime(2026, 10, 20, 9),
          end: DateTime(2026, 10, 20, 11),
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

void main() {
  test('removes target course and its dependent records only', () {
    final original = _profile();
    final updated = CourseDeletionService.removeCourse(original, _courseA);

    expect(original.courses, hasLength(2));
    expect(updated.courses.map((course) => course.id), [_courseB]);
    expect(updated.sessionRules.map((rule) => rule.courseId), [_courseB]);
    expect(updated.exams.map((exam) => exam.courseId), [_courseB]);
    expect(updated.grades.map((grade) => grade.courseId), [_courseB]);
    expect(updated.currentSemesterId, _semesterId);
    expect(updated.revision, original.revision);
    expect(updated.planningRevision, original.planningRevision);
    expect(updated.semesters, original.semesters);
  });

  test('unknown course ID returns the original snapshot', () {
    final original = _profile();

    expect(
      CourseDeletionService.removeCourse(
        original,
        '20000000-0000-4000-8000-000000000099',
      ),
      same(original),
    );
  });
}
