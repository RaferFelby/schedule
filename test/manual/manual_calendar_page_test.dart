import 'dart:convert';

import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/local_exam.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/model/session_rule.dart';
import 'package:celechron/manual/model/time_slot.dart';
import 'package:celechron/manual/page/manual_calendar_page.dart';
import 'package:celechron/manual/controller/local_calendar_controller.dart';
import 'package:celechron/manual/service/manual_calendar_period_adapter.dart';
import 'package:celechron/manual/service/local_calendar_ics_exporter.dart';
import 'package:celechron/manual/service/local_calendar_sync_service.dart';
import 'package:celechron/manual/service/local_calendar_event_mapping_store.dart';
import 'package:celechron/model/calendar_to_ical.dart';
import 'package:celechron/model/period.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Store implements AcademicProfileStore {
  _Store(this.value);
  String? value;

  @override
  Future<String?> readSnapshot() async => value;

  @override
  Future<void> writeSnapshot(String encoded) async => value = encoded;
}

AcademicProfile _profile() => AcademicProfile(
      schemaVersion: 1,
      revision: 0,
      semesters: [
        LocalSemester(
          id: '10000000-0000-4000-8000-000000000001',
          name: '学期',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 12, 31),
          weekOneStart: DateTime(2026, 9, 14),
        ),
      ],
      timeSlots: TimeSlot.defaultTemplate(),
      courses: [
        LocalCourse(
          id: '20000000-0000-4000-8000-000000000001',
          semesterId: '10000000-0000-4000-8000-000000000001',
          name: '数据结构',
        ),
      ],
      sessionRules: [
        SessionRule(
          id: '30000000-0000-4000-8000-000000000001',
          courseId: '20000000-0000-4000-8000-000000000001',
          weekday: DateTime.tuesday,
          weekNumbers: [1],
          startSlotOrdinal: 1,
          endSlotOrdinal: 1,
        ),
      ],
      exams: [
        LocalExam(
          id: '40000000-0000-4000-8000-000000000001',
          courseId: '20000000-0000-4000-8000-000000000001',
          type: '期中考试',
          start: DateTime(2026, 9, 15, 13),
          end: DateTime(2026, 9, 15, 14),
          location: '教学楼 201',
        ),
        LocalExam(
          id: '40000000-0000-4000-8000-000000000002',
          courseId: '20000000-0000-4000-8000-000000000001',
          type: '期末考试',
        ),
      ],
    );

final class _CalendarGateway implements LocalCalendarGateway {
  _CalendarGateway({required this.granted});
  final bool granted;
  List<Period>? writtenPeriods;
  final Map<String, String> events = {};
  final Set<String> deletedEvents = {};
  var writes = 0;

  @override
  bool get isSupported => true;

  @override
  Future<bool> requestPermissions() async => granted;

  @override
  Future<String?> getOrCreateCalendarId() async => 'preview-calendar';

  @override
  Future<String?> writePeriod(
    Period period,
    String calendarId, {
    String? eventId,
  }) async {
    writes++;
    writtenPeriods = [...?writtenPeriods, period];
    final id = eventId ?? 'event-${period.uid}';
    events[period.uid] = id;
    return id;
  }

  @override
  Future<bool> deleteMappedEvent(LocalCalendarEventMapping mapping) async {
    deletedEvents.add(mapping.eventId);
    events.removeWhere((_, eventId) => eventId == mapping.eventId);
    return true;
  }
}

final class _CalendarMappings implements LocalCalendarEventMappingStore {
  final Map<String, LocalCalendarEventMapping> values = {};

  @override
  Future<Map<String, LocalCalendarEventMapping>> readAll() async =>
      Map.of(values);

  @override
  Future<void> put(String sourceUid, LocalCalendarEventMapping mapping) async {
    values[sourceUid] = mapping;
  }

  @override
  Future<void> remove(String sourceUid) async => values.remove(sourceUid);
}

void main() {
  test('local calendar descriptions do not depend on legacy semester names',
      () {
    final controller = LocalCalendarController();

    expect(controller.dayDescription(DateTime(2026, 9, 15)), '本地课程');
    expect(controller.getCurrentSemesterDisplayName(), '无学期信息');
  });

  testWidgets('local calendar displays periods adapted from manual data',
      (tester) async {
    final store = _Store(jsonEncode(_profile().toJson()));
    await tester.pumpWidget(MaterialApp(
      home: ManualCalendarPage(
        repository: AcademicRepository(store),
        calendarGateway: _CalendarGateway(granted: true),
        calendarMappings: _CalendarMappings(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('2026-09-15'), findsOneWidget);
    expect(find.text('数据结构'), findsOneWidget);
    expect(find.text('08:00–08:45'), findsOneWidget);
    expect(find.text('数据结构 · 期中考试'), findsOneWidget);
    expect(find.text('13:00–14:00 · 教学楼 201'), findsOneWidget);
    expect(find.text('期末考试'), findsNothing);
    expect(find.byTooltip('导出本地 ICS'), findsOneWidget);
    expect(find.byTooltip('同步到系统日历'), findsOneWidget);
  });

  test('calendar adapter includes timed exams and skips unknown-time exams',
      () async {
    final adapter = ManualCalendarPeriodAdapter(
      AcademicRepository(_Store(jsonEncode(_profile().toJson()))),
    );
    final periods = await adapter.readPeriods();
    final examPeriods =
        periods.where((period) => period.type == PeriodType.test).toList();

    expect(examPeriods, hasLength(1));
    expect(examPeriods.single.uid, 'exam-40000000-0000-4000-8000-000000000001');
    expect(examPeriods.single.startTime, DateTime(2026, 9, 15, 13));
    expect(examPeriods.single.endTime, DateTime(2026, 9, 15, 14));
  });

  test('system calendar sync writes periods only after permission is granted',
      () async {
    final periods = await ManualCalendarPeriodAdapter(AcademicRepository(
      _Store(jsonEncode(_profile().toJson())),
    )).readPeriods();
    final gateway = _CalendarGateway(granted: true);
    final result = await LocalCalendarSyncService(
      gateway,
      mappings: _CalendarMappings(),
    ).sync(periods);

    expect(result.status, LocalCalendarSyncStatus.synced);
    expect(result.eventCount, 2);
    expect(gateway.writtenPeriods, hasLength(2));
    expect(
        gateway.writtenPeriods!.any((period) =>
            period.type == PeriodType.test && period.summary == '数据结构 · 期中考试'),
        isTrue);
  });

  test('repeat sync updates mapped events instead of creating duplicates',
      () async {
    final periods = await ManualCalendarPeriodAdapter(AcademicRepository(
      _Store(jsonEncode(_profile().toJson())),
    )).readPeriods();
    final gateway = _CalendarGateway(granted: true);
    final mappings = _CalendarMappings();
    final service = LocalCalendarSyncService(gateway, mappings: mappings);

    await service.sync(periods);
    final firstIds = Map.of(gateway.events);
    await service.sync(periods);

    expect(gateway.events, firstIds);
    expect(gateway.writes, 4);
    expect(gateway.deletedEvents, isEmpty);
    expect(mappings.values, hasLength(2));
  });

  test('removed local source deletes only its mapped system event', () async {
    final periods = await ManualCalendarPeriodAdapter(AcademicRepository(
      _Store(jsonEncode(_profile().toJson())),
    )).readPeriods();
    final gateway = _CalendarGateway(granted: true);
    final mappings = _CalendarMappings();
    final service = LocalCalendarSyncService(gateway, mappings: mappings);
    await service.sync(periods);
    final removedPeriod = periods.first;
    final removedEventId = gateway.events[removedPeriod.uid]!;
    gateway.events['unmanaged-user-event'] = 'user-event-1';

    await service.sync(
      periods.where((period) => period.uid != removedPeriod.uid).toList(),
    );

    expect(gateway.deletedEvents, {removedEventId});
    expect(gateway.events.values, contains('user-event-1'));
    expect(mappings.values.containsKey(removedPeriod.uid), isFalse);
  });

  test('local ICS export includes classes and timed exams only', () async {
    final ical = await const LocalCalendarIcsExporter().generate(
      repository: AcademicRepository(_Store(jsonEncode(_profile().toJson()))),
    );

    expect(ical, contains('SUMMARY;LANGUAGE=zh-cn:数据结构'));
    expect(ical, contains('SUMMARY;LANGUAGE=zh-cn:数据结构 · 期中考试'));
    expect(ical, isNot(contains('期末考试')));
    expect(RegExp('BEGIN:VEVENT').allMatches(ical), hasLength(2));
  });

  test('ICS text fields escape Chinese punctuation and line breaks', () {
    final ical = CalendarToIcal.generateIcal(
      calendarName: '日历,甲;乙\n丙',
      periods: [
        Period(
          uid: 'period-1',
          summary: '中文,标题;换行\n反斜\\',
          description: '说明,含;分隔\r\n第二\\行',
          location: '教室,201;西',
          startTime: DateTime(2026, 9, 15, 9),
          endTime: DateTime(2026, 9, 15, 10),
        ),
      ],
    );

    expect(ical, contains(r'X-WR-CALNAME:日历\,甲\;乙\n丙'));
    expect(ical, contains(r'SUMMARY;LANGUAGE=zh-cn:中文\,标题\;换行\n反斜\\'));
    expect(ical, contains(r'DESCRIPTION:说明\,含\;分隔\n第二\\行'));
    expect(ical, contains(r'LOCATION:教室\,201\;西'));
  });

  testWidgets(
      'manual calendar sync is explicit and permission denial preserves data',
      (tester) async {
    final encoded = jsonEncode(_profile().toJson());
    final store = _Store(encoded);
    final gateway = _CalendarGateway(granted: false);
    await tester.pumpWidget(MaterialApp(
      home: ManualCalendarPage(
        repository: AcademicRepository(store),
        calendarGateway: gateway,
        calendarMappings: _CalendarMappings(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('同步到系统日历'));
    await tester.pumpAndSettle();

    expect(find.text('未获得日历权限，本地数据未受影响'), findsOneWidget);
    expect(gateway.writtenPeriods, isNull);
    expect(store.value, encoded);
  });
}
