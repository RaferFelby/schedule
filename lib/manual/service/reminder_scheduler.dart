import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_planner.dart';

const manualReminderPayloadPrefix = 'celechron-manual-reminder:v1:';

String reminderNotificationPayload(ReminderPlanEntry entry) =>
    '$manualReminderPayloadPrefix${Uri.encodeComponent(entry.taskId)}:'
    '${entry.scheduledAt.microsecondsSinceEpoch}';

final class PendingReminderNotification {
  const PendingReminderNotification({
    required this.id,
    this.title,
    this.body,
    this.payload,
  });

  final int id;
  final String? title;
  final String? body;
  final String? payload;
}

enum ReminderScheduleStatus {
  scheduled,
  cancelled,
  permissionDenied,
  noReminders,
  unsupportedPlatform,
  failed,
  limitExceeded,
}

final class ReminderScheduleResult {
  const ReminderScheduleResult(
    this.status, {
    this.scheduledCount = 0,
    this.cancelledCount = 0,
  });

  final ReminderScheduleStatus status;
  final int scheduledCount;
  final int cancelledCount;
}

/// Platform boundary kept injectable so permission and scheduling outcomes can
/// be checked without requesting real device permissions in tests.
abstract interface class ReminderNotificationGateway {
  Future<bool> requestPermissions();

  Future<bool?> notificationsEnabled();

  Future<void> schedule(ReminderPlanEntry entry, {required String title});

  Future<void> cancel(int notificationId);

  Future<List<PendingReminderNotification>> pendingNotifications();
}

final class FlutterReminderNotificationGateway
    implements ReminderNotificationGateway {
  FlutterReminderNotificationGateway({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Future<void> _initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const settings = InitializationSettings(
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  @override
  Future<bool> requestPermissions() async {
    await _initialize();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  @override
  Future<bool?> notificationsEnabled() async {
    await _initialize();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final permissions = await ios?.checkPermissions();
    return permissions?.isEnabled;
  }

  @override
  Future<void> schedule(
    ReminderPlanEntry entry, {
    required String title,
  }) async {
    await _initialize();
    await _plugin.zonedSchedule(
      entry.notificationId,
      '任务截止提醒',
      title,
      tz.TZDateTime.from(entry.scheduledAt, tz.UTC),
      const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: reminderNotificationPayload(entry),
    );
  }

  @override
  Future<void> cancel(int notificationId) async {
    await _initialize();
    await _plugin.cancel(notificationId);
  }

  @override
  Future<List<PendingReminderNotification>> pendingNotifications() async {
    await _initialize();
    final pending = await _plugin.pendingNotificationRequests();
    return pending
        .map((request) => PendingReminderNotification(
              id: request.id,
              title: request.title,
              body: request.body,
              payload: request.payload,
            ))
        .toList(growable: false);
  }
}

/// iOS-only bridge from local reminder plans to notification requests.
final class ReminderScheduler {
  ReminderScheduler({
    ReminderNotificationGateway? gateway,
    bool Function()? supportsPlatform,
  })  : _gateway = gateway ?? FlutterReminderNotificationGateway(),
        _supportsPlatform = supportsPlatform ?? (() => Platform.isIOS);

  final ReminderNotificationGateway _gateway;
  final bool Function() _supportsPlatform;

  Future<ReminderScheduleResult> schedule(
    Iterable<ReminderPlanEntry> entries, {
    required Map<String, String> taskTitles,
  }) async {
    final plans = entries.where((entry) {
      final title = taskTitles[entry.taskId];
      return title != null && title.isNotEmpty;
    }).toList(growable: false);
    if (plans.isEmpty) {
      return const ReminderScheduleResult(ReminderScheduleStatus.noReminders);
    }
    if (!_supportsPlatform()) {
      return const ReminderScheduleResult(
        ReminderScheduleStatus.unsupportedPlatform,
      );
    }
    if (!await _gateway.requestPermissions()) {
      return const ReminderScheduleResult(
        ReminderScheduleStatus.permissionDenied,
      );
    }

    var scheduledCount = 0;
    for (final entry in plans) {
      final title = taskTitles[entry.taskId];
      if (title == null) continue;
      await _gateway.schedule(entry, title: title);
      scheduledCount++;
    }
    return ReminderScheduleResult(
      scheduledCount == 0
          ? ReminderScheduleStatus.noReminders
          : ReminderScheduleStatus.scheduled,
      scheduledCount: scheduledCount,
    );
  }

  Future<ReminderScheduleResult> cancel(
    Iterable<ReminderPlanEntry> entries,
  ) async {
    if (!_supportsPlatform()) {
      return const ReminderScheduleResult(
        ReminderScheduleStatus.unsupportedPlatform,
      );
    }
    var cancelledCount = 0;
    for (final entry in entries) {
      await _gateway.cancel(entry.notificationId);
      cancelledCount++;
    }
    return ReminderScheduleResult(
      cancelledCount == 0
          ? ReminderScheduleStatus.noReminders
          : ReminderScheduleStatus.cancelled,
      cancelledCount: cancelledCount,
    );
  }

  Future<ReminderScheduleResult> reconcile(
    Iterable<ReminderPlanEntry> entries, {
    required Map<String, String> taskTitles,
    int maximumPending = 64,
  }) async {
    final desired = entries.where((entry) {
      final title = taskTitles[entry.taskId];
      return title != null && title.isNotEmpty;
    }).toList(growable: false);
    if (!_supportsPlatform()) {
      return ReminderScheduleResult(
        desired.isEmpty
            ? ReminderScheduleStatus.noReminders
            : ReminderScheduleStatus.unsupportedPlatform,
      );
    }
    final pending = await _gateway.pendingNotifications();
    final desiredById = {
      for (final entry in desired) entry.notificationId: entry
    };
    final owned = pending.where((request) {
      return request.payload?.startsWith(manualReminderPayloadPrefix) ?? false;
    }).toList(growable: false);

    final stale = owned.where((request) {
      final entry = desiredById[request.id];
      return entry == null ||
          request.payload != reminderNotificationPayload(entry) ||
          request.title != '任务截止提醒' ||
          request.body != taskTitles[entry.taskId];
    }).toList(growable: false);
    var cancelledCount = 0;
    for (final request in stale) {
      await _gateway.cancel(request.id);
      cancelledCount++;
    }

    if (desired.isEmpty) {
      return ReminderScheduleResult(
        cancelledCount == 0
            ? ReminderScheduleStatus.noReminders
            : ReminderScheduleStatus.cancelled,
        cancelledCount: cancelledCount,
      );
    }

    final notificationsEnabled = await _gateway.notificationsEnabled();
    final hasMissing = desired.any((entry) {
      return !pending.any((request) =>
          request.id == entry.notificationId &&
          request.payload == reminderNotificationPayload(entry) &&
          request.title == '任务截止提醒' &&
          request.body == taskTitles[entry.taskId]);
    });
    if (hasMissing &&
        notificationsEnabled != true &&
        !await _gateway.requestPermissions()) {
      return ReminderScheduleResult(
        ReminderScheduleStatus.permissionDenied,
        cancelledCount: cancelledCount,
      );
    }
    if (notificationsEnabled == false && !hasMissing) {
      return ReminderScheduleResult(
        ReminderScheduleStatus.permissionDenied,
        cancelledCount: cancelledCount,
      );
    }

    var pendingCount = pending.length - cancelledCount;
    var scheduledCount = 0;
    var limitExceeded = false;
    for (final entry in desired) {
      final payload = reminderNotificationPayload(entry);
      final title = taskTitles[entry.taskId]!;
      final existing = pending.any((request) =>
          request.id == entry.notificationId &&
          request.payload == payload &&
          request.title == '任务截止提醒' &&
          request.body == title);
      if (existing) continue;

      final idCollision = pending.any((request) =>
          request.id == entry.notificationId &&
          !(request.payload?.startsWith(manualReminderPayloadPrefix) ?? false));
      if (idCollision) {
        return ReminderScheduleResult(
          ReminderScheduleStatus.failed,
          scheduledCount: scheduledCount,
          cancelledCount: cancelledCount,
        );
      }
      if (pendingCount >= maximumPending) {
        limitExceeded = true;
        continue;
      }

      await _gateway.schedule(entry, title: title);
      scheduledCount++;
      pendingCount++;
    }

    if (limitExceeded) {
      return ReminderScheduleResult(
        ReminderScheduleStatus.limitExceeded,
        scheduledCount: scheduledCount,
        cancelledCount: cancelledCount,
      );
    }
    if (scheduledCount > 0) {
      return ReminderScheduleResult(
        ReminderScheduleStatus.scheduled,
        scheduledCount: scheduledCount,
        cancelledCount: cancelledCount,
      );
    }
    return ReminderScheduleResult(
      cancelledCount == 0
          ? ReminderScheduleStatus.noReminders
          : ReminderScheduleStatus.cancelled,
      cancelledCount: cancelledCount,
    );
  }
}
