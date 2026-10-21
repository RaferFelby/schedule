import 'pdf_timetable_document.dart';
import 'week_number_parser.dart';

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
  bool creditsInputValid = true;

  bool get isComplete =>
      creditsInputValid &&
      (credits == null || credits!.isFinite && credits! >= 0) &&
      name.trim().isNotEmpty &&
      sessions.isNotEmpty &&
      sessions.every((session) => session.isComplete);
}

final class TimetableImportDraft {
  TimetableImportDraft({
    required this.courses,
    this.termLabel,
    this.warnings = const [],
  });

  final List<TimetableCourseDraft> courses;
  final String? termLabel;
  final List<String> warnings;

  bool get hasCourses => courses.isNotEmpty;
  bool get isComplete =>
      courses.where((item) => item.include).every((item) => item.isComplete);
}

/// Parses the ZJU timetable's weekday columns, section markers and course cards.
final class PdfTimetableParser {
  static final _sectionPattern = RegExp(
    r'[（(]?\s*(\d{1,2})(?:\s*[-–—至]\s*(\d{1,2}))?\s*节[）)]?',
  );
  static final _weekdayPattern = RegExp(r'星期([一二三四五六日天])');
  static const _weekdayNumbers = {
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '日': 7,
    '天': 7,
  };

  static TimetableImportDraft parse(PdfTimetableDocument document) {
    final result = <TimetableCourseDraft>[];
    final warnings = <String>[];
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
      if (validCenters.length != 7) {
        warnings.add('第 ${page.index + 1} 页未能确认星期列，请对照 PDF 手动补录该页课程。');
        continue;
      }

      for (var spanIndex = 0; spanIndex < orderedSpans.length; spanIndex++) {
        final span = orderedSpans[spanIndex];
        final day = _dayFor(span, centers);
        if (day == null) continue;
        final text = span.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        final section = _sectionPattern.firstMatch(text);
        if (section != null) {
          final missingStart =
              RegExp(r'[-–—至]\s*$').hasMatch(text.substring(0, section.start));
          serial++;
          final inlineName = text.substring(0, section.start).trim();
          final name = _looksLikeCourseName(inlineName)
              ? inlineName
              : currentNames.remove(day);
          final number = _courseNumber(text);
          final course = TimetableCourseDraft(
            id: 'pdf-course-$serial',
            name: name ?? '',
            courseNumber: number,
          );
          result.add(course);
          final session = TimetableSessionDraft(
            id: 'pdf-session-$serial',
            weekday: day,
            weekNumbers: _weeks(text),
            startSlot: missingStart ? null : int.tryParse(section.group(1)!),
            endSlot: int.parse(section.group(2) ?? section.group(1)!),
          );
          course.sessions.add(session);
          lastSession[day] = session;
          locations.add(
            _SessionLocation(
              page.index,
              day,
              span.y,
              spanIndex,
              course,
              session,
            ),
          );
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
          if (WeekNumberParser.hasNotation(text) &&
              session.weekNumbers.isEmpty) {
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
              (item) => item.pageIndex == page.index && item.weekday == day,
            )
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
            (a, b) => (a.y - span.y).abs().compareTo((b.y - span.y).abs()),
          );
        }
        final nearest = candidates.first;
        if ((nearest.y - span.y).abs() > 0.12) continue;
        if (WeekNumberParser.hasNotation(text) &&
            nearest.session.weekNumbers.isEmpty) {
          nearest.session.weekNumbers = _weeks(text);
        }
        _readDetails(text, nearest.course, nearest.session);
      }
    }
    final grouped = <String, TimetableCourseDraft>{};
    final courses = <TimetableCourseDraft>[];
    for (final course in result) {
      final key = '${_key(course.name)}|${course.courseNumber ?? ''}';
      final existing = course.name.isEmpty ? null : grouped[key];
      if (existing == null) {
        grouped[key] = course;
        courses.add(course);
      } else {
        existing.sessions.addAll(course.sessions);
        existing.credits ??= course.credits;
      }
    }
    return TimetableImportDraft(
      courses: courses,
      termLabel: termLabel,
      warnings: warnings,
    );
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

  static List<int> _weeks(String text) => WeekNumberParser.extract(text);

  static void _readDetails(
    String text,
    TimetableCourseDraft course,
    TimetableSessionDraft session,
  ) {
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
      RegExp(r'[A-Za-z\u3400-\u9fff]').hasMatch(value) &&
      !_weekdayPattern.hasMatch(value) &&
      !_sectionPattern.hasMatch(value) &&
      !WeekNumberParser.hasNotation(value) &&
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
