import 'dart:math';

import 'package:flutter/cupertino.dart';

import '../controller/academic_controller.dart';
import '../data/academic_repository.dart';
import '../model/academic_profile.dart';
import '../model/session_rule.dart';
import '../model/time_slot.dart';

/// Editable section timetable, kept separate from course rules and dates.
final class TimeSlotListPage extends StatefulWidget {
  const TimeSlotListPage({super.key, required this.repository});

  final AcademicRepository repository;

  @override
  State<TimeSlotListPage> createState() => _TimeSlotListPageState();
}

final class _TimeSlotListPageState extends State<TimeSlotListPage> {
  late Future<AcademicProfile> _profile;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _profile = widget.repository.read();
  }

  Future<void> _add(AcademicProfile profile, List<TimeSlot> slots) async {
    final nextOrdinal = slots.isEmpty
        ? 1
        : slots.map((slot) => slot.ordinal).reduce((a, b) => max(a, b)) + 1;
    final draft = await _editDialog(ordinal: nextOrdinal);
    if (draft != null) await _save(profile, [...slots, draft]);
  }

  Future<void> _edit(
    AcademicProfile profile,
    List<TimeSlot> slots,
    TimeSlot original,
  ) async {
    final draft = await _editDialog(slot: original);
    if (draft == null) return;
    final updated = slots.map((slot) => slot.id == original.id ? draft : slot);
    await _save(profile, updated.toList());
  }

  Future<TimeSlot?> _editDialog({TimeSlot? slot, int? ordinal}) async {
    return showCupertinoDialog<TimeSlot>(
      context: context,
      builder: (_) => _TimeSlotEditorDialog(
        slot: slot,
        ordinal: ordinal ?? slot!.ordinal,
      ),
    );
  }

  Future<void> _delete(
    AcademicProfile profile,
    List<TimeSlot> slots,
    TimeSlot slot,
  ) async {
    if (_isReferenced(profile.sessionRules, slot)) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('不能删除节次'),
          content: const Text('已有上课规则引用该节次，请先修改或移除规则。'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('删除节次？'),
        content: Text('将删除第 ${slot.ordinal} 节。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            key: const ValueKey('confirm-delete-slot'),
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _save(
          profile, slots.where((value) => value.id != slot.id).toList());
    }
  }

  Future<void> _save(AcademicProfile current, List<TimeSlot> slots) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final controller = AcademicController(
        repository: widget.repository,
        initialProfile: current,
      );
      final saved = await controller.applyUpdate(
        (latest) => AcademicProfile(
          schemaVersion: latest.schemaVersion,
          revision: latest.revision,
          currentSemesterId: latest.currentSemesterId,
          semesters: latest.semesters,
          timeSlots: slots,
          courses: latest.courses,
          sessionRules: latest.sessionRules,
          exams: latest.exams,
          grades: latest.grades,
          practiceRecords: latest.practiceRecords,
        ),
      );
      if (mounted) setState(() => _profile = Future.value(saved));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(
          previousPageTitle: '学期',
          middle: Text('节次表'),
        ),
        child: SafeArea(
          child: Column(
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: CupertinoColors.systemRed),
                  ),
                ),
              Expanded(
                child: FutureBuilder<AcademicProfile>(
                  future: _profile,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CupertinoActivityIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('读取节次失败：${snapshot.error}'));
                    }
                    final profile = snapshot.data!;
                    final slots = [..._effectiveSlots(profile)]..sort(
                        (left, right) => left.ordinal.compareTo(right.ordinal));
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final slot in slots)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SlotRow(
                              slot: slot,
                              busy: _busy,
                              onEdit: () => _edit(profile, slots, slot),
                              onDelete: () => _delete(profile, slots, slot),
                            ),
                          ),
                        CupertinoButton.filled(
                          onPressed: _busy ? null : () => _add(profile, slots),
                          child: const Text('新增节次'),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );

  static List<TimeSlot> _effectiveSlots(AcademicProfile profile) =>
      profile.timeSlots.isEmpty
          ? TimeSlot.defaultTemplate()
          : profile.timeSlots;

  static bool _isReferenced(Iterable<SessionRule> rules, TimeSlot slot) =>
      rules.any(
        (rule) =>
            slot.ordinal >= rule.startSlotOrdinal &&
            slot.ordinal <= rule.endSlotOrdinal,
      );
}

final class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.slot,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final TimeSlot slot;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Container(
        key: ValueKey('slot-row-${slot.ordinal}'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '第 ${slot.ordinal} 节    '
                '${_clock(slot.startMinute)} – ${_clock(slot.endMinute)}',
              ),
            ),
            CupertinoButton(
              key: ValueKey('edit-slot-${slot.ordinal}'),
              onPressed: busy ? null : onEdit,
              child: const Text('编辑'),
            ),
            CupertinoButton(
              key: ValueKey('delete-slot-${slot.ordinal}'),
              onPressed: busy ? null : onDelete,
              child: const Text('删除'),
            ),
          ],
        ),
      );

  static String _clock(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:'
      '${(minute % 60).toString().padLeft(2, '0')}';
}

final class _TimeSlotEditorDialog extends StatefulWidget {
  const _TimeSlotEditorDialog({required this.ordinal, this.slot});

  final int ordinal;
  final TimeSlot? slot;

  @override
  State<_TimeSlotEditorDialog> createState() => _TimeSlotEditorDialogState();
}

final class _TimeSlotEditorDialogState extends State<_TimeSlotEditorDialog> {
  late final TextEditingController _ordinal;
  late final TextEditingController _start;
  late final TextEditingController _end;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ordinal = TextEditingController(text: widget.ordinal.toString());
    _start = TextEditingController(
      text: _clock(widget.slot?.startMinute ?? 480),
    );
    _end = TextEditingController(text: _clock(widget.slot?.endMinute ?? 525));
  }

  @override
  void dispose() {
    _ordinal.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final ordinal = int.parse(_ordinal.text);
      final start = _parseClock(_start.text);
      final end = _parseClock(_end.text);
      final slot = TimeSlot(
        id: widget.slot?.id ?? _newUuid(),
        ordinal: ordinal,
        startMinute: start,
        endMinute: end,
      );
      Navigator.of(context).pop(slot);
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoAlertDialog(
        title: Text(widget.slot == null ? '新增节次' : '编辑节次'),
        content: Column(
          children: [
            _field(
              '节次序号',
              _ordinal,
              'slot-ordinal',
              readOnly: widget.slot != null,
            ),
            _field('开始时间', _start, 'slot-start'),
            _field('结束时间', _end, 'slot-end'),
            if (_error != null) Text(_error!),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: _submit,
            child: const Text('保存'),
          ),
        ],
      );

  Widget _field(String label, TextEditingController controller, String key,
          {bool readOnly = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: CupertinoTextField(
          key: ValueKey(key),
          controller: controller,
          placeholder: label,
          keyboardType: TextInputType.text,
          readOnly: readOnly,
        ),
      );

  static int _parseClock(String value) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    if (match == null) throw const FormatException('时间格式必须为 HH:mm');
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (minute > 59 || hour > 24 || (hour == 24 && minute != 0)) {
      throw const FormatException('时间超出一天范围');
    }
    return hour * 60 + minute;
  }

  static String _clock(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:'
      '${(minute % 60).toString().padLeft(2, '0')}';

  static String _newUuid() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final value =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
}
