import 'dart:convert';

import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/service/local_schedule_device_sync_service.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/pigeon/flow_messenger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sends an empty snapshot with the current academic revision', () async {
    final profile = AcademicProfile(
      schemaVersion: AcademicProfile.supportedSchemaVersion,
      revision: 17,
    );
    FlowMessage? sent;
    final service = LocalScheduleDeviceSyncService(
      AcademicRepository(_MemoryStore(jsonEncode(profile.toJson()))),
      sender: (message) async {
        sent = message;
        return true;
      },
    );

    expect(await service.sync(), isTrue);
    expect(sent?.revision, 17);
    expect(sent?.flowListDto, isEmpty);
  });

  test('maps only classes and exams to Pigeon period DTOs', () async {
    final profile = AcademicProfile(
      schemaVersion: AcademicProfile.supportedSchemaVersion,
      revision: 4,
    );
    final start = DateTime(2026, 10, 5, 8);
    final end = start.add(const Duration(minutes: 45));
    FlowMessage? sent;
    final service = LocalScheduleDeviceSyncService(
      AcademicRepository(_MemoryStore(jsonEncode(profile.toJson()))),
      sender: (message) async {
        sent = message;
        return true;
      },
      periodReader: (_) async => [
        Period(
          uid: 'class-1',
          type: PeriodType.classes,
          startTime: start,
          endTime: end,
          summary: '课程',
          location: '教室',
        ),
        Period(
          uid: 'exam-1',
          type: PeriodType.test,
          startTime: start,
          endTime: end,
          summary: '考试',
        ),
        Period(
          uid: 'virtual-1',
          type: PeriodType.virtual,
          startTime: start,
          endTime: end,
        ),
      ],
    );

    expect(await service.sync(), isTrue);
    expect(sent?.revision, 4);
    expect(sent?.flowListDto, hasLength(2));
    expect(sent!.flowListDto[0]!.type, PeriodTypeDto.classes);
    expect(
        sent!.flowListDto[0]!.startTime, start.millisecondsSinceEpoch ~/ 1000);
    expect(sent!.flowListDto[1]!.type, PeriodTypeDto.test);
  });
}

final class _MemoryStore implements AcademicProfileStore {
  _MemoryStore(this.value);
  String? value;

  @override
  Future<String?> readSnapshot() async => value;

  @override
  Future<void> writeSnapshot(String value) async => this.value = value;
}
