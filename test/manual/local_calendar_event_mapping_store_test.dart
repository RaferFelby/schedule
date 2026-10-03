import 'dart:io';

import 'package:celechron/manual/service/local_calendar_event_mapping_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('calendar-event-map-');
    Hive.init(directory.path);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('mapping survives store recreation and deletes only selected source',
      () async {
    final store = HiveLocalCalendarEventMappingStore();
    const first = LocalCalendarEventMapping(
      calendarId: 'calendar-1',
      eventId: 'event-1',
    );
    const second = LocalCalendarEventMapping(
      calendarId: 'calendar-1',
      eventId: 'event-2',
    );
    await store.put('source-1', first);
    await store.put('source-2', second);
    await Hive.close();

    final reopened = HiveLocalCalendarEventMappingStore();
    expect(await reopened.readAll(), {'source-1': first, 'source-2': second});
    await reopened.remove('source-1');

    expect(await HiveLocalCalendarEventMappingStore().readAll(), {
      'source-2': second,
    });
  });
}
