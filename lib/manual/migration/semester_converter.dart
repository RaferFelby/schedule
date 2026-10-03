import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/model/time_slot.dart';

/// Converts only explicit, sanitized legacy Scholar fields into candidate data.
/// It never infers term dates from a name, course, or cached calendar.
final class LegacySemesterConversionResult {
  const LegacySemesterConversionResult({
    required this.semesters,
    required this.timeSlots,
    required this.unresolvedSemesters,
    required this.reviewItems,
  });

  final List<LocalSemester> semesters;
  final List<TimeSlot> timeSlots;
  final List<Map<String, Object?>> unresolvedSemesters;
  final List<String> reviewItems;
}

final class LegacySemesterConverter {
  const LegacySemesterConverter();

  LegacySemesterConversionResult convert(Map<String, Object?> scholar) {
    final semesters = <LocalSemester>[];
    final unresolved = <Map<String, Object?>>[];
    final review = <String>[];
    List<TimeSlot>? selectedSlots;
    final rawSemesters = scholar['semesters'];
    if (rawSemesters is! List) {
      return const LegacySemesterConversionResult(
        semesters: [],
        timeSlots: [],
        unresolvedSemesters: [],
        reviewItems: ['旧 Scholar 数据缺少学期列表'],
      );
    }

    for (var index = 0; index < rawSemesters.length; index++) {
      final raw = rawSemesters[index];
      if (raw is! Map) {
        review.add('第 ${index + 1} 条学期记录格式无效，保留在旧备份中待人工核对');
        continue;
      }
      final item = Map<String, Object?>.from(raw);
      final id = stableSemesterId(item, index);
      final sourceName = item['name'];
      final name = sourceName is String ? sourceName : '';
      final start = _date(item['startDate']);
      final end = _date(item['endDate']);
      final weekOne = _date(item['weekOneStart']);
      if (name.trim().isEmpty ||
          start == null ||
          end == null ||
          weekOne == null) {
        unresolved.add({
          'id': id,
          'sourceIndex': index,
          'name': name,
          'courseCount':
              item['courses'] is Map ? (item['courses'] as Map).length : 0,
          'missingFields': [
            if (name.trim().isEmpty) 'name',
            if (start == null) 'startDate',
            if (end == null) 'endDate',
            if (weekOne == null) 'weekOneStart',
          ],
        });
        review.add('学期「${name.isEmpty ? '（空名称）' : name}」缺少明确日期或名称，待补齐');
      } else {
        try {
          semesters.add(LocalSemester(
            id: id,
            name: name,
            startDate: start,
            endDate: end,
            weekOneStart: weekOne,
          ));
        } on Object catch (error) {
          unresolved.add({
            'id': id,
            'sourceIndex': index,
            'name': name,
            'courseCount':
                item['courses'] is Map ? (item['courses'] as Map).length : 0,
            'missingFields': const [],
            'validationError': error.toString(),
          });
          review.add('学期「$name」日期配置无效，待人工核对');
        }
      }

      final slots = _readSlots(item['sessionToTime'], id, review);
      if (slots.isNotEmpty) {
        if (selectedSlots == null) {
          selectedSlots = slots;
        } else if (!_sameSlots(selectedSlots, slots)) {
          review.add('学期「$name」的节次时间与其他学期不同，未合并该配置');
        }
      }
    }
    return LegacySemesterConversionResult(
      semesters: List.unmodifiable(semesters),
      timeSlots: List.unmodifiable(selectedSlots ?? const <TimeSlot>[]),
      unresolvedSemesters: List.unmodifiable(unresolved),
      reviewItems: List.unmodifiable(review),
    );
  }

  static DateTime? _date(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    try {
      final date = DateTime.parse(value);
      return '${date.year.toString().padLeft(4, '0')}-'
                  '${date.month.toString().padLeft(2, '0')}-'
                  '${date.day.toString().padLeft(2, '0')}' ==
              value
          ? date
          : null;
    } on FormatException {
      return null;
    }
  }

  /// Stable UUID shared by semester and dependent-record converters.
  static String stableSemesterId(Map<String, Object?> item, int index) {
    final digest = sha256
        .convert(utf8.encode('legacy-semester:$index:${jsonEncode(item)}'))
        .bytes
        .take(16)
        .toList();
    digest[6] = (digest[6] & 0x0f) | 0x50;
    digest[8] = (digest[8] & 0x3f) | 0x80;
    final hex =
        digest.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  static List<TimeSlot> _readSlots(
    Object? raw,
    String semesterId,
    List<String> review,
  ) {
    if (raw is! List) return const [];
    final slots = <TimeSlot>[];
    for (var index = 0; index < raw.length; index++) {
      final range = raw[index];
      // Legacy semester reserves index zero; its first period is ordinal 1.
      if (index == 0 && range is List && range.isEmpty) continue;
      if (range is! List ||
          range.length != 2 ||
          range[0] is! int ||
          range[1] is! int) {
        if (range is List && range.isNotEmpty) {
          review.add('旧节次索引 $index 格式异常，未导入');
        }
        continue;
      }
      try {
        slots.add(TimeSlot(
          id: '$semesterId-slot-$index',
          ordinal: index,
          startMinute: range[0] as int,
          endMinute: range[1] as int,
        ));
      } on Object {
        review.add('旧节次索引 $index 时间无效，未导入');
      }
    }
    return slots;
  }

  static bool _sameSlots(List<TimeSlot> a, List<TimeSlot> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i].ordinal != b[i].ordinal ||
          a[i].startMinute != b[i].startMinute ||
          a[i].endMinute != b[i].endMinute) {
        return false;
      }
    }
    return true;
  }
}
