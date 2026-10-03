import 'pdf_timetable_document.dart';

final class TimetableSessionDraft {
  TimetableSessionDraft({
    required this.id,
    this.weekday,
    List<int> weekNumbers = const [],
    this.startSlot,
    this.endSlot,
    this.teacher,
    this.location,
  }) : weekNumbers = weekNumbers.toList();

  final String id;
  int? weekday;
  List<int> weekNumbers;
  int? startSlot;
  int? endSlot;
  String? teacher;
  String? location;

  bool get isComplete =>
      weekday != null &&
      weekday! >= 1 &&
      weekday! <= 7 &&
      weekNumbers.isNotEmpty &&
      weekNumbers.every((week) => week >= 1) &&
      startSlot != null &&
      endSlot != null &&
      startSlot! >= 1 &&
      endSlot! >= startSlot!;
}

final class TimetableCourseDraft {
  TimetableCourseDraft({
    required this.id,
    required this.name,
    this.courseNumber,
    this.credits,
    this.teacher,
    List<TimetableSessionDraft> sessions = const [],
    this.include = true,
  }) : sessions = sessions.toList();

  final String id;
  String name;
  String? courseNumber;
  double? credits;
  String? teacher;
  final List<TimetableSessionDraft> sessions;
  bool include;

  bool get isComplete =>
      name.trim().isNotEmpty &&
      sessions.isNotEmpty &&
      sessions.every((session) => session.isComplete);
}

final class TimetableImportDraft {
  TimetableImportDraft({required this.courses, this.termLabel});

  final List<TimetableCourseDraft> courses;
  final String? termLabel;

  bool get hasCourses => courses.isNotEmpty;
  bool get isComplete =>
      courses.where((item) => item.include).every((item) => item.isComplete);
}

/// Parses the ZJU timetable's weekday columns, section markers and course cards.
final class PdfTimetableParser {
  static final _sectionPattern =
      RegExp(r'\(?\s*(\d{1,2})\s*[-–—至]\s*(\d{1,2})\s*节\)?');
  static final _weekdayPattern = RegExp(r'星期([一二三四五六日天])');
  static final _weekPattern =
      RegExp(r'(\d{1,2})\s*(?:[-–—至]\s*(\d{1,2})\s*)?周(?:\s*[（(]?(单|双)[）)]?)?');
  static const _weekdayNumbers = {
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '日': 7,
    '天': 7
  };

  static TimetableImportDraft parse(PdfTimetableDocument document) {
    final result = <TimetableCourseDraft>[];
    final coursesByKey = <String, TimetableCourseDraft>{};
    final centers = <double>[];
    final currentNames = <int, String>{};
    final lastSession = <int, TimetableSessionDraft>{};
    final locations = <_SessionLocation>[];
    String? termLabel;
    var serial = 0;

    for (final page in document.pages) {
      final orderedSpans = [...page.spans]..sort((left, right) {
          final byRow = left.y.compareTo(right.y);
          return byRow == 0 ? left.x.compareTo(right.x) : byRow;
        });
      for (var spanIndex = 0; spanIndex < orderedSpans.length; spanIndex++) {
        final span = orderedSpans[spanIndex];
        final term = RegExp(r'\d{4}-\d{4}学年第[一二三四1-4]学期').firstMatch(span.text);
        termLabel ??= term?.group(0);
        final weekday = _weekdayPattern.firstMatch(span.text);
        if (weekday != null) {
          final day = _weekdayNumbers[weekday.group(1)];
          if (day != null) {
            while (centers.length < day) {
              centers.add(double.nan);
            }
            centers[day - 1] = span.x + span.width / 2;
          }
        }
      }
      final validCenters = centers.where((value) => value.isFinite).toList();
      if (validCenters.length != 7) continue;

      for (var spanIndex = 0; spanIndex < orderedSpans.length; spanIndex++) {
        final span = orderedSpans[spanIndex];
        final day = _dayFor(span, centers);
        if (day == null) continue;
        final text = span.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        final section = _sectionPattern.firstMatch(text);
        if (section != null) {
          serial++;
          final inlineName = text.substring(0, section.start).trim();
          final name = _looksLikeCourseName(inlineName)
              ? inlineName
              : currentNames.remove(day);
          final number = _courseNumber(text);
          final key =
              '${_key(name ?? '')}|${number ?? ''}|${name == null ? serial : ''}';
          final course = coursesByKey.putIfAbsent(key, () {
            final created = TimetableCourseDraft(
              id: 'pdf-course-$serial',
              name: name ?? '',
              courseNumber: number,
            );
            result.add(created);
            return created;
          });
          final session = TimetableSessionDraft(
            id: 'pdf-session-$serial',
            weekday: day,
            weekNumbers: _weeks(text),
            startSlot: int.tryParse(section.group(1)!),
            endSlot: int.tryParse(section.group(2)!),
          );
          course.sessions.add(session);
          lastSession[day] = session;
          locations.add(_SessionLocation(
            page.index,
            day,
            span.y,
            spanIndex,
            course,
            session,
          ));
          continue;
        }

        final session = lastSession[day];
        TimetableCourseDraft? course;
        for (final candidate in result) {
          if (candidate.sessions.contains(session)) {
            course = candidate;
            break;
          }
        }
        if (_looksLikeCourseName(text)) {
          currentNames[day] = text.replaceAll(RegExp(r'\s*[(（].*$'), '').trim();
          continue;
        }
        if (session != null && course != null) {
          if (_weekPattern.hasMatch(text) && session.weekNumbers.isEmpty) {
            session.weekNumbers = _weeks(text);
          }
        }
      }

      // PDFKit often emits each course card as independent weekday-column
      // spans. Associate metadata by its position relative to that column's
      // section marker instead of relying on interleaved page text order.
      for (var spanIndex = 0; spanIndex < orderedSpans.length; spanIndex++) {
        final span = orderedSpans[spanIndex];
        final day = _dayFor(span, centers);
        if (day == null) continue;
        final text = span.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        final candidates = locations
            .where(
                (item) => item.pageIndex == page.index && item.weekday == day)
            .toList();
        if (candidates.isEmpty) continue;
        final preceding = candidates
            .where((item) => item.spanIndex < spanIndex)
            .toList()
          ..sort((a, b) => b.spanIndex.compareTo(a.spanIndex));
        if (preceding.isNotEmpty) {
          candidates
            ..clear()
            ..add(preceding.first);
        } else {
          candidates.sort(
              (a, b) => (a.y - span.y).abs().compareTo((b.y - span.y).abs()));
        }
        final nearest = candidates.first;
        if ((nearest.y - span.y).abs() > 0.12) continue;
        if (_weekPattern.hasMatch(text) &&
            nearest.session.weekNumbers.isEmpty) {
          nearest.session.weekNumbers = _weeks(text);
        }
        _readDetails(text, nearest.course, nearest.session);
      }
    }
    return TimetableImportDraft(courses: result, termLabel: termLabel);
  }

  static int? _dayFor(PdfTextSpan span, List<double> centers) {
    final x = span.x + span.width / 2;
    var best = 0;
    var distance = double.infinity;
    for (var index = 0; index < centers.length; index++) {
      if (!centers[index].isFinite) continue;
      final current = (x - centers[index]).abs();
      if (current < distance) {
        distance = current;
        best = index;
      }
    }
    return distance < 0.075 ? best + 1 : null;
  }

  static List<int> _weeks(String text) {
    final weeks = <int>{};
    for (final match in _weekPattern.allMatches(text)) {
      final start = int.parse(match.group(1)!);
      final end = int.tryParse(match.group(2) ?? '') ?? start;
      if (end < start || end - start > 52) continue;
      final parity = match.group(3);
      for (var week = start; week <= end; week++) {
        if (parity == '单' && week.isEven || parity == '双' && week.isOdd) {
          continue;
        }
        weeks.add(week);
      }
    }
    return weeks.toList()..sort();
  }

  static void _readDetails(
      String text, TimetableCourseDraft course, TimetableSessionDraft session) {
    course.courseNumber ??= _courseNumber(text);
    final credits = RegExp(r'学分\s*[:：]\s*(\d+(?:\.\d+)?)').firstMatch(text);
    course.credits ??= double.tryParse(credits?.group(1) ?? '');
    final teacher =
        RegExp(r'教师\s*[:：]\s*([^/／]+)').firstMatch(text)?.group(1)?.trim();
    if (teacher != null && teacher.isNotEmpty) session.teacher = teacher;
    if (RegExp(r'教师\s*[:：]\s*$').hasMatch(text)) return;
    final location = RegExp(r'(?:地点|场地|校区)\s*[:：]\s*([^/／]+)')
        .firstMatch(text)
        ?.group(1)
        ?.trim();
    if (location != null && location.isNotEmpty) session.location = location;
    if (RegExp(r'(?:地点|场地|校区)\s*[:：]\s*$').hasMatch(text)) return;
  }

  static String? _courseNumber(String text) =>
      RegExp(r'\b[A-Z]\d{5}\b').firstMatch(text)?.group(0);

  static bool _looksLikeCourseName(String value) =>
      value.isNotEmpty &&
      !_weekdayPattern.hasMatch(value) &&
      !_sectionPattern.hasMatch(value) &&
      !_weekPattern.hasMatch(value) &&
      !RegExp(r'^(?:\d{1,2}|上午|下午|晚上)$').hasMatch(value) &&
      !RegExp(r'^(?:教师|地点|场地|校区|教学班|学分|总学时|课程学时组成|时间段)\s*[:：]?')
          .hasMatch(value) &&
      !value.contains('实践课程：');

  static String _key(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
}

final class _SessionLocation {
  const _SessionLocation(
    this.pageIndex,
    this.weekday,
    this.y,
    this.spanIndex,
    this.course,
    this.session,
  );

  final int pageIndex;
  final int weekday;
  final double y;
  final int spanIndex;
  final TimetableCourseDraft course;
  final TimetableSessionDraft session;
}
