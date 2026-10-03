import 'package:celechron/manual/service/session_conflict_detector.dart';
import 'package:celechron/model/period.dart';
import 'package:flutter_test/flutter_test.dart';

Period _period({
  required String id,
  required String courseId,
  required int startMinute,
  required int endMinute,
}) =>
    Period(
      uid: id,
      fromUid: courseId,
      startTime: DateTime(2026, 9, 1, startMinute ~/ 60, startMinute % 60),
      endTime: DateTime(2026, 9, 1, endMinute ~/ 60, endMinute % 60),
      summary: id,
    );

void main() {
  test('finds overlapping periods from different courses', () {
    final conflicts = SessionConflictDetector.findConflicts(
      proposed: [
        _period(
          id: 'candidate',
          courseId: 'course-a',
          startMinute: 9 * 60,
          endMinute: 10 * 60,
        ),
      ],
      existing: [
        _period(
          id: 'scheduled',
          courseId: 'course-b',
          startMinute: 9 * 60 + 30,
          endMinute: 10 * 60 + 30,
        ),
      ],
    );

    expect(conflicts, hasLength(1));
    expect(conflicts.single.scheduled.summary, 'scheduled');
  });

  test('does not count adjacent periods or same-course periods as conflicts',
      () {
    final proposed = [
      _period(
        id: 'candidate',
        courseId: 'course-a',
        startMinute: 9 * 60,
        endMinute: 10 * 60,
      ),
    ];
    final existing = [
      _period(
        id: 'adjacent',
        courseId: 'course-b',
        startMinute: 10 * 60,
        endMinute: 11 * 60,
      ),
      _period(
        id: 'same-course',
        courseId: 'course-a',
        startMinute: 9 * 60 + 30,
        endMinute: 10 * 60 + 30,
      ),
    ];

    expect(
      SessionConflictDetector.findConflicts(
        proposed: proposed,
        existing: existing,
      ),
      isEmpty,
    );
  });
}
