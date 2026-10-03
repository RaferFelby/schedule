import 'package:flutter/material.dart';

import '../service/backup_preview_service.dart';

/// Read-only validation page for a pasted manual-entry backup.
final class BackupPreviewPage extends StatefulWidget {
  const BackupPreviewPage({
    super.key,
    this.initialJson = '',
    this.onRestore,
  });

  final String initialJson;
  final Future<void> Function(String backupJson)? onRestore;

  @override
  State<BackupPreviewPage> createState() => _BackupPreviewPageState();
}

final class _BackupPreviewPageState extends State<BackupPreviewPage> {
  late final TextEditingController _controller;
  BackupPreviewResult? _result;
  bool _restoring = false;
  String? _restoreError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialJson);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _preview() {
    setState(() {
      _result = const BackupPreviewService().previewJson(_controller.text);
      _restoreError = null;
    });
  }

  Future<void> _restore() async {
    if (_restoring || _result?.isValid != true || widget.onRestore == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('替换当前本地数据？'),
        content: const Text(
          '将先保存当前数据备份，再验证新数据并切换活动代次。旧代次会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _restoring = true;
      _restoreError = null;
    });
    try {
      await widget.onRestore!(_controller.text);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _restoreError = '恢复失败：$error');
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('备份与恢复')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(widget.onRestore == null
                ? '粘贴备份 JSON。此页面只校验和统计，不会写入当前数据。'
                : '粘贴备份 JSON 并校验内容；确认恢复后将替换当前本地数据。'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('backup-json-input'),
              controller: _controller,
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '在此粘贴备份文件内容',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _preview,
              icon: const Icon(Icons.fact_check),
              label: const Text('校验备份'),
            ),
            if (widget.onRestore != null && _result?.isValid == true) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _restoring ? null : _restore,
                icon: const Icon(Icons.restore),
                label: Text(_restoring ? '正在安全恢复…' : '恢复并替换本地数据'),
              ),
            ],
            if (_restoreError case final error?)
              ListTile(
                leading: Icon(
                  Icons.error,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(error),
              ),
            if (_result case final result?) ...[
              const Divider(height: 28),
              ListTile(
                leading: Icon(
                  result.isValid ? Icons.check_circle : Icons.error,
                  color: result.isValid
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
                title: Text(result.isValid ? '备份校验通过' : '发现校验问题'),
                subtitle: Text(
                  '备份版本：${result.backupVersion ?? '未知'} · '
                  '学业 revision：${result.academicRevision ?? '未知'} · '
                  '任务 revision：${result.taskPlanningRevision ?? '未知'}\n'
                  '${result.recordCounts.entries.map((entry) => '${_label(entry.key)}：${entry.value}').join(' · ')}',
                ),
              ),
              for (final entry in result.recordCounts.entries)
                ListTile(
                  key: ValueKey('backup-record-count-${entry.key}'),
                  dense: true,
                  title: Text(_label(entry.key)),
                  trailing: Text('${entry.value}'),
                ),
              for (final error in result.errors)
                ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.warning_amber,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(error),
                ),
            ],
          ],
        ),
      );

  static String _label(String key) => switch (key) {
        'semesters' => '学期',
        'courses' => '课程',
        'sessionRules' => '上课安排',
        'exams' => '考试',
        'grades' => '成绩',
        'practiceRecords' => '实践记录',
        'tasks' => '任务',
        'settings' => '设置项',
        _ => key,
      };
}
