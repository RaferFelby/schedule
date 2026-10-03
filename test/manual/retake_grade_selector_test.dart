import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/grade_record.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/model/retake_selection_strategy.dart';
import 'package:celechron/manual/service/manual_grade_summary_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

const _firstSemesterId = '10000000-0000-4000-8000-000000000001';
const _secondSemesterId = '10000000-0000-4000-8000-000000000002';
const _firstCourseId = '20000000-0000-4000-8000-000000000001';
const _secondCourseId = '20000000-0000-4000-8000-000000000002';
const _groupId = '30000000-0000-4000-8000-000000000001';

AcademicProfile _profile(RetakeSelectionStrategy strategy) {
  final firstSemester = LocalSemester(
    id: _firstSemesterId,
    name: '第一次修读',
    startDate: DateTime(2026, 9, 1),
    endDate: DateTime(2027, 1, 31),
    weekOneStart: DateTime(2026, 8, 31),
  );
  final secondSemester = LocalSemester(
    id: _secondSemesterId,
    name: '重修',
    startDate: DateTime(2027, 2, 1),
    endDate: DateTime(2027, 6, 30),
    weekOneStart: DateTime(2027, 2, 1),
  );
  final firstCourse = LocalCourse(
    id: _firstCourseId,
    semesterId: firstSemester.id,
    name: '同名课',
    credits: 3,
    retakeGroupId: _groupId,
    retakeStrategy: strategy,
  );
  final secondCourse = LocalCourse(
    id: _secondCourseId,
    semesterId: secondSemester.id,
    name: '同名课',
    credits: 3,
    retakeGroupId: _groupId,
    retakeStrategy: strategy,
  );
  return AcademicProfile(
    schemaVersion: 1,
    revision: 0,
    semesters: [firstSemester, secondSemester],
    // Reverse chronological order to prove source order is irrelevant.
    courses: [secondCourse, firstCourse],
    grades: [
      GradeRecord(
        id: '50000000-0000-4000-8000-000000000002',
        courseId: secondCourse.id,
        status: LocalGradeStatus.recorded,
        method: LocalGradingMethod.directGpa,
        gradePoint: 4,
      ),
      GradeRecord(
        id: '50000000-0000-4000-8000-000000000001',
        courseId: firstCourse.id,
        status: LocalGradeStatus.recorded,
        method: LocalGradingMethod.directGpa,
        gradePoint: 2,
      ),
    ],
  );
}

void main() {
  test('switches between first and highest without mutating source order', () {
    final firstPolicyProfile = _profile(RetakeSelectionStrategy.firstAttempt);
    final highestPolicyProfile = _profile(RetakeSelectionStrategy.highestGpa);

    expect(
      ManualGradeSummaryAdapter.calculate(firstPolicyProfile).gpa.gpa,
      2,
    );
    expect(
      ManualGradeSummaryAdapter.calculate(highestPolicyProfile).gpa.gpa,
      4,
    );
    expect(
      ManualGradeSummaryAdapter.calculate(firstPolicyProfile).gpa.gpa,
      2,
    );
    expect(firstPolicyProfile.courses.map((course) => course.id).toList(),
        [_secondCourseId, _firstCourseId]);
    expect(firstPolicyProfile.grades.map((grade) => grade.courseId).toList(),
        [_secondCourseId, _firstCourseId]);
  });

  test('same-named courses outside a retake group are both counted', () {
    final grouped = _profile(RetakeSelectionStrategy.highestGpa);
    final courses = grouped.courses
        .map((course) => LocalCourse(
              id: course.id,
              semesterId: course.semesterId,
              name: course.name,
              credits: course.credits,
            ))
        .toList();
    final independent = AcademicProfile(
      schemaVersion: grouped.schemaVersion,
      revision: grouped.revision,
      semesters: grouped.semesters,
      courses: courses,
      grades: grouped.grades,
    );

    final summary = ManualGradeSummaryAdapter.calculate(independent).gpa;
    expect(summary.gpa, 3);
    expect(summary.includedCount, 2);
  });
}
