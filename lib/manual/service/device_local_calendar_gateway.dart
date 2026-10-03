import 'dart:io';

import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../model/location_mapper.dart';
import '../../model/period.dart';
import 'local_calendar_event_mapping_store.dart';
import 'local_calendar_sync_service.dart';

final class DeviceLocalCalendarGateway implements LocalCalendarGateway {
  DeviceLocalCalendarGateway({DeviceCalendarPlugin? plugin})
      : _plugin = plugin ?? DeviceCalendarPlugin();

  static const calendarName = 'Celechron本地课表';
  final DeviceCalendarPlugin _plugin;

  @override
  bool get isSupported => Platform.isIOS;

  @override
  Future<bool> requestPermissions() async {
    final result = await _plugin.requestPermissions();
    return result.isSuccess && result.data == true;
  }

  @override
  Future<String?> getOrCreateCalendarId() async {
    final calendars = await _plugin.retrieveCalendars();
    if (!calendars.isSuccess) return null;
    final existing = calendars.data!.where((item) => item.name == calendarName);
    final String? calendarId;
    if (existing.isNotEmpty) {
      calendarId = existing.first.id;
    } else {
      final created = await _plugin.createCalendar(calendarName);
      if (!created.isSuccess) return null;
      calendarId = created.data;
    }
    if (calendarId == null || calendarId.isEmpty) return null;
    return calendarId;
  }

  @override
  Future<String?> writePeriod(
    Period period,
    String calendarId, {
    String? eventId,
  }) async {
    final event = Event(calendarId, eventId: eventId)
      ..title = period.type == PeriodType.test
          ? '💯 ${period.summary}'
          : period.summary
      ..description = period.description
      ..start = tz.TZDateTime.from(
        period.startTime,
        tz.getLocation('Asia/Shanghai'),
      )
      ..end = tz.TZDateTime.from(
        period.endTime,
        tz.getLocation('Asia/Shanghai'),
      )
      ..availability = Availability.Busy;
    final location = CalendarLocationMapper.mapForCalendar(period.location);
    if (location.isNotEmpty) event.location = location;
    final result = await _plugin.createOrUpdateEvent(event);
    return result?.isSuccess == true ? result?.data : null;
  }

  @override
  Future<bool> deleteMappedEvent(LocalCalendarEventMapping mapping) async {
    final result = await _plugin.deleteEvent(
      mapping.calendarId,
      mapping.eventId,
    );
    return result.isSuccess && result.data == true;
  }
}
