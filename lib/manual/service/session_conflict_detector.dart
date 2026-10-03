import 'package:celechron/model/period.dart';

/// Finds overlaps between proposed periods and already scheduled periods.
final class SessionConflictDetector {
  const SessionConflictDetector._();

  static List<SessionConflict> findConflicts({
    required Iterable<Period> proposed,
    required Iterable<Period> existing,
  }) {
    final conflicts = <SessionConflict>[];
    for (final candidate in proposed) {
      for (final scheduled in existing) {
        if (candidate.fromUid == scheduled.fromUid ||
            !candidate.startTime.isBefore(scheduled.endTime) ||
            !candidate.endTime.isAfter(scheduled.startTime)) {
          continue;
        }
        conflicts.add(SessionConflict(candidate, scheduled));
      }
    }
    return List.unmodifiable(conflicts);
  }
}

final class SessionConflict {
  const SessionConflict(this.proposed, this.scheduled);

  final Period proposed;
  final Period scheduled;
}
