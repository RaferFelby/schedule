import 'package:flutter/cupertino.dart';
import 'package:uuid/uuid.dart';

import '../model/time_slot.dart';
import '../service/pdf_timetable_parser.dart';
import '../service/week_number_parser.dart';

final class PdfTimetableDraftEditor extends StatelessWidget {
  const PdfTimetableDraftEditor({
    super.key,
    required this.course,
    required this.duplicate,
    required this.timeSlots,
    required this.onChanged,
    required this.onRemove,
  });

  final TimetableCourseDraft course;
  final bool duplicate;
  final List<TimeSlot> timeSlots;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    course.name.isEmpty ? '待补全课程' : course.name,
                    style:
                        CupertinoTheme.of(context).textTheme.navTitleTextStyle,
                  ),
                ),
                CupertinoSwitch(
                  value: course.include,
                  onChanged: (value) {
                    course.include = value;
                    onChanged();
                  },
                ),
              ],
            ),
            if (duplicate)
              const Text(
                '疑似与本学期已有课程重复；关闭右侧开关可跳过。',
                style: TextStyle(color: CupertinoColors.systemOrange),
              ),
            _textField('课程名称（必填）', course.name, (value) {
              course.name = value;
              onChanged();
            }),
            _textField('课程号（可选）', course.courseNumber ?? '', (value) {
              course.courseNumber = value;
              onChanged();
            }),
            _textField('学分（可选）', course.credits?.toString() ?? '', (value) {
              final parsed = double.tryParse(value.trim());
              course.creditsInputValid = value.trim().isEmpty ||
                  parsed != null && parsed.isFinite && parsed >= 0;
              course.credits = parsed;
              onChanged();
            }, keyboard: const TextInputType.numberWithOptions(decimal: true)),
            if (!course.creditsInputValid)
              const Text(
                '学分须为不小于零的数字，也可留空。',
                style: TextStyle(color: CupertinoColors.systemRed),
              ),
            _textField('课程教师（可选）', course.teacher ?? '', (value) {
              course.teacher = value;
              onChanged();
            }),
            const SizedBox(height: 8),
            for (final session in course.sessions)
              _SessionEditor(
                key: ValueKey('session-${session.id}'),
                session: session,
                timeSlots: timeSlots,
                onChanged: onChanged,
                onRemove: () {
                  course.sessions.remove(session);
                  onChanged();
                },
              ),
            CupertinoButton(
              key: ValueKey('add-session-${course.id}'),
              padding: EdgeInsets.zero,
              onPressed: () {
                course.sessions
                    .add(TimetableSessionDraft(id: const Uuid().v4()));
                onChanged();
              },
              child: const Text('补充一条上课安排'),
            ),
            CupertinoButton(
              key: ValueKey('remove-course-${course.id}'),
              padding: EdgeInsets.zero,
              onPressed: onRemove,
              child: const Text(
                '移除此课程',
                style: TextStyle(color: CupertinoColors.systemRed),
              ),
            ),
          ],
        ),
      );

  Widget _textField(
    String label,
    String value,
    ValueChanged<String> changed, {
    TextInputType keyboard = TextInputType.text,
  }) =>
      CupertinoTextFormFieldRow(
        key: ValueKey('$label-${course.id}'),
        initialValue: value,
        prefix: SizedBox(width: 132, child: Text(label)),
        keyboardType: keyboard,
        onChanged: changed,
      );
}

final class _SessionEditor extends StatelessWidget {
  const _SessionEditor({
    super.key,
    required this.session,
    required this.timeSlots,
    required this.onChanged,
    required this.onRemove,
  });

  final TimetableSessionDraft session;
  final List<TimeSlot> timeSlots;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border:
              Border.all(color: CupertinoColors.separator.resolveFrom(context)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('上课安排 ${session.isComplete ? '' : '· 待补全'}'),
            Text(_timeSummary(session, timeSlots)),
            _field('星期 1–7', '${session.weekday ?? ''}', (v) {
              session.weekday = int.tryParse(v);
              onChanged();
            }),
            _field('周次，如 1,3,5', session.weekNumbers.join(','), (v) {
              session.weekNumbers = WeekNumberParser.parse(v);
              onChanged();
            }),
            _field('起始节次', '${session.startSlot ?? ''}', (v) {
              session.startSlot = int.tryParse(v);
              onChanged();
            }),
            _field('结束节次', '${session.endSlot ?? ''}', (v) {
              session.endSlot = int.tryParse(v);
              onChanged();
            }),
            _field('本次教师（可选）', session.teacher ?? '', (v) {
              session.teacher = v;
              onChanged();
            }),
            _field('地点（可选）', session.location ?? '', (v) {
              session.location = v;
              onChanged();
            }),
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: onRemove,
                child: const Text(
                  '删除此安排',
                  style: TextStyle(color: CupertinoColors.systemRed),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _field(String label, String value, ValueChanged<String> changed) =>
      CupertinoTextFormFieldRow(
        key: ValueKey('$label-${session.id}'),
        initialValue: value,
        prefix: SizedBox(width: 118, child: Text(label)),
        onChanged: changed,
      );

  static String _timeSummary(
    TimetableSessionDraft session,
    List<TimeSlot> timeSlots,
  ) {
    if (session.startSlot == null || session.endSlot == null) return '节次时间待补全';
    final slots = {for (final slot in timeSlots) slot.ordinal: slot};
    final first = slots[session.startSlot];
    final last = slots[session.endSlot];
    if (first == null || last == null) return '所选节次尚未配置时间';
    return '星期 ${session.weekday ?? '?'} · 第 ${session.startSlot}–${session.endSlot} 节'
        ' · ${_minute(first.startMinute)}–${_minute(last.endMinute)}';
  }

  static String _minute(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
}
