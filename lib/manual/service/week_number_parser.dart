/// Parses complete week expressions without silently dropping invalid tokens.
final class WeekNumberParser {
  static const _numbers =
      r'\d{1,2}(?:\s*[-–—至]\s*\d{1,2})?(?:\s*[,，、]\s*\d{1,2}(?:\s*[-–—至]\s*\d{1,2})?)*';
  static const _parity = r'(?:\s*[（(]?(单|双)[）)]?)?';
  static final _input = RegExp('(?:第\\s*)?($_numbers)\\s*(?:周)?$_parity');
  static final _pdf = RegExp('(?<![0-9])(?:第\\s*)?($_numbers)\\s*周$_parity');

  static bool hasNotation(String text) => _pdf.hasMatch(text);

  static List<int> extract(String text) {
    final weeks = <int>{};
    var end = 0;
    for (final match in _pdf.allMatches(text)) {
      final gap = text.substring(end, match.start);
      if (end == 0
          ? RegExp(r'[,，、]\s*$').hasMatch(gap)
          : !RegExp(r'^\s*[,，、]?\s*$').hasMatch(gap)) {
        return [];
      }
      if (RegExp(r'[-–—至]\s*$').hasMatch(text.substring(0, match.start))) {
        return [];
      }
      final parsed = _expand(match);
      if (parsed == null) return [];
      weeks.addAll(parsed);
      end = match.end;
    }
    if (RegExp(r'^\s*[,，、]\s*[\d\-–—至]').hasMatch(text.substring(end))) {
      return [];
    }
    return weeks.toList()..sort();
  }

  static List<int> parse(String text) {
    final weeks = <int>{};
    var cursor = 0;
    for (final match in _input.allMatches(text)) {
      final gap = text.substring(cursor, match.start);
      if (cursor == 0
          ? gap.trim().isNotEmpty
          : !RegExp(r'^\s*[,，、]\s*$').hasMatch(gap)) {
        return [];
      }
      final parsed = _expand(match);
      if (parsed == null) return [];
      weeks.addAll(parsed);
      cursor = match.end;
    }
    if (text.substring(cursor).trim().isNotEmpty) return [];
    return weeks.toList()..sort();
  }

  static List<int>? _expand(RegExpMatch match) {
    final weeks = <int>[];
    for (final part in match.group(1)!.split(RegExp(r'[,，、]'))) {
      final range = part.trim().split(RegExp(r'\s*[-–—至]\s*'));
      final start = int.parse(range.first);
      final end = int.parse(range.last);
      if (start < 1 || end < start || end > 99) return null;
      for (var week = start; week <= end; week++) {
        if (match.group(2) == '单' && week.isEven ||
            match.group(2) == '双' && week.isOdd) {
          continue;
        }
        weeks.add(week);
      }
    }
    return weeks;
  }
}
