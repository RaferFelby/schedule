import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:celechron/manual/migration/course_converter.dart';
import 'package:celechron/manual/migration/semester_converter.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/model/session_rule.dart';
import 'package:celechron/manual/model/time_slot.dart';

final class LegacySessionConversionResult {
  const LegacySessionConversionResult({
    required this.sessionRules,
    required this.unresolvedSessions,
    required this.reviewItems,
  });

  final List<SessionRule> sessionRules;
  final List<Map<String, Object?>> unresolvedSessions;
  final List<String> reviewItems;
}

/// Converts only course-owned legacy sessions into weekly rules.
final class LegacySessionConverter {
  const LegacySessionConverter();

  LegacySessionConversionResult convert({
    required Map<String, Object?> scholar,
    required Iterable<LocalSemester> semesters,
    required Iterable<TimeSlot> timeSlots,
    required Iterable<LegacyCourseIdMapping> courseMappings,
  }) {
    final rules = <SessionRule>[];
    final unresolved = <Map<String, Object?>>[];
    final review = <String>[];
    final semestersById = {for (final value in semesters) value.id: value};
    final slotsByOrdinal = {
      for (final value in timeSlots) value.ordinal: value
    };
    final mappingsByLegacyKey = {
      for (final value in courseMappings) value.legacyKey: value,
    };
    final rawSemesters = scholar['semesters'];
    if (rawSemesters is! List) {
      return const LegacySessionConversionResult(
        sessionRules: [],
        unresolvedSessions: [],
        reviewItems: ['旧 Scholar 数据缺少学期列表，无法转换上课安排'],
      );
    }

    for (var semesterIndex = 0;
        semesterIndex < rawSemesters.length;
        semesterIndex++) {
      final rawSemester = rawSemesters[semesterIndex];
      if (rawSemester is! Map) continue;
      final sourceSemester = Map<String, Object?>.from(rawSemester);
      final sourceSemesterId = LegacySemesterConverter.stableSemesterId(
        sourceSemester,
        semesterIndex,
      );
      final semester = semestersById[sourceSemesterId];
      final rawCourses = sourceSemester['courses'];
      if (rawCourses is! Map) continue;
      for (final courseEntry in rawCourses.entries) {
        final rawCourse = courseEntry.value;
        if (rawCourse is! Map) continue;
        final sourceCourse = Map<String, Object?>.from(rawCourse);
        final sessions = sourceCourse['sessions'];
        if (sessions is! List || sessions.isEmpty) continue;
        final oldCourseId = sourceCourse['id'];
        final mapping = oldCourseId is String
            ? mappingsByLegacyKey[jsonEncode([sourceSemesterId, oldCourseId])]
            : null;
        for (var sessionIndex = 0;
            sessionIndex < sessions.length;
            sessionIndex++) {
          final rawSession = sessions[sessionIndex];
          String? reason;
          Map<String, Object?>? sourceSession;
          if (rawSession is Map) {
            sourceSession = Map<String, Object?>.from(rawSession);
          } else {
            reason = '上课记录格式无效';
          }
          if (reason == null && semester == null) {
            reason = '所属学期日期未转换';
          }
          if (reason == null && mapping == null) {
            reason = '课程缺少可用的旧 ID 映射';
          }
          final session = sourceSession;
          if (reason == null &&
              session != null &&
              session['id'] != null &&
              session['id'] != oldCourseId) {
            reason = '上课记录 ID 与所属课程 ID 不一致';
          }
          if (reason == null && session?['confirmed'] == false) {
            reason = '课程尚未确认';
          }

          final weekday = session?['day'];
          if (reason == null &&
              (weekday is! int || weekday < 1 || weekday > 7)) {
            reason = '星期字段超出 1 至 7';
          }
          final rawTimes = session?['time'];
          final ordinals = <int>[];
          if (reason == null) {
            if (rawTimes is! List ||
                rawTimes.isEmpty ||
                rawTimes.any((value) => value is! int || value < 1)) {
              reason = '节次列表为空或格式无效';
            } else {
              ordinals.addAll(rawTimes.cast<int>());
              for (var index = 1; index < ordinals.length; index++) {
                if (ordinals[index] != ordinals[index - 1] + 1) {
                  reason = '节次不连续，无法表示为单条节次范围';
                  break;
                }
              }
              if (reason == null &&
                  ordinals.toSet().length != ordinals.length) {
                reason = '节次存在重复';
              }
              if (reason == null &&
                  ordinals.any((value) => !slotsByOrdinal.containsKey(value))) {
                reason = '课程引用了未迁移的节次时间';
              }
              if (reason == null &&
                  !_matchesLegacySlots(
                    sourceSemester['sessionToTime'],
                    ordinals,
                    slotsByOrdinal,
                  )) {
                reason = '旧学期节次时间与已迁移模板不一致';
              }
            }
          }

          List<int>? weekNumbers;
          if (reason == null && semester != null && session != null) {
            final result = _weekNumbers(
              session,
              weekday as int,
              semester,
              sourceSemester['dayOfWeekToDays'],
            );
            weekNumbers = result.weeks;
            reason = result.error;
          }
          if (reason != null ||
              semester == null ||
              mapping == null ||
              session == null ||
              weekNumbers == null ||
              weekNumbers.isEmpty) {
            final message = reason ?? '没有可确认的上课周次';
            unresolved.add({
              'semesterIndex': semesterIndex,
              'courseMapKey': courseEntry.key,
              'legacyCourseId': oldCourseId,
              'sessionIndex': sessionIndex,
              'sessionId': session?['id'],
              'reason': message,
            });
            review.add('课程「${sourceCourse['name'] ?? ''}」上课安排待核对：$message');
            continue;
          }

          final location = session['location'];
          if (location != null && location is! String) {
            unresolved.add({
              'semesterIndex': semesterIndex,
              'courseMapKey': courseEntry.key,
              'legacyCourseId': oldCourseId,
              'sessionIndex': sessionIndex,
              'reason': '地点字段格式无效',
            });
            review.add('课程「${sourceCourse['name'] ?? ''}」上课地点格式无效，安排待核对');
            continue;
          }
          final normalizedLocation =
              location is String && location.trim().isNotEmpty
                  ? location
                  : null;
          final id = _stableRuleId(
            semesterIndex,
            mapping.courseId,
            sessionIndex,
            session,
          );
          rules.add(SessionRule(
            id: id,
            courseId: mapping.courseId,
            weekday: weekday as int,
            weekNumbers: weekNumbers,
            startSlotOrdinal: ordinals.first,
            endSlotOrdinal: ordinals.last,
            location: normalizedLocation,
          ));
        }
      }
    }

    return LegacySessionConversionResult(
      sessionRules: List.unmodifiable(rules),
      unresolvedSessions: List.unmodifiable(unresolved),
      reviewItems: List.unmodifiable(review),
    );
  }

  static _WeekNumberResult _weekNumbers(
    Map<String, Object?> session,
    int weekday,
    LocalSemester semester,
    Object? rawCalendar,
  ) {
    final customRepeat = session['customRepeat'];
    if (customRepeat == true) {
      final rawWeeks = session['customRepeatWeeks'];
      if (rawWeeks is! List ||
          rawWeeks.isEmpty ||
          rawWeeks.any((week) => week is! int || week < 1) ||
          rawWeeks.toSet().length != rawWeeks.length) {
        return const _WeekNumberResult.error('自定义周次缺失或格式无效');
      }
      final weeks = rawWeeks.cast<int>()..sort();
      if (weeks
          .any((week) => !_weekDateIsInSemester(week, weekday, semester))) {
        return const _WeekNumberResult.error('自定义周次超出明确学期日期范围');
      }
      return _WeekNumberResult.value(weeks);
    }
    if (customRepeat != false) {
      return const _WeekNumberResult.error('自定义重复标记格式无效');
    }

    final firstHalf = session['firstHalf'];
    final secondHalf = session['secondHalf'];
    final oddWeek = session['oddWeek'];
    final evenWeek = session['evenWeek'];
    if (firstHalf is! bool ||
        secondHalf is! bool ||
        oddWeek is! bool ||
        evenWeek is! bool) {
      return const _WeekNumberResult.error('半学期或单双周标记缺失/格式无效');
    }
    if ((!firstHalf && !secondHalf) || (!oddWeek && !evenWeek)) {
      return const _WeekNumberResult.error('没有启用的半学期或单双周');
    }
    if (rawCalendar is! List) {
      return const _WeekNumberResult.error('旧学期逐日缓存缺失，无法确定周次');
    }
    final selectedWeeks = <int>{};
    for (final half in [if (firstHalf) 0, if (secondHalf) 1]) {
      if (half >= rawCalendar.length || rawCalendar[half] is! List) {
        return const _WeekNumberResult.error('旧学期逐日缓存结构不完整');
      }
      final parityLists = rawCalendar[half] as List;
      for (final parity in [if (oddWeek) 0, if (evenWeek) 1]) {
        if (parity >= parityLists.length || parityLists[parity] is! List) {
          return const _WeekNumberResult.error('旧学期单双周缓存结构不完整');
        }
        final weekdays = parityLists[parity] as List;
        if (weekday >= weekdays.length || weekdays[weekday] is! List) {
          return const _WeekNumberResult.error('旧学期星期日期缓存结构不完整');
        }
        for (final rawDate in weekdays[weekday] as List) {
          if (rawDate is! String) {
            return const _WeekNumberResult.error('旧学期缓存包含无效日期');
          }
          final date = DateTime.tryParse(rawDate);
          if (date == null ||
              date.hour != 0 ||
              date.minute != 0 ||
              date.second != 0 ||
              date.millisecond != 0 ||
              date.microsecond != 0) {
            return const _WeekNumberResult.error('旧学期缓存包含无效日期');
          }
          if (date.weekday != weekday) {
            return const _WeekNumberResult.error('旧学期缓存日期与星期字段不一致');
          }
          if (date.isBefore(semester.startDate) ||
              date.isAfter(semester.endDate)) {
            return const _WeekNumberResult.error('旧学期缓存日期超出学期范围');
          }
          final dayDelta =
              _dateOnly(date).difference(semester.weekOneStart).inDays;
          if (dayDelta < 0 || dayDelta % 7 != weekday - DateTime.monday) {
            return const _WeekNumberResult.error('缓存日期与明确的第一周起点不一致');
          }
          selectedWeeks.add(dayDelta ~/ 7 + 1);
        }
      }
    }
    if (selectedWeeks.isEmpty) {
      return const _WeekNumberResult.error('所选半学期/单双周没有明确日期');
    }
    final weeks = selectedWeeks.toList()..sort();
    return _WeekNumberResult.value(weeks);
  }

  static bool _weekDateIsInSemester(
    int week,
    int weekday,
    LocalSemester semester,
  ) {
    final date = semester.weekOneStart.add(
      Duration(days: (week - 1) * 7 + weekday - DateTime.monday),
    );
    return !date.isBefore(semester.startDate) &&
        !date.isAfter(semester.endDate);
  }

  static bool _matchesLegacySlots(
    Object? rawTemplate,
    List<int> ordinals,
    Map<int, TimeSlot> slotsByOrdinal,
  ) {
    if (rawTemplate is! List) return false;
    for (final ordinal in ordinals) {
      if (ordinal >= rawTemplate.length) return false;
      final rawRange = rawTemplate[ordinal];
      final slot = slotsByOrdinal[ordinal];
      if (rawRange is! List ||
          rawRange.length != 2 ||
          rawRange[0] is! int ||
          rawRange[1] is! int ||
          slot == null ||
          rawRange[0] != slot.startMinute ||
          rawRange[1] != slot.endMinute) {
        return false;
      }
    }
    return true;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _stableRuleId(
    int semesterIndex,
    String courseId,
    int sessionIndex,
    Map<String, Object?> session,
  ) {
    final bytes = sha256
        .convert(utf8.encode(
          'legacy-session:$semesterIndex:$courseId:$sessionIndex:${jsonEncode(session)}',
        ))
        .bytes
        .take(16)
        .toList();
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

final class _WeekNumberResult {
  const _WeekNumberResult._(this.weeks, this.error);

  const _WeekNumberResult.value(List<int> weeks) : this._(weeks, null);

  const _WeekNumberResult.error(String message) : this._(null, message);

  final List<int>? weeks;
  final String? error;
}
