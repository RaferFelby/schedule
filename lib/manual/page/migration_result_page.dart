import 'dart:convert';

import 'package:flutter/material.dart';

import '../migration/migration_validator.dart';

/// Read-only summary of a manual migration run with optional correction routes.
final class MigrationResultPage extends StatelessWidget {
  const MigrationResultPage({
    super.key,
    required this.report,
    this.onEditSemesters,
    this.onEditCourses,
    this.onCorrectIssue,
    this.onSkipIssue,
  });

  final MigrationValidationReport report;
  final VoidCallback? onEditSemesters;
  final VoidCallback? onEditCourses;
  final Future<void> Function(String issueCode, Object? correctedRecord)?
      onCorrectIssue;
  final Future<void> Function(String issueCode)? onSkipIssue;

  @override
  Widget build(BuildContext context) {
    final hasBlocking = report.blockingCount > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('迁移结果')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                hasBlocking ? Icons.error_outline : Icons.check_circle_outline,
                color: hasBlocking
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
              title: Text(hasBlocking ? '迁移候选需要处理' : '迁移校验完成'),
              subtitle: Text(
                '待确认 $_totalUnresolved 条 · '
                '需要修复 ${report.blockingCount} 项 · '
                '提示 ${report.reviewCount} 项',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('数据统计', style: Theme.of(context).textTheme.titleMedium),
          for (final entry in report.counts.entries)
            Card(
              child: ListTile(
                title: Text(entry.key),
                subtitle: Text(
                  '来源 ${entry.value.sourceRecords} 条，'
                  '已转换 ${entry.value.convertedRecords} 条，'
                  '待确认 ${entry.value.unresolvedRecords} 条，'
                  '明确忽略 ${entry.value.ignoredRecords} 条',
                ),
              ),
            ),
          if (report.issues.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('校验与提示', style: Theme.of(context).textTheme.titleMedium),
            for (final issue in report.issues)
              Card(
                child: ListTile(
                  leading: Icon(
                    issue.blocking ? Icons.block : Icons.info_outline,
                    color: issue.blocking
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.secondary,
                  ),
                  title: Text(issue.blocking ? '需要修复' : '待核对'),
                  subtitle: Text(issue.message),
                  trailing: _issueActions(context, issue),
                ),
              ),
          ],
          if (onEditSemesters != null || onEditCourses != null) ...[
            const SizedBox(height: 12),
            Text('继续补齐', style: Theme.of(context).textTheme.titleMedium),
            if (onEditSemesters != null)
              OutlinedButton.icon(
                onPressed: onEditSemesters,
                icon: const Icon(Icons.event_note_outlined),
                label: const Text('检查学期日期'),
              ),
            if (onEditCourses != null)
              OutlinedButton.icon(
                onPressed: onEditCourses,
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('检查课程关联'),
              ),
          ],
          const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 24),
            child: Text('旧数据备份会保留；此页面不会自动删除待确认记录。'),
          ),
        ],
      ),
    );
  }

  int get _totalUnresolved => report.counts.values
      .fold(0, (sum, count) => sum + count.unresolvedRecords);

  Widget? _issueActions(
    BuildContext context,
    MigrationValidationIssue issue,
  ) {
    final canSkip =
        onSkipIssue != null && issue.code.startsWith('legacy-unresolved:');
    final canCorrect = onCorrectIssue != null && issue.canCorrect;
    if (!canSkip && !canCorrect) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canCorrect)
          TextButton(
            onPressed: () => _editIssue(context, issue),
            child: const Text('修正'),
          ),
        if (canSkip)
          TextButton(
            onPressed: () => _confirmSkip(context, issue.code),
            child: const Text('跳过'),
          ),
      ],
    );
  }

  Future<void> _editIssue(
    BuildContext context,
    MigrationValidationIssue issue,
  ) async {
    final controller = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(issue.sourceRecord),
    );
    Object? correctedRecord;
    var saved = false;
    String? validationError;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('修正旧记录'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(issue.message),
                const SizedBox(height: 12),
                const Text('编辑这条记录的 JSON；保存后会重新校验，原始备份不变。'),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  minLines: 5,
                  maxLines: 12,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    errorText: validationError,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final decoded = jsonDecode(controller.text);
                  if (issue.sourceRecord is Map && decoded is! Map) {
                    setDialogState(
                        () => validationError = '这条记录必须保持 JSON 对象格式');
                    return;
                  }
                  if (issue.sourceRecord is List && decoded is! List) {
                    setDialogState(
                        () => validationError = '这条记录必须保持 JSON 数组格式');
                    return;
                  }
                  correctedRecord = decoded;
                  saved = true;
                  Navigator.of(dialogContext).pop(true);
                } on FormatException {
                  setDialogState(() => validationError = 'JSON 格式无效');
                }
              },
              child: const Text('保存并重新校验'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (accepted == true && saved) {
      await onCorrectIssue?.call(issue.code, correctedRecord);
    }
  }

  Future<void> _confirmSkip(BuildContext context, String issueCode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('跳过这条旧记录？'),
        content: const Text('这条记录不会导入新数据。原始旧数据备份会保留，可供之后查看。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认跳过'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onSkipIssue?.call(issueCode);
  }
}
