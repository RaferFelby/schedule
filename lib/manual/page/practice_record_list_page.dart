import 'package:flutter/cupertino.dart';

import '../data/academic_repository.dart';
import '../model/academic_profile.dart';
import '../model/practice_record.dart';
import '../service/practice_points_calculator.dart';
import 'practice_record_edit_page.dart';

final class PracticeRecordListPage extends StatefulWidget {
  const PracticeRecordListPage({super.key, required this.repository});

  final AcademicRepository repository;

  @override
  State<PracticeRecordListPage> createState() => _PracticeRecordListPageState();
}

final class _PracticeRecordListPageState extends State<PracticeRecordListPage> {
  late Future<List<PracticeRecord>> _records;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _records = _readRecords();
  }

  Future<List<PracticeRecord>> _readRecords() async {
    final profile = await widget.repository.read();
    final records = [...profile.practiceRecords]..sort((left, right) {
        final byDate = right.date.compareTo(left.date);
        return byDate == 0 ? left.id.compareTo(right.id) : byDate;
      });
    return List.unmodifiable(records);
  }

  Future<void> _add() async {
    await _openEditor();
  }

  Future<void> _edit(PracticeRecord record) async {
    await _openEditor(record: record);
  }

  Future<void> _openEditor({PracticeRecord? record}) async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      final saved = await Navigator.of(context).push<bool>(
        CupertinoPageRoute<bool>(
          builder: (_) => PracticeRecordEditPage(
            repository: widget.repository,
            record: record,
          ),
        ),
      );
      if (saved == true && mounted) {
        setState(() {
          _records = _readRecords();
        });
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _delete(PracticeRecord record) async {
    if (_adding) return;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('删除实践记录？'),
        content: const Text('只会删除这条实践记录。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _adding = true);
    try {
      await widget.repository.update((current) {
        if (!current.practiceRecords.any((item) => item.id == record.id)) {
          throw StateError('实践记录已不存在');
        }
        return AcademicProfile(
          schemaVersion: current.schemaVersion,
          revision: current.revision,
          currentSemesterId: current.currentSemesterId,
          semesters: current.semesters,
          timeSlots: current.timeSlots,
          courses: current.courses,
          sessionRules: current.sessionRules,
          exams: current.exams,
          grades: current.grades,
          practiceRecords: current.practiceRecords
              .where((item) => item.id != record.id)
              .toList(),
        );
      });
      if (mounted) {
        setState(() {
          _records = _readRecords();
        });
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          previousPageTitle: '预览',
          middle: const Text('实践记录'),
          trailing: CupertinoButton(
            key: const ValueKey('practice-add'),
            padding: EdgeInsets.zero,
            onPressed: _adding ? null : _add,
            child: const Text('新增'),
          ),
        ),
        child: SafeArea(
          child: FutureBuilder<List<PracticeRecord>>(
            future: _records,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CupertinoActivityIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('读取实践记录失败：${snapshot.error}'));
              }
              final records = snapshot.data!;
              if (records.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _PracticePointsCard(
                      summary: PracticePointsCalculator.calculate(records),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('暂无实践记录')),
                    ),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _PracticePointsCard(
                    summary: PracticePointsCalculator.calculate(records),
                  ),
                  const SizedBox(height: 10),
                  for (final record in records) ...[
                    _PracticeRecordTile(
                      record: record,
                      onEdit: () => _edit(record),
                      onDelete: () => _delete(record),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ),
      );
}

final class _PracticePointsCard extends StatelessWidget {
  const _PracticePointsCard({required this.summary});

  final PracticePointsSummary summary;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('practice-points-summary'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '通过项目合计：${summary.total.toStringAsFixed(1)} · '
          '已计入 ${summary.includedCount} 项',
        ),
      );
}

final class _PracticeRecordTile extends StatelessWidget {
  const _PracticeRecordTile({
    required this.record,
    required this.onEdit,
    required this.onDelete,
  });

  final PracticeRecord record;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Container(
        key: ValueKey('practice-record-${record.id}'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${record.category} · ${record.projectName}'),
            const SizedBox(height: 4),
            Text('${_date(record.date)} · ${record.points} 记点'),
            Text('审核状态：${_status(record.status)}'),
            if (record.note != null) Text('备注：${record.note}'),
            Row(
              children: [
                CupertinoButton(
                  key: ValueKey('practice-edit-${record.id}'),
                  onPressed: onEdit,
                  child: const Text('编辑'),
                ),
                CupertinoButton(
                  key: ValueKey('practice-delete-${record.id}'),
                  onPressed: onDelete,
                  child: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      );

  static String _status(PracticeReviewStatus status) => switch (status) {
        PracticeReviewStatus.pending => '待审核',
        PracticeReviewStatus.approved => '通过',
        PracticeReviewStatus.rejected => '未通过',
      };

  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
