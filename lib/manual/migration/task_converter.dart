import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/model/todo.dart';

final class LegacyTaskConversionResult {
  const LegacyTaskConversionResult({
    required this.tasks,
    required this.unresolvedTodos,
    required this.reviewItems,
  });

  /// Includes copied legacy tasks and deterministic candidates from Todo.
  final List<Task> tasks;
  final List<Map<String, Object?>> unresolvedTodos;
  final List<String> reviewItems;
}

/// Converts only sanitized task and Todo projections; it never persists them.
final class LegacyTaskConverter {
  const LegacyTaskConverter();

  LegacyTaskConversionResult convert({
    required Iterable<Task> legacyTasks,
    required Iterable<Todo> todos,
  }) {
    final tasks = <Task>[];
    final review = <String>[];
    for (final legacy in legacyTasks) {
      // copyWith preserves legacy UID, status, timeSpent, and scheduling fields.
      tasks.add(legacy.copyWith());
    }

    final unresolved = <Map<String, Object?>>[];
    final sourceById = <String, String>{};
    final emittedIds = <String>{for (final task in tasks) task.uid};
    for (var index = 0; index < todos.length; index++) {
      final todo = todos.elementAt(index);
      final sourceId = todo.id.trim();
      final name = todo.name.trim();
      final courseText = todo.course.trim();
      final due = todo.endTime;
      if (sourceId.isEmpty) {
        unresolved.add({'sourceIndex': index, 'reason': 'Todo 缺少来源 ID'});
        continue;
      }
      if (name.isEmpty || courseText.isEmpty || due == null) {
        unresolved.add({
          'sourceIndex': index,
          'sourceId': sourceId,
          'reason': due == null ? 'Todo 缺少截止时间' : 'Todo 标题或课程文本缺失',
        });
        continue;
      }
      final signature = jsonEncode({
        'id': sourceId,
        'name': name,
        'course': courseText,
        'endTime': due.toIso8601String(),
      });
      final prior = sourceById[sourceId];
      if (prior != null) {
        if (prior != signature) {
          unresolved.add({
            'sourceIndex': index,
            'sourceId': sourceId,
            'reason': 'Todo 来源 ID 重复但内容不同，未合并',
          });
          review.add('Todo 来源 ID $sourceId 重复且内容不同，待核对');
        }
        continue;
      }
      sourceById[sourceId] = signature;
      final uid = _stableTodoUid(sourceId);
      if (!emittedIds.add(uid)) {
        review.add('Todo 来源 ID $sourceId 与已有任务 ID 冲突，已跳过');
        continue;
      }
      final date = DateTime(due.year, due.month, due.day);
      tasks.add(Task(
        uid: uid,
        status: TaskStatus.running,
        description: '',
        timeSpent: Duration.zero,
        timeNeeded: Duration.zero,
        endTime: due,
        location: '',
        summary: '$name · $courseText',
        isBreakable: true,
        type: TaskType.deadline,
        startTime: date,
        repeatType: TaskRepeatType.norepeat,
        repeatPeriod: 1,
        repeatEndsTime: date,
        blockArrangements: false,
        fromUid: 'legacy-todo:$sourceId',
        isCoursework: true,
        isTimeEstimated: false,
      ));
      review.add('Todo 来源 ID $sourceId 的课程文本保留在任务摘要；旧 schema 无课程 ID，未猜测关联');
    }

    return LegacyTaskConversionResult(
      tasks: List.unmodifiable(tasks),
      unresolvedTodos: List.unmodifiable(unresolved),
      reviewItems: List.unmodifiable(review),
    );
  }

  static String _stableTodoUid(String sourceId) {
    final bytes = sha256
        .convert(utf8.encode('legacy-todo:$sourceId'))
        .bytes
        .take(16)
        .toList();
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
