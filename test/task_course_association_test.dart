import 'package:celechron/database/adapters/deadline_adapter.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

final class _Writer implements BinaryWriter {
  final values = <Object?>[];

  @override
  void writeByte(int byte) => values.add(byte);

  @override
  void write<T>(T value, {bool writeTypeId = true}) => values.add(value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Reader implements BinaryReader {
  _Reader(this.values);

  final List<Object?> values;
  int _index = 0;

  @override
  int readByte() => values[_index++]! as int;

  @override
  dynamic read([int? typeId]) => values[_index++];

  @override
  int get availableBytes => values.length - _index;

  @override
  int get usedBytes => _index;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Task _task({String? courseId}) => Task(
      uid: 'task-1',
      description: '交报告',
      endTime: DateTime(2026, 9, 10, 17),
      startTime: DateTime(2026, 9, 1),
      repeatEndsTime: DateTime(2026, 9, 10),
      summary: '数据库（原课程文本）',
      courseId: courseId,
    );

List<Object?> _legacyTaskFields() => [
      16,
      0,
      'task-old',
      1,
      TaskStatus.running,
      2,
      '旧任务',
      3,
      const Duration(minutes: 10),
      4,
      const Duration(hours: 2),
      5,
      DateTime(2026, 9, 10, 17),
      6,
      '图书馆',
      7,
      '数据库（原课程文本）',
      8,
      false,
      9,
      TaskType.deadline,
      10,
      DateTime(2026, 9, 1),
      11,
      TaskRepeatType.norepeat,
      12,
      1,
      13,
      DateTime(2026, 9, 10),
      14,
      true,
      15,
      null,
    ];

void main() {
  test('Hive adapter round-trips course ID and keeps original summary text',
      () {
    final adapter = DeadlineAdapter();
    final writer = _Writer();
    final original = _task(courseId: '20000000-0000-4000-8000-000000000001')
      ..isCoursework = true
      ..isTimeEstimated = false
      ..reminderEnabled = true
      ..reminderOffset = const Duration(days: 1);
    adapter.write(
      writer,
      original,
    );

    final restored = adapter.read(_Reader(writer.values));
    expect(restored.courseId, '20000000-0000-4000-8000-000000000001');
    expect(restored.isCoursework, isTrue);
    expect(restored.isTimeEstimated, isFalse);
    expect(restored.reminderEnabled, isTrue);
    expect(restored.reminderOffset, const Duration(days: 1));
    expect(restored.summary, '数据库（原课程文本）');
    expect(writer.values.first, 21);
    expect(
      writer.values.sublist(writer.values.length - 10),
      [
        16,
        '20000000-0000-4000-8000-000000000001',
        17,
        true,
        18,
        false,
        19,
        true,
        20,
        const Duration(days: 1),
      ],
    );
    expect(writer.values.last, const Duration(days: 1));
  });

  test('old Hive task fields load without a course association', () {
    final restored = DeadlineAdapter().read(_Reader(_legacyTaskFields()));
    expect(restored.uid, 'task-old');
    expect(restored.courseId, isNull);
    expect(restored.isCoursework, isFalse);
    expect(restored.isTimeEstimated, isTrue);
    expect(restored.reminderEnabled, isFalse);
    expect(restored.reminderOffset, const Duration(days: 1));
    expect(restored.summary, '数据库（原课程文本）');
  });

  test('unestimated coursework does not auto-complete at zero estimate', () {
    final task = _task()
      ..isCoursework = true
      ..isTimeEstimated = false
      ..timeNeeded = Duration.zero
      ..timeSpent = Duration.zero
      ..endTime = DateTime(2030, 1, 1);

    task.refreshStatus();
    expect(task.status, TaskStatus.running);
    expect(task.getProgress(), 0);

    task.updateTimeSpent(const Duration(minutes: 20));
    expect(task.timeSpent, const Duration(minutes: 20));
    expect(task.status, TaskStatus.running);
    task.forceRefreshStatus();
    expect(task.status, TaskStatus.running);
  });

  test('legacy estimated task keeps the prior completion behavior', () {
    final task = _task()
      ..timeNeeded = Duration.zero
      ..timeSpent = Duration.zero;

    task.refreshStatus();
    expect(task.status, TaskStatus.completed);
    expect(task.tracksEstimatedTime, isTrue);
  });

  test('copy operations preserve course ID and can explicitly clear it', () {
    final original = _task(courseId: '20000000-0000-4000-8000-000000000001');
    original.isCoursework = true;
    original.isTimeEstimated = false;
    expect(original.copyWith().courseId, original.courseId);
    expect(original.copyWith().isCoursework, isTrue);
    expect(original.copyWith().isTimeEstimated, isFalse);
    expect(original.copyWith(clearCourseId: true).courseId, isNull);
    final copied = _task()..copy(original);
    expect(copied.courseId, original.courseId);
    expect(copied.isCoursework, isTrue);
    expect(copied.isTimeEstimated, isFalse);
    copied.reset();
    expect(copied.courseId, isNull);
    expect(copied.isCoursework, isFalse);
    expect(copied.isTimeEstimated, isTrue);
  });
}
