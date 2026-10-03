import 'package:celechron/manual/migration/migration_validator.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validator = ManualMigrationValidator();
  final emptyProfile = AcademicProfile(schemaVersion: 1, revision: 0);

  test('balanced source counts and valid empty candidate have no issues', () {
    final report = validator.validate(
      profile: emptyProfile,
      tasks: [],
      counts: const {
        'semesters': MigrationCount(
          sourceRecords: 3,
          convertedRecords: 2,
          unresolvedRecords: 1,
        ),
      },
    );

    expect(report.issues, isEmpty);
    expect(report.blockingCount, 0);
    expect(report.counts['semesters']!.sourceRecords, 3);
  });

  test('unexplained records are blocking and the discrepancy is reported', () {
    final report = validator.validate(
      profile: emptyProfile,
      tasks: [],
      counts: const {
        'grades': MigrationCount(
          sourceRecords: 4,
          convertedRecords: 2,
          unresolvedRecords: 1,
        ),
      },
    );

    expect(report.blockingCount, 1);
    expect(report.issues.single.code, 'count-mismatch:grades');
    expect(report.issues.single.message, contains('尚有 1 条未解释'));
  });

  test('missing task course reference and duplicate IDs are blocking', () {
    final task = _task(uid: 'same-id', courseId: 'missing-course');
    final report = validator.validate(
      profile: emptyProfile,
      tasks: [task, _task(uid: 'same-id')],
      counts: const {},
    );

    expect(report.blockingCount, 2);
    expect(report.issues.map((issue) => issue.code),
        contains('duplicate-id:task:same-id'));
    expect(report.issues.map((issue) => issue.code),
        contains('missing-task-course:same-id'));
  });
}

Task _task({required String uid, String? courseId}) => Task(
      uid: uid,
      description: '',
      timeSpent: Duration.zero,
      timeNeeded: Duration.zero,
      endTime: DateTime(2025, 1, 2),
      location: '',
      summary: '',
      startTime: DateTime(2025, 1, 1),
      repeatEndsTime: DateTime(2025, 1, 2),
      courseId: courseId,
    );
