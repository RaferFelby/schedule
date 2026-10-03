import 'package:celechron/manual/data/local_data_error.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/local_exam.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:flutter_test/flutter_test.dart';

const _semesterId = '10000000-0000-4000-8000-000000000001';
const _courseId = '20000000-0000-4000-8000-000000000001';

AcademicProfile _profile({List<LocalExam> exams = const []}) {
  final semester = LocalSemester(
    id: _semesterId,
    name: '暑期班',
    startDate: DateTime(2026, 7, 1),
    endDate: DateTime(2026, 8, 31),
    weekOneStart: DateTime(2026, 6, 29),
  );
  final course = LocalCourse(
    id: _courseId,
    semesterId: _semesterId,
    name: '示例课程',
  );
  return AcademicProfile(
    schemaVersion: 1,
    revision: 3,
    currentSemesterId: _semesterId,
    semesters: [semester],
    courses: [course],
    exams: exams,
  );
}

void main() {
  group('AcademicProfile', () {
    test('versioned snapshot round-trips with ID-only relationships', () {
      final original = _profile(
        exams: [
          LocalExam(
            id: 'exam-1',
            courseId: _courseId,
            type: '期末考试',
          ),
        ],
      );

      final restored = AcademicProfile.fromJson(original.toJson());
      expect(restored.schemaVersion, 1);
      expect(restored.revision, 3);
      expect(restored.currentSemesterId, _semesterId);
      expect(restored.semesters.single.name, '暑期班');
      expect(restored.courses.single.semesterId, _semesterId);
      expect(restored.exams.single.courseId, _courseId);
      expect(restored.toJson(), original.toJson());
    });

    test('older course snapshots default GPA selection to included', () {
      final json = _profile().toJson();
      (json['courses'] as List).single.remove('selectedForGpa');
      (json['courses'] as List).single.remove('retakeGroupId');

      final restored = AcademicProfile.fromJson(json);
      expect(restored.courses.single.selectedForGpa, isTrue);
      expect(restored.courses.single.gpaWeight, 1);
      expect(restored.courses.single.retakeGroupId, isNull);
    });

    test('rejects an invalid course GPA weight', () {
      expect(
        () => LocalCourse(
          id: _courseId,
          semesterId: _semesterId,
          name: '示例课程',
          gpaWeight: -0.5,
        ),
        throwsA(isA<LocalDataValidationError>()),
      );
    });

    test('rejects a schema version this build cannot read', () {
      final json = _profile().toJson()..['schemaVersion'] = 2;
      expect(
        () => AcademicProfile.fromJson(json),
        throwsA(
          isA<LocalDataVersionIncompatibleError>()
              .having((error) => error.storedVersion, 'storedVersion', 2)
              .having((error) => error.supportedVersion, 'supportedVersion', 1),
        ),
      );
    });

    test('rejects an exam that references an absent course', () {
      final orphan = LocalExam(
        id: 'exam-1',
        courseId: '20000000-0000-4000-8000-000000000099',
        type: '期末考试',
      );
      expect(
        () => _profile(exams: [orphan]),
        throwsA(isA<LocalDataValidationError>()),
      );
    });

    test('rejects duplicate entity IDs and retains a stale current ID', () {
      final profile = _profile();
      final duplicate = LocalExam(
        id: _courseId,
        courseId: _courseId,
        type: '期末考试',
      );
      expect(
        () => AcademicProfile(
          schemaVersion: 1,
          revision: 0,
          semesters: profile.semesters,
          courses: profile.courses,
          exams: [duplicate],
        ),
        throwsA(isA<LocalDataValidationError>()),
      );
      final json = profile.toJson()
        ..['currentSemesterId'] = '10000000-0000-4000-8000-000000000099';
      expect(AcademicProfile.fromJson(json).currentSemesterId,
          '10000000-0000-4000-8000-000000000099');
    });
  });
}
