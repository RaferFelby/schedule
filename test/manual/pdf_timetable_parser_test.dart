import 'package:celechron/manual/service/pdf_timetable_parser.dart';
import 'package:celechron/manual/service/pdf_timetable_document.dart';
import 'package:flutter_test/flutter_test.dart';

PdfTextSpan _span(String text, double centerX) => PdfTextSpan(
      text: text,
      x: centerX - 0.025,
      y: 0.2,
      width: 0.05,
      height: 0.015,
    );

PdfTimetablePage _page(int index, int rotation, List<PdfTextSpan> spans) =>
    PdfTimetablePage(
        index: index, rotation: rotation, source: 'pdf', spans: spans);

void main() {
  test('groups repeated course cards and preserves week-specific teachers', () {
    final headers = [
      for (var day = 1; day <= 7; day++)
        _span('星期${'一二三四五六日'[day - 1]}', day * 0.1),
    ];
    final document = PdfTimetableDocument(pages: [
      _page(0, 90, [
        _span('2026-2027学年第1学期', 0.4),
        ...headers,
        _span('合成课程甲', 0.1),
        _span('(1-2节)1-3周,5-8周', 0.1),
        _span('地点:教学楼A-101/教师:合成教师甲/教学班:C12345/学分:4.5', 0.1),
        _span('合成课程甲', 0.1),
        _span('(1-2节)3-7周(单)', 0.1),
        _span('地点:教学楼A-101/教师:合成教师乙/教学班:C12345/学分:4.5', 0.1),
        _span('合成课程乙', 0.2),
        _span('(3-4节)2-5周', 0.2),
        _span('教师:合成教师丙/教学班:C54321/学分:2', 0.2),
      ]),
      _page(1, 270, [
        _span('合成课程甲', 0.1),
        _span('(1-2节)第9周', 0.1),
        _span('教师:合成教师甲/教学班:C12345', 0.1),
      ]),
    ]);

    final draft = PdfTimetableParser.parse(document);
    expect(draft.courses, hasLength(2));
    final calculus =
        draft.courses.singleWhere((course) => course.name == '合成课程甲');
    expect(calculus.courseNumber, 'C12345');
    expect(calculus.credits, 4.5);
    expect(calculus.sessions, hasLength(3));
    expect(calculus.sessions[0].weekday, 1);
    expect(calculus.sessions[0].weekNumbers, [1, 2, 3, 5, 6, 7, 8]);
    expect(calculus.sessions[1].weekNumbers, [3, 5, 7]);
    expect(calculus.sessions[1].teacher, '合成教师乙');
    expect(calculus.sessions[2].weekNumbers, [9]);
    expect(calculus.sessions[2].teacher, '合成教师甲');
    expect(calculus.sessions.first.location, '教学楼A-101');
    expect(draft.termLabel, '2026-2027学年第1学期');
    expect(
        draft.courses
            .singleWhere((course) => course.name == '合成课程乙')
            .sessions
            .single
            .weekday,
        2);
  });

  test('keeps uncertain information incomplete for review', () {
    final page = _page(0, 90, [
      for (var day = 1; day <= 7; day++)
        _span('星期${'一二三四五六日'[day - 1]}', day * 0.1),
      _span('待确认课程', 0.1),
      _span('(5-6节)', 0.1),
    ]);

    final course = PdfTimetableParser.parse(
      PdfTimetableDocument(pages: [page]),
    ).courses.single;
    expect(course.isComplete, isFalse);
    expect(course.sessions.single.weekNumbers, isEmpty);
    expect(course.sessions.single.startSlot, 5);
    expect(course.sessions.single.weekday, 1);
  });

  test('rejects invalid weekday, week and section values as incomplete', () {
    final session = TimetableSessionDraft(
      id: 'invalid',
      weekday: 8,
      weekNumbers: [0],
      startSlot: 5,
      endSlot: 2,
    );
    expect(session.isComplete, isFalse);
  });
}
