import 'dart:convert';

import 'package:hive/hive.dart';

final class LocalCalendarEventMapping {
  const LocalCalendarEventMapping({
    required this.calendarId,
    required this.eventId,
  });

  final String calendarId;
  final String eventId;

  Map<String, String> toJson() => {
        'calendarId': calendarId,
        'eventId': eventId,
      };

  @override
  bool operator ==(Object other) =>
      other is LocalCalendarEventMapping &&
      other.calendarId == calendarId &&
      other.eventId == eventId;

  @override
  int get hashCode => Object.hash(calendarId, eventId);

  static LocalCalendarEventMapping fromJson(Map<String, dynamic> json) =>
      LocalCalendarEventMapping(
        calendarId: json['calendarId'] as String,
        eventId: json['eventId'] as String,
      );
}

abstract interface class LocalCalendarEventMappingStore {
  Future<Map<String, LocalCalendarEventMapping>> readAll();

  Future<void> put(String sourceUid, LocalCalendarEventMapping mapping);

  Future<void> remove(String sourceUid);
}

/// Keeps only the preview calendar's source-to-system event references.
final class HiveLocalCalendarEventMappingStore
    implements LocalCalendarEventMappingStore {
  static const boxName = 'manual-calendar-event-map-v1';

  Future<Box<String>> _box() {
    if (Hive.isBoxOpen(boxName)) {
      return Future.value(Hive.box<String>(boxName));
    }
    return Hive.openBox<String>(boxName);
  }

  @override
  Future<Map<String, LocalCalendarEventMapping>> readAll() async {
    final box = await _box();
    final result = <String, LocalCalendarEventMapping>{};
    for (final key in box.keys.cast<String>()) {
      final encoded = box.get(key);
      if (encoded == null) continue;
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        throw const FormatException('本地日历事件映射格式无效');
      }
      result[key] = LocalCalendarEventMapping.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    }
    return result;
  }

  @override
  Future<void> put(String sourceUid, LocalCalendarEventMapping mapping) async {
    final box = await _box();
    await box.put(sourceUid, jsonEncode(mapping.toJson()));
  }

  @override
  Future<void> remove(String sourceUid) async {
    final box = await _box();
    await box.delete(sourceUid);
  }
}
