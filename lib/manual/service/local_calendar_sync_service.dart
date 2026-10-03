import '../../model/period.dart';
import 'local_calendar_event_mapping_store.dart';

enum LocalCalendarSyncStatus {
  synced,
  permissionDenied,
  unsupported,
  failed,
  partialFailure,
}

final class LocalCalendarSyncResult {
  const LocalCalendarSyncResult(this.status, {this.eventCount = 0});

  final LocalCalendarSyncStatus status;
  final int eventCount;
}

abstract interface class LocalCalendarGateway {
  bool get isSupported;

  Future<bool> requestPermissions();

  Future<String?> getOrCreateCalendarId();

  Future<String?> writePeriod(
    Period period,
    String calendarId, {
    String? eventId,
  });

  Future<bool> deleteMappedEvent(LocalCalendarEventMapping mapping);
}

/// Explicitly writes preview periods to the device calendar after permission.
final class LocalCalendarSyncService {
  const LocalCalendarSyncService(
    this._gateway, {
    required LocalCalendarEventMappingStore mappings,
  }) : _mappings = mappings;

  final LocalCalendarGateway _gateway;
  final LocalCalendarEventMappingStore _mappings;

  Future<LocalCalendarSyncResult> sync(List<Period> periods) async {
    if (!_gateway.isSupported) {
      return const LocalCalendarSyncResult(
        LocalCalendarSyncStatus.unsupported,
      );
    }
    try {
      if (!await _gateway.requestPermissions()) {
        return const LocalCalendarSyncResult(
          LocalCalendarSyncStatus.permissionDenied,
        );
      }
      final previous = await _mappings.readAll();
      final localPeriods = periods
          .where((period) =>
              period.type == PeriodType.classes ||
              period.type == PeriodType.test)
          .toList();
      final desiredUids = localPeriods.map((period) => period.uid).toSet();
      if (desiredUids.length != localPeriods.length) {
        return const LocalCalendarSyncResult(LocalCalendarSyncStatus.failed);
      }
      final calendarId =
          localPeriods.isEmpty ? null : await _gateway.getOrCreateCalendarId();
      if (localPeriods.isNotEmpty &&
          (calendarId == null || calendarId.isEmpty)) {
        return const LocalCalendarSyncResult(LocalCalendarSyncStatus.failed);
      }

      var successfulWrites = 0;
      var hadFailure = false;
      for (final period in localPeriods) {
        final oldMapping = previous[period.uid];
        final eventId = await _gateway.writePeriod(
          period,
          calendarId!,
          eventId:
              oldMapping?.calendarId == calendarId ? oldMapping?.eventId : null,
        );
        if (eventId == null || eventId.isEmpty) {
          hadFailure = true;
          continue;
        }
        successfulWrites++;
        await _mappings.put(
          period.uid,
          LocalCalendarEventMapping(calendarId: calendarId, eventId: eventId),
        );
        if (oldMapping != null && oldMapping.calendarId != calendarId) {
          if (!await _gateway.deleteMappedEvent(oldMapping)) {
            hadFailure = true;
          }
        }
      }

      for (final entry in previous.entries) {
        if (desiredUids.contains(entry.key)) continue;
        if (await _gateway.deleteMappedEvent(entry.value)) {
          await _mappings.remove(entry.key);
        } else {
          hadFailure = true;
        }
      }
      final status = hadFailure
          ? (successfulWrites == 0
              ? LocalCalendarSyncStatus.failed
              : LocalCalendarSyncStatus.partialFailure)
          : LocalCalendarSyncStatus.synced;
      return LocalCalendarSyncResult(
        status,
        eventCount: successfulWrites,
      );
    } catch (_) {
      return const LocalCalendarSyncResult(LocalCalendarSyncStatus.failed);
    }
  }
}
