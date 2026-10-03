import 'dart:io';

import 'package:celechron/model/period.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:table_calendar/table_calendar.dart';

import '../controller/local_calendar_controller.dart';
import '../data/academic_repository.dart';
import '../service/manual_calendar_period_adapter.dart';
import '../service/local_calendar_sync_service.dart';
import '../service/local_calendar_event_mapping_store.dart';
import '../service/device_local_calendar_gateway.dart';
import '../service/local_schedule_device_sync_service.dart';
import '../service/local_calendar_ics_exporter.dart';
import 'semester_list_page.dart';

/// Local-only calendar view backed by explicit academic Period data.
final class ManualCalendarPage extends StatefulWidget {
  const ManualCalendarPage({
    super.key,
    required this.repository,
    this.calendarGateway,
    this.calendarMappings,
  });

  final AcademicRepository repository;
  final LocalCalendarGateway? calendarGateway;
  final LocalCalendarEventMappingStore? calendarMappings;

  @override
  State<ManualCalendarPage> createState() => ManualCalendarPageState();
}

final class ManualCalendarPageState extends State<ManualCalendarPage> {
  static const _controllerTag = 'manual-preview-calendar';
  late final LocalCalendarController _controller;
  late final ManualCalendarPeriodAdapter _adapter;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _adapter = ManualCalendarPeriodAdapter(widget.repository);
    _controller = Get.put(
      LocalCalendarController(),
      tag: _controllerTag,
    );
    _refresh();
  }

  @override
  void dispose() {
    Get.delete<LocalCalendarController>(tag: _controllerTag, force: true);
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final wasEmpty = _controller.events.isEmpty;
      final periods = await _adapter.readPeriods();
      if (!mounted) return;
      _controller.replacePeriods(periods);
      if (Platform.isIOS) {
        try {
          await LocalScheduleDeviceSyncService(widget.repository).sync();
        } on Object catch (error) {
          _error = '日程已读取，但设备同步失败：$error';
        }
      }
      if (wasEmpty && periods.isNotEmpty) {
        final firstDay = _controller.chopDate(periods.first.startTime);
        _controller.selectedDay.value = firstDay;
        _controller.focusedDay.value = firstDay;
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> refresh() => _refresh();

  Future<void> _openCourses() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CupertinoApp(
          home: SemesterListPage(repository: widget.repository),
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _exportIcs() => const LocalCalendarIcsExporter().exportFile(
        widget.repository,
        context: context,
      );

  Future<void> _syncToSystemCalendar() async {
    setState(() => _loading = true);
    final LocalCalendarSyncResult result;
    try {
      final periods = await _adapter.readPeriods();
      result = await LocalCalendarSyncService(
        widget.calendarGateway ?? DeviceLocalCalendarGateway(),
        mappings:
            widget.calendarMappings ?? HiveLocalCalendarEventMappingStore(),
      ).sync(periods);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('读取本地日程失败，未同步系统日历')),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    final message = switch (result.status) {
      LocalCalendarSyncStatus.synced => '已同步 ${result.eventCount} 个日历事件',
      LocalCalendarSyncStatus.permissionDenied => '未获得日历权限，本地数据未受影响',
      LocalCalendarSyncStatus.unsupported => '当前仅支持在 iOS 上同步系统日历',
      LocalCalendarSyncStatus.failed => '同步失败，请检查系统日历权限后重试',
      LocalCalendarSyncStatus.partialFailure => '部分日历事件同步失败，重新同步可继续修复',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('日程'),
          actions: [
            IconButton(
              tooltip: '同步到系统日历',
              onPressed: _loading ? null : _syncToSystemCalendar,
              icon: const Icon(Icons.event_available),
            ),
            IconButton(
              tooltip: '导出本地 ICS',
              onPressed: _loading ? null : _exportIcs,
              icon: const Icon(Icons.ios_share),
            ),
            IconButton(
              tooltip: '刷新日程',
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Obx(() {
            final selectedDay = _controller.selectedDay.value;
            final dayPeriods = _controller.getEventsForDay(selectedDay);
            return ListView(
              children: [
                TableCalendar<Period>(
                  firstDay: DateTime(2000),
                  lastDay: DateTime(2100),
                  focusedDay: _controller.focusedDay.value,
                  calendarFormat: _controller.calendarFormat.value,
                  selectedDayPredicate: (day) =>
                      isSameDay(_controller.selectedDay.value, day),
                  eventLoader: _controller.getEventsForDay,
                  onDaySelected: (selected, focused) {
                    _controller.selectedDay.value = selected;
                    _controller.focusedDay.value = focused;
                  },
                  onFormatChanged: (format) =>
                      _controller.calendarFormat.value = format,
                  onPageChanged: (focused) =>
                      _controller.focusedDay.value = focused,
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${selectedDay.year}-${selectedDay.month.toString().padLeft(2, '0')}-${selectedDay.day.toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_loading) const LinearProgressIndicator(),
                if (_error case final error?)
                  ListTile(title: Text('读取日程失败：$error')),
                if (dayPeriods.isEmpty && !_loading)
                  const ListTile(title: Text('当天没有课程')),
                ...dayPeriods.map((period) => ListTile(
                      title: Text(period.summary),
                      subtitle: Text(
                        '${_time(period.startTime)}–${_time(period.endTime)}'
                        '${period.location.isEmpty ? '' : ' · ${period.location}'}',
                      ),
                    )),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.tonalIcon(
                    onPressed: _loading ? null : _openCourses,
                    icon: const Icon(Icons.edit_calendar),
                    label: const Text('管理课程与上课安排'),
                  ),
                ),
              ],
            );
          }),
        ),
      );

  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
