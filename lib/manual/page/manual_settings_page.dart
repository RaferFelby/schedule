import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import '../../debug/manual_preview_task_store.dart';
import '../data/academic_repository.dart';
import '../data/storage_generation.dart';
import '../data/manual_user_preferences_store.dart';
import '../model/manual_user_preferences.dart';
import '../service/backup_service.dart';
import '../service/reminder_scheduler.dart';
import 'backup_preview_page.dart';
import 'semester_list_page.dart';

/// Local data and reminder settings for the manual academic experience.
final class ManualSettingsPage extends StatefulWidget {
  const ManualSettingsPage({
    super.key,
    required this.repository,
    required this.taskBox,
    required this.activeGeneration,
    required this.preferences,
    required this.onPreferencesChanged,
    this.onRestoreBackup,
  });

  final AcademicRepository repository;
  final Box<String> taskBox;
  final StorageGenerationManifest activeGeneration;
  final ManualUserPreferences preferences;
  final ValueChanged<ManualUserPreferences> onPreferencesChanged;
  final Future<void> Function(String backupJson)? onRestoreBackup;

  @override
  State<ManualSettingsPage> createState() => _ManualSettingsPageState();
}

final class _ManualSettingsPageState extends State<ManualSettingsPage> {
  bool _working = false;

  Future<void> _savePreferences(ManualUserPreferences value) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await ManualUserPreferencesStore(widget.activeGeneration).write(value);
      widget.onPreferencesChanged(value);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存设置失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _addWindow() async {
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (start.hour + 1) % 24, minute: start.minute),
    );
    if (!mounted) return;
    if (end == null) return;
    final startMinute = start.hour * 60 + start.minute;
    final endMinute = end.hour * 60 + end.minute;
    if (endMinute <= startMinute ||
        widget.preferences.availableWindows.any(
          (window) => startMinute < window[1] && endMinute > window[0],
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('时段结束需晚于开始，且不能与已有时段重叠')),
      );
      return;
    }
    final windows = [
      ...widget.preferences.availableWindows,
      [startMinute, endMinute]
    ]..sort((a, b) => a[0].compareTo(b[0]));
    await _savePreferences(
        widget.preferences.copyWith(availableWindows: windows));
  }

  String _clock(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

  Future<void> _exportBackup() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final backup = await BackupService(
        academic: widget.repository,
        tasks: ManualPreviewTaskStore(widget.taskBox),
      ).exportJson(settings: widget.preferences.toJson());
      await Clipboard.setData(ClipboardData(text: backup));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('本地备份已复制到剪贴板')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出备份失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _reconcileReminders() async {
    if (_working) return;
    setState(() => _working = true);
    final result =
        await ManualPreviewTaskStore(widget.taskBox).reconcileReminders();
    if (!mounted) return;
    setState(() => _working = false);
    final message = switch (result.status) {
      ReminderScheduleStatus.scheduled => '任务提醒已同步',
      ReminderScheduleStatus.cancelled => '已清理不再需要的任务提醒',
      ReminderScheduleStatus.permissionDenied => '未获得通知权限，任务数据未受影响',
      ReminderScheduleStatus.unsupportedPlatform => '当前平台不支持本地提醒',
      ReminderScheduleStatus.limitExceeded => '系统提醒数量已达上限，部分提醒未安排',
      ReminderScheduleStatus.failed => '提醒同步失败，可稍后重试',
      ReminderScheduleStatus.noReminders => '当前没有需要安排的任务提醒',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _openBackup() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BackupPreviewPage(onRestore: widget.onRestoreBackup),
      ),
    );
  }

  void _openAcademic() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MaterialApp(
          home: SemesterListPage(
            repository: widget.repository,
            previewBox: widget.taskBox,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: ListView(
          children: [
            const ListTile(title: Text('本地学业数据')),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('学期、课程与节次'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openAcademic,
            ),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('备份与恢复'),
              subtitle: const Text('导出到剪贴板，或校验并恢复备份'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openBackup,
            ),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text('复制本地备份'),
              onTap: _working ? null : _exportBackup,
            ),
            const Divider(),
            const ListTile(title: Text('显示与排程')),
            ListTile(
              title: const Text('外观'),
              trailing: DropdownButton<String>(
                value: widget.preferences.theme,
                items: const [
                  DropdownMenuItem(value: 'system', child: Text('跟随系统')),
                  DropdownMenuItem(value: 'light', child: Text('浅色')),
                  DropdownMenuItem(value: 'dark', child: Text('深色')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _savePreferences(widget.preferences.copyWith(theme: value));
                  }
                },
              ),
            ),
            _durationTile('专注时长', widget.preferences.workMinutes, (value) {
              _savePreferences(widget.preferences.copyWith(workMinutes: value));
            }, allowZero: false),
            _durationTile('休息时长', widget.preferences.restMinutes, (value) {
              _savePreferences(widget.preferences.copyWith(restMinutes: value));
            }, allowZero: true),
            const ListTile(title: Text('每日可安排时段')),
            ...widget.preferences.availableWindows
                .asMap()
                .entries
                .map((entry) => ListTile(
                      title: Text(
                          '${_clock(entry.value[0])}–${_clock(entry.value[1])}'),
                      trailing: IconButton(
                        tooltip: '删除时段',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _working
                            ? null
                            : () {
                                final windows = [
                                  ...widget.preferences.availableWindows
                                ]..removeAt(entry.key);
                                _savePreferences(widget.preferences
                                    .copyWith(availableWindows: windows));
                              },
                      ),
                    )),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('添加可用时段'),
              onTap: _working ? null : _addWindow,
            ),
            const Divider(),
            const ListTile(title: Text('提醒')),
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('重新同步任务提醒'),
              onTap: _working ? null : _reconcileReminders,
            ),
            if (_working) const LinearProgressIndicator(),
            ListTile(
              title: const Text('活动数据代次'),
              subtitle: Text(widget.activeGeneration.generationId),
            ),
          ],
        ),
      );

  Widget _durationTile(String title, int value, ValueChanged<int> onChanged,
      {required bool allowZero}) {
    final values = <int>{
      if (allowZero) 0,
      ...List.generate(48, (i) => (i + 1) * 5),
      value
    }.toList()
      ..sort();
    return ListTile(
      title: Text(title),
      trailing: DropdownButton<int>(
        value: value,
        items: values
            .map((minutes) => DropdownMenuItem(
                  value: minutes,
                  child: Text(minutes == 0 ? '关闭' : '$minutes 分钟'),
                ))
            .toList(growable: false),
        onChanged: _working
            ? null
            : (minutes) {
                if (minutes != null) onChanged(minutes);
              },
      ),
    );
  }
}
