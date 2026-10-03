import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:celechron/model/location_mapper.dart';
import 'package:celechron/model/period.dart';

/// Encodes schedule periods as an iCalendar document without reading app state.
final class IcalPeriodEncoder {
  static String _toISOString(DateTime dateTime) {
    return '${dateTime.year.toString().padLeft(4, '0')}'
        '${dateTime.month.toString().padLeft(2, '0')}'
        '${dateTime.day.toString().padLeft(2, '0')}'
        'T'
        '${dateTime.hour.toString().padLeft(2, '0')}'
        '${dateTime.minute.toString().padLeft(2, '0')}'
        '${dateTime.second.toString().padLeft(2, '0')}';
  }

  static String _escapeText(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\n', r'\n')
      .replaceAll(',', r'\,')
      .replaceAll(';', r'\;');

  static String _generateVEvent(Period period) {
    final buffer = StringBuffer();
    final utcStr =
        '${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.')[0]}Z';
    final startStr = _toISOString(period.startTime);
    final endStr = _toISOString(period.endTime);
    final mappedLocation =
        CalendarLocationMapper.mapForCalendar(period.location);
    final hash = _generateHash(period);

    buffer.writeln('BEGIN:VEVENT');
    buffer.writeln('CLASS:PUBLIC');
    buffer.writeln('CREATED:$utcStr');
    if (period.description.isNotEmpty) {
      buffer.writeln('DESCRIPTION:${_escapeText(period.description)}');
    }
    buffer.writeln('DTSTAMP:$utcStr');
    buffer.writeln('DTSTART;TZID=Asia/Shanghai:$startStr');
    buffer.writeln('DTEND;TZID=Asia/Shanghai:$endStr');
    buffer.writeln('LAST-MODIFIED:$utcStr');
    if (mappedLocation.isNotEmpty) {
      buffer.writeln('LOCATION:${_escapeText(mappedLocation)}');
    }
    buffer.writeln('SEQUENCE:0');
    buffer.writeln('SUMMARY;LANGUAGE=zh-cn:${_escapeText(period.summary)}');
    buffer.writeln('TRANSP:OPAQUE');
    buffer.writeln('UID:$hash');
    buffer.writeln('BEGIN:VALARM');
    buffer.writeln('TRIGGER:-PT15M');
    buffer.writeln('ACTION:DISPLAY');
    buffer.writeln('DESCRIPTION:提醒');
    buffer.writeln('END:VALARM');
    buffer.writeln('END:VEVENT');
    return buffer.toString();
  }

  static String _generateHash(Period period) {
    final mappedLocation =
        CalendarLocationMapper.mapForCalendar(period.location);
    final content =
        '${period.description}${period.summary}$mappedLocation${_toISOString(period.startTime)}';
    return sha1.convert(utf8.encode(content)).toString();
  }

  static String generate({
    required List<Period> periods,
    String calendarName = '浙大课程表',
    bool includeExams = true,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('X-WR-CALNAME:${_escapeText(calendarName)}');
    buffer.writeln('X-APPLE-CALENDAR-COLOR:#2BBFF0');
    buffer.writeln('PRODID:-//Celechron//Course Calendar 1.0//CN');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('METHOD:PUBLISH');
    buffer.writeln('BEGIN:VTIMEZONE');
    buffer.writeln('TZID:Asia/Shanghai');
    buffer.writeln('BEGIN:STANDARD');
    buffer.writeln('DTSTART:16010101T000000');
    buffer.writeln('TZOFFSETFROM:+0800');
    buffer.writeln('TZOFFSETTO:+0800');
    buffer.writeln('END:STANDARD');
    buffer.writeln('END:VTIMEZONE');

    for (final period in periods) {
      if (!includeExams && period.type == PeriodType.test) continue;
      buffer.write(_generateVEvent(period));
    }
    buffer.writeln('END:VCALENDAR');
    return buffer.toString();
  }
}
