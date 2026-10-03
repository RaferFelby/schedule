import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/pigeon/flow_messenger.dart';

import '../model/academic_profile.dart';
import 'manual_calendar_period_adapter.dart';

typedef LocalScheduleSnapshotSender = Future<bool> Function(
    FlowMessage message);
typedef LocalSchedulePeriodReader = Future<List<Period>> Function(
  AcademicProfile profile,
);

/// Publishes one consistent local schedule snapshot to Apple widgets and Watch.
final class LocalScheduleDeviceSyncService {
  const LocalScheduleDeviceSyncService(
    this._repository, {
    LocalScheduleSnapshotSender? sender,
    LocalSchedulePeriodReader? periodReader,
  })  : _sender = sender,
        _periodReader = periodReader;

  final AcademicRepository _repository;
  final LocalScheduleSnapshotSender? _sender;
  final LocalSchedulePeriodReader? _periodReader;

  Future<bool> sync() async {
    final profile = await _repository.read();
    final periods = await (_periodReader?.call(profile) ??
        ManualCalendarPeriodAdapter(_repository).readPeriods(profile));
    final message = FlowMessage(
      revision: profile.revision,
      flowListDto: [
        for (final period in periods)
          if (period.type == PeriodType.classes ||
              period.type == PeriodType.test)
            PeriodDto(
              uid: period.uid,
              type: period.type == PeriodType.classes
                  ? PeriodTypeDto.classes
                  : PeriodTypeDto.test,
              name: period.summary,
              startTime: period.startTime.millisecondsSinceEpoch ~/ 1000,
              endTime: period.endTime.millisecondsSinceEpoch ~/ 1000,
              location: period.location,
            ),
      ],
    );
    return (_sender ?? FlowMessenger().transfer)(message);
  }
}
