import 'dart:convert';

import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/grade_record.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/local_exam.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/model/session_rule.dart';
import 'package:celechron/manual/model/time_slot.dart';
import 'package:celechron/manual/page/semester_list_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Store implements AcademicProfileStore {
  _Store([this.value]);

  String? value;

  @override
  Future<String?> readSnapshot() async => value;

  @override
  Future<void> writeSnapshot(String encoded) async => value = encoded;
}

AcademicProfile _profile() => AcademicProfile(
      schemaVersion: 1,
      revision: 0,
      semesters: [
        LocalSemester(
          id: '10000000-0000-4000-8000-000000000001',
          name: '秋季学期',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2027, 1, 31),
          weekOneStart: DateTime(2026, 8, 31),
        ),
        LocalSemester(
          id: '10000000-0000-4000-8000-000000000002',
          name: '春季学期',
          startDate: DateTime(2027, 2, 1),
          endDate: DateTime(2027, 6, 30),
          weekOneStart: DateTime(2027, 2, 1),
        ),
        LocalSemester(
          id: '10000000-0000-4000-8000-000000000003',
          name: '空学期',
          startDate: DateTime(2027, 7, 1),
          endDate: DateTime(2027, 8, 31),
          weekOneStart: DateTime(2027, 6, 28),
        ),
      ],
      courses: [
        LocalCourse(
          id: '20000000-0000-4000-8000-000000000001',
          semesterId: '10000000-0000-4000-8000-000000000001',
          name: '同名课程',
          credits: 2,
          teacher: '张老师',
        ),
        LocalCourse(
          id: '20000000-0000-4000-8000-000000000002',
          semesterId: '10000000-0000-4000-8000-000000000002',
          name: '同名课程',
        ),
      ],
    );

AcademicProfile _profileWithRules() {
  final profile = _profile();
  return AcademicProfile(
    schemaVersion: profile.schemaVersion,
    revision: profile.revision,
    semesters: profile.semesters,
    timeSlots: TimeSlot.defaultTemplate(),
    courses: profile.courses,
    sessionRules: [
      SessionRule(
        id: '30000000-0000-4000-8000-000000000001',
        courseId: profile.courses.first.id,
        weekday: DateTime.tuesday,
        weekNumbers: [1, 2],
        startSlotOrdinal: 1,
        endSlotOrdinal: 1,
        location: '教学楼 101',
      ),
    ],
  );
}

AcademicProfile _profileWithOverlappingRules() {
  final base = _profileWithRules();
  final additionalCourse = LocalCourse(
    id: '20000000-0000-4000-8000-000000000003',
    semesterId: base.semesters.first.id,
    name: '冲突课程',
  );
  return AcademicProfile(
    schemaVersion: base.schemaVersion,
    revision: base.revision,
    semesters: base.semesters,
    timeSlots: base.timeSlots,
    courses: [...base.courses, additionalCourse],
    sessionRules: [
      ...base.sessionRules,
      SessionRule(
        id: '30000000-0000-4000-8000-000000000002',
        courseId: additionalCourse.id,
        weekday: DateTime.tuesday,
        weekNumbers: [1],
        startSlotOrdinal: 1,
        endSlotOrdinal: 1,
      ),
    ],
  );
}

AcademicProfile _profileWithExam() {
  final base = _profile();
  return AcademicProfile(
    schemaVersion: base.schemaVersion,
    revision: base.revision,
    semesters: base.semesters,
    courses: base.courses,
    exams: [
      LocalExam(
        id: '40000000-0000-4000-8000-000000000001',
        courseId: base.courses.first.id,
        type: '期中考试',
        start: DateTime(2026, 10, 1, 9),
        end: DateTime(2026, 10, 1, 11),
      ),
    ],
  );
}

AcademicProfile _profileWithGrade() {
  final base = _profile();
  return AcademicProfile(
    schemaVersion: base.schemaVersion,
    revision: base.revision,
    semesters: base.semesters,
    courses: base.courses,
    grades: [
      GradeRecord(
        id: '50000000-0000-4000-8000-000000000001',
        courseId: base.courses.first.id,
        status: LocalGradeStatus.recorded,
        method: LocalGradingMethod.directGpa,
        gradePoint: 4,
        isMajor: false,
      ),
    ],
  );
}

void main() {
  group('CourseListPage', () {
    Future<void> openFirstCourse(WidgetTester tester, _Store store) async {
      await tester.pumpWidget(CupertinoApp(
        key: UniqueKey(),
        home: SemesterListPage(repository: AcademicRepository(store)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey(
          'semester-courses-10000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(
          const ValueKey('course-20000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
    }

    testWidgets('filters same-named courses by the selected semester',
        (tester) async {
      final store = _Store(jsonEncode(_profile().toJson()));
      await tester.pumpWidget(
        CupertinoApp(
            home: SemesterListPage(repository: AcademicRepository(store))),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          const ValueKey(
              'semester-courses-10000000-0000-4000-8000-000000000002'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('同名课程'), findsOneWidget);
      expect(find.text('教师：未填写'), findsOneWidget);
      expect(find.text('学分：未填写'), findsOneWidget);
      expect(find.text('教师：张老师'), findsNothing);
    });

    testWidgets('shows an empty state for a semester without courses',
        (tester) async {
      final store = _Store(jsonEncode(_profile().toJson()));
      await tester.pumpWidget(
        CupertinoApp(
            home: SemesterListPage(repository: AcademicRepository(store))),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          const ValueKey(
              'semester-courses-10000000-0000-4000-8000-000000000003'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('这个学期还没有课程'), findsOneWidget);
    });

    testWidgets('opens details with non-interactive unfinished sections',
        (tester) async {
      final profile = _profile();
      final store = _Store(jsonEncode(profile.toJson()));
      await tester.pumpWidget(
        CupertinoApp(
            home: SemesterListPage(repository: AcademicRepository(store))),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          const ValueKey(
              'semester-courses-10000000-0000-4000-8000-000000000001'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
            const ValueKey('course-20000000-0000-4000-8000-000000000001')),
      );
      await tester.pumpAndSettle();

      expect(find.text('课程详情'), findsOneWidget);
      expect(find.text('课程名称：同名课程'), findsOneWidget);
      expect(find.text('教师：张老师'), findsOneWidget);
      expect(find.text('尚未添加上课安排'), findsOneWidget);
      expect(find.text('尚无考试记录'), findsOneWidget);
      expect(find.text('尚无成绩记录'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('尚未添加上课安排'),
          matching: find.byType(CupertinoButton),
        ),
        findsNothing,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('同名课程'), findsOneWidget);
    });

    testWidgets('shows dates expanded from the selected course rules',
        (tester) async {
      final profile = _profileWithRules();
      final store = _Store(jsonEncode(profile.toJson()));
      await tester.pumpWidget(
        CupertinoApp(
          home: SemesterListPage(repository: AcademicRepository(store)),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          const ValueKey(
              'semester-courses-10000000-0000-4000-8000-000000000001'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('course-20000000-0000-4000-8000-000000000001'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2026-09-01 08:00–08:45 · 教学楼 101'), findsOneWidget);
      expect(find.text('2026-09-08 08:00–08:45 · 教学楼 101'), findsOneWidget);
      expect(find.text('尚未添加上课安排'), findsNothing);
    });

    testWidgets('creates a weekly rule and immediately refreshes the detail',
        (tester) async {
      final profile = _profile();
      final store = _Store(jsonEncode(profile.toJson()));
      await tester.pumpWidget(
        CupertinoApp(
          home: SemesterListPage(repository: AcademicRepository(store)),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          const ValueKey(
              'semester-courses-10000000-0000-4000-8000-000000000001'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('course-20000000-0000-4000-8000-000000000001'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-add-rule')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('rule-weekday')),
        '2',
      );
      await tester.enterText(
        find.byKey(const ValueKey('rule-weeks')),
        '1,2',
      );
      await tester.enterText(
        find.byKey(const ValueKey('rule-location')),
        '教学楼 101',
      );
      tester.testTextInput.hide();
      await tester.pump();
      await tester.drag(
        find.byType(ListView).last,
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rule-save')));
      await tester.pumpAndSettle();

      final saved = AcademicProfile.fromJson(
        jsonDecode(store.value!) as Map<String, dynamic>,
      );
      expect(saved.revision, 1);
      expect(saved.sessionRules, hasLength(1));
      expect(saved.sessionRules.single.courseId, profile.courses.first.id);
      expect(saved.sessionRules.single.weekNumbers, [1, 2]);
      expect(find.text('2026-09-01 08:00–08:45 · 教学楼 101'), findsOneWidget);
      expect(find.text('2026-09-08 08:00–08:45 · 教学楼 101'), findsOneWidget);
    });

    testWidgets('week shortcuts save an explicit even-week set',
        (tester) async {
      final profile = _profile();
      final store = _Store(jsonEncode(profile.toJson()));
      await tester.pumpWidget(
        CupertinoApp(
          home: SemesterListPage(repository: AcademicRepository(store)),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey(
          'semester-courses-10000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(
          const ValueKey('course-20000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-add-rule')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('rule-range-end')), '6');
      tester.testTextInput.hide();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rule-weeks-range')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rule-weeks-even')));
      await tester.pump();
      expect(find.byKey(const ValueKey('rule-weeks')), findsOneWidget);
      expect(
          tester
              .widget<CupertinoTextField>(
                find.byKey(const ValueKey('rule-weeks')),
              )
              .controller!
              .text,
          '2,4,6');

      await tester.drag(
        find.byType(ListView).last,
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rule-save')));
      await tester.pumpAndSettle();
      final reopened = await AcademicRepository(store).read();
      expect(reopened.sessionRules.single.weekNumbers, [2, 4, 6]);
    });

    testWidgets('editing a rule replaces its occurrences without changing ID',
        (tester) async {
      final profile = _profileWithRules();
      final store = _Store(jsonEncode(profile.toJson()));
      await tester.pumpWidget(CupertinoApp(
        home: SemesterListPage(repository: AcademicRepository(store)),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey(
          'semester-courses-10000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(
          const ValueKey('course-20000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey(
          'course-rule-edit-30000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<CupertinoTextField>(
                find.byKey(const ValueKey('rule-weeks')),
              )
              .controller!
              .text,
          '1,2');
      await tester.enterText(find.byKey(const ValueKey('rule-weeks')), '3');
      tester.testTextInput.hide();
      await tester.pump();
      await tester.drag(find.byType(ListView).last, const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rule-save')));
      await tester.pumpAndSettle();

      final updated = await AcademicRepository(store).read();
      expect(updated.sessionRules.single.id,
          '30000000-0000-4000-8000-000000000001');
      expect(updated.sessionRules.single.weekNumbers, [3]);
      expect(find.text('2026-09-01 08:00–08:45 · 教学楼 101'), findsNothing);
      expect(find.text('2026-09-08 08:00–08:45 · 教学楼 101'), findsNothing);
      expect(find.text('2026-09-15 08:00–08:45 · 教学楼 101'), findsOneWidget);
    });

    testWidgets('warns about a conflict but allows saving the rule',
        (tester) async {
      final profile = _profileWithOverlappingRules();
      final store = _Store(jsonEncode(profile.toJson()));
      await tester.pumpWidget(CupertinoApp(
        home: SemesterListPage(repository: AcademicRepository(store)),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey(
          'semester-courses-10000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(
          const ValueKey('course-20000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey(
          'course-rule-edit-30000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      final verticalScrollables = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('session-conflicts')),
        300,
        scrollable: verticalScrollables.last,
      );
      expect(find.byKey(const ValueKey('session-conflicts')), findsOneWidget);
      expect(find.textContaining('仍可保存'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('rule-save')),
        300,
        scrollable: verticalScrollables.last,
      );
      await tester.tap(find.byKey(const ValueKey('rule-save')));
      await tester.pumpAndSettle();

      final saved = await AcademicRepository(store).read();
      expect(saved.revision, 1);
      expect(saved.sessionRules, hasLength(2));
    });

    testWidgets('adds a dated exam and shows it in course details',
        (tester) async {
      final store = _Store(jsonEncode(_profile().toJson()));
      await openFirstCourse(tester, store);
      await tester.tap(find.byKey(const ValueKey('course-add-exam')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('exam-type')), '期中考试');
      await tester.tap(find.byKey(const ValueKey('exam-time-unknown')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('exam-start')), '2026-10-01 09:00');
      await tester.enterText(
          find.byKey(const ValueKey('exam-end')), '2026-10-01 11:00');
      await tester.enterText(
          find.byKey(const ValueKey('exam-location')), '教学楼 101');
      await tester.enterText(find.byKey(const ValueKey('exam-seat')), 'A12');
      tester.testTextInput.hide();
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('exam-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('exam-save')));
      await tester.pumpAndSettle();

      final saved = await AcademicRepository(store).read();
      expect(saved.exams, hasLength(1));
      expect(saved.exams.single.type, '期中考试');
      expect(saved.exams.single.start, DateTime(2026, 10, 1, 9));
      expect(saved.exams.single.end, DateTime(2026, 10, 1, 11));
      expect(saved.exams.single.location, '教学楼 101');
      expect(saved.exams.single.seat, 'A12');
      expect(
        find.text('期中考试 · 2026-10-01 09:00–11:00 · 教学楼 101 · A12'),
        findsOneWidget,
      );
    });

    testWidgets('saves explicitly unknown exam time without a date',
        (tester) async {
      final store = _Store(jsonEncode(_profile().toJson()));
      await openFirstCourse(tester, store);
      await tester.tap(find.byKey(const ValueKey('course-add-exam')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('exam-type')), '期末考试');
      tester.testTextInput.hide();
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('exam-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('exam-save')));
      await tester.pumpAndSettle();

      final saved = await AcademicRepository(store).read();
      expect(saved.exams, hasLength(1));
      expect(saved.exams.single.start, isNull);
      expect(saved.exams.single.end, isNull);
      expect(find.text('期末考试 · 时间未定'), findsOneWidget);
    });

    testWidgets('canceling a new exam leaves the snapshot unchanged',
        (tester) async {
      final store = _Store(jsonEncode(_profile().toJson()));
      await openFirstCourse(tester, store);
      await tester.tap(find.byKey(const ValueKey('course-add-exam')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('exam-type')), '不保存');
      await tester.tap(find.byKey(const ValueKey('exam-cancel')));
      await tester.pumpAndSettle();

      final unchanged = await AcademicRepository(store).read();
      expect(unchanged.revision, 0);
      expect(unchanged.exams, isEmpty);
    });

    testWidgets('editing an exam preserves ID and replaces its time',
        (tester) async {
      final store = _Store(jsonEncode(_profileWithExam().toJson()));
      await openFirstCourse(tester, store);
      final editButton = find.byKey(const ValueKey(
          'course-exam-edit-40000000-0000-4000-8000-000000000001'));
      await tester.ensureVisible(editButton);
      await tester.pumpAndSettle();
      await tester.tap(editButton);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('exam-start')), '2026-10-02 10:00');
      await tester.enterText(
          find.byKey(const ValueKey('exam-end')), '2026-10-02 12:00');
      tester.testTextInput.hide();
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('exam-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('exam-save')));
      await tester.pumpAndSettle();

      final updated = await AcademicRepository(store).read();
      expect(updated.exams, hasLength(1));
      expect(updated.exams.single.id, '40000000-0000-4000-8000-000000000001');
      expect(updated.exams.single.start, DateTime(2026, 10, 2, 10));
      expect(updated.exams.single.end, DateTime(2026, 10, 2, 12));
      expect(find.textContaining('2026-10-01'), findsNothing);
      expect(find.textContaining('2026-10-02 10:00–12:00'), findsOneWidget);
    });

    testWidgets('deleting an exam leaves the course and supports cancel',
        (tester) async {
      final store = _Store(jsonEncode(_profileWithExam().toJson()));
      await openFirstCourse(tester, store);
      final deleteButton = find.byKey(const ValueKey(
          'course-exam-delete-40000000-0000-4000-8000-000000000001'));
      await tester.ensureVisible(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      expect(find.text('删除考试记录？'), findsOneWidget);
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      expect((await AcademicRepository(store).read()).exams, hasLength(1));

      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();
      final deleted = await AcademicRepository(store).read();
      expect(deleted.exams, isEmpty);
      expect(deleted.courses, hasLength(2));
      expect(find.text('尚无考试记录'), findsOneWidget);
    });

    testWidgets('saves a decimal percentage without invented GPA',
        (tester) async {
      final store = _Store(jsonEncode(_profile().toJson()));
      await openFirstCourse(tester, store);
      final addButton = find.byKey(const ValueKey('course-add-grade'));
      await tester.ensureVisible(addButton);
      await tester.pumpAndSettle();
      await tester.tap(addButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grade-not-recorded')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('grade-value')), '89.5');
      tester.testTextInput.hide();
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('grade-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grade-save')));
      await tester.pumpAndSettle();

      final saved = await AcademicRepository(store).read();
      expect(saved.grades, hasLength(1));
      expect(saved.grades.single.status, LocalGradeStatus.recorded);
      expect(saved.grades.single.rawScore, 89.5);
      expect(saved.grades.single.gradePoint, isNull);
      expect(find.text('百分制：89.5 分'), findsOneWidget);
      expect(find.text('GPA 暂无可用换算'), findsOneWidget);
      expect(find.text('获得学分：未确定'), findsOneWidget);
    });

    testWidgets('edits a grade in place and preserves its stable ID',
        (tester) async {
      final store = _Store(jsonEncode(_profileWithGrade().toJson()));
      await openFirstCourse(tester, store);
      final editButton = find.byKey(const ValueKey(
          'course-grade-edit-50000000-0000-4000-8000-000000000001'));
      await tester.ensureVisible(editButton);
      await tester.pumpAndSettle();
      await tester.tap(editButton);
      await tester.pumpAndSettle();
      expect(find.text('编辑成绩'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('grade-value')), '3');
      tester.testTextInput.hide();
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('grade-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grade-save')));
      await tester.pumpAndSettle();

      final updated = await AcademicRepository(store).read();
      expect(updated.grades, hasLength(1));
      expect(updated.grades.single.id, '50000000-0000-4000-8000-000000000001');
      expect(updated.grades.single.courseId, updated.courses.first.id);
      expect(updated.grades.single.gradePoint, 3);
      expect(find.text('直接绩点：绩点 3.0'), findsOneWidget);
      expect(find.text('计入 GPA（3.0）'), findsOneWidget);
    });

    testWidgets('course selection persists and limits the displayed GPA',
        (tester) async {
      final store = _Store(jsonEncode(_profileWithGrade().toJson()));
      await openFirstCourse(tester, store);
      final selection = find.byKey(const ValueKey('course-gpa-selection'));
      await tester.scrollUntilVisible(
        selection,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(selection);
      await tester.pumpAndSettle();

      final saved = await AcademicRepository(store).read();
      expect(saved.courses.first.selectedForGpa, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining('GPA：4.0'), findsNothing);
      expect(find.textContaining('GPA 暂无结果'), findsNWidgets(4));
    });

    testWidgets('deletes only the confirmed grade and keeps the course',
        (tester) async {
      final store = _Store(jsonEncode(_profileWithGrade().toJson()));
      await openFirstCourse(tester, store);
      final deleteButton = find.byKey(const ValueKey(
          'course-grade-delete-50000000-0000-4000-8000-000000000001'));
      await tester.ensureVisible(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      expect(find.text('删除成绩记录？'), findsOneWidget);
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      expect((await AcademicRepository(store).read()).grades, hasLength(1));

      await tester.ensureVisible(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();
      final deleted = await AcademicRepository(store).read();
      expect(deleted.grades, isEmpty);
      expect(deleted.courses, hasLength(2));
      expect(find.text('尚无成绩记录'), findsOneWidget);
      expect(find.byKey(const ValueKey('course-add-grade')), findsOneWidget);
    });

    testWidgets('saves zero as recorded and direct GPA as a GPA value',
        (tester) async {
      final zeroStore = _Store(jsonEncode(_profile().toJson()));
      await openFirstCourse(tester, zeroStore);
      await tester
          .ensureVisible(find.byKey(const ValueKey('course-add-grade')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-add-grade')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grade-not-recorded')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('grade-value')), '0');
      tester.testTextInput.hide();
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('grade-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grade-save')));
      await tester.pumpAndSettle();
      final zero = await AcademicRepository(zeroStore).read();
      expect(zero.grades.single.status, LocalGradeStatus.recorded);
      expect(zero.grades.single.rawScore, 0);
      expect(find.text('百分制：0.0 分'), findsOneWidget);
      expect(find.text('获得学分：0.0'), findsOneWidget);

      final gpaStore = _Store(jsonEncode(_profile().toJson()));
      await openFirstCourse(tester, gpaStore);
      await tester
          .ensureVisible(find.byKey(const ValueKey('course-add-grade')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-add-grade')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grade-not-recorded')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('绩点'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('grade-value')), '4.0');
      tester.testTextInput.hide();
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('grade-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grade-save')));
      await tester.pumpAndSettle();
      final direct = await AcademicRepository(gpaStore).read();
      expect(direct.grades.single.method, LocalGradingMethod.directGpa);
      expect(direct.grades.single.gradePoint, 4);
      expect(find.text('计入 GPA（4.0）'), findsOneWidget);
    });

    testWidgets('saves a not-recorded status separately from numeric zero',
        (tester) async {
      final store = _Store(jsonEncode(_profile().toJson()));
      await openFirstCourse(tester, store);
      await tester
          .ensureVisible(find.byKey(const ValueKey('course-add-grade')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-add-grade')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('grade-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grade-save')));
      await tester.pumpAndSettle();

      final saved = await AcademicRepository(store).read();
      expect(saved.grades.single.status, LocalGradeStatus.notRecorded);
      expect(saved.grades.single.rawScore, isNull);
      expect(saved.grades.single.gradePoint, isNull);
      expect(find.text('成绩尚未录入'), findsOneWidget);
    });

    testWidgets('rejects an out-of-range score and cancel does not save',
        (tester) async {
      final store = _Store(jsonEncode(_profile().toJson()));
      await openFirstCourse(tester, store);
      await tester
          .ensureVisible(find.byKey(const ValueKey('course-add-grade')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-add-grade')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grade-not-recorded')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('grade-value')), '101');
      tester.testTextInput.hide();
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('grade-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('grade-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('0 到 100'), findsOneWidget);
      expect((await AcademicRepository(store).read()).grades, isEmpty);

      await tester.tap(find.byKey(const ValueKey('grade-cancel')));
      await tester.pumpAndSettle();
      expect((await AcademicRepository(store).read()).revision, 0);
      expect((await AcademicRepository(store).read()).grades, isEmpty);
    });

    testWidgets('deleting a rule keeps other rules and their occurrences',
        (tester) async {
      final base = _profileWithRules();
      final second = SessionRule(
        id: '30000000-0000-4000-8000-000000000002',
        courseId: base.courses.first.id,
        weekday: DateTime.wednesday,
        weekNumbers: [1],
        startSlotOrdinal: 1,
        endSlotOrdinal: 1,
        location: '实验楼',
      );
      final profile = AcademicProfile(
        schemaVersion: base.schemaVersion,
        revision: base.revision,
        semesters: base.semesters,
        timeSlots: base.timeSlots,
        courses: base.courses,
        sessionRules: [...base.sessionRules, second],
      );
      final store = _Store(jsonEncode(profile.toJson()));
      await tester.pumpWidget(CupertinoApp(
        home: SemesterListPage(repository: AcademicRepository(store)),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey(
          'semester-courses-10000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(
          const ValueKey('course-20000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey(
          'course-rule-delete-30000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();

      final updated = await AcademicRepository(store).read();
      expect(updated.sessionRules.map((rule) => rule.id), [second.id]);
      expect(find.text('2026-09-01 08:00–08:45 · 教学楼 101'), findsNothing);
      expect(find.text('2026-09-02 08:00–08:45 · 实验楼'), findsOneWidget);
    });

    testWidgets('cancelling and restoring one occurrence keeps the rule',
        (tester) async {
      final profile = _profileWithRules();
      final store = _Store(jsonEncode(profile.toJson()));
      await tester.pumpWidget(CupertinoApp(
        home: SemesterListPage(repository: AcademicRepository(store)),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey(
          'semester-courses-10000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(
          const ValueKey('course-20000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey(
          'course-rule-cancel-30000000-0000-4000-8000-000000000001-20260908')));
      await tester.pumpAndSettle();

      var updated = await AcademicRepository(store).read();
      expect(
          updated.sessionRules.single.cancelledDates, [DateTime(2026, 9, 8)]);
      expect(find.text('2026-09-01 08:00–08:45 · 教学楼 101'), findsOneWidget);
      expect(find.text('2026-09-08 08:00–08:45 · 教学楼 101'), findsNothing);
      expect(find.text('2026-09-08 · 已停课'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey(
          'course-rule-restore-30000000-0000-4000-8000-000000000001-20260908')));
      await tester.pumpAndSettle();
      updated = await AcademicRepository(store).read();
      expect(updated.sessionRules.single.cancelledDates, isEmpty);
      expect(find.text('2026-09-08 08:00–08:45 · 教学楼 101'), findsOneWidget);
      expect(find.text('2026-09-08 · 已停课'), findsNothing);
    });

    testWidgets('reschedules one occurrence and restores its original date',
        (tester) async {
      final profile = _profileWithRules();
      final store = _Store(jsonEncode(profile.toJson()));
      await tester.pumpWidget(CupertinoApp(
        home: SemesterListPage(repository: AcademicRepository(store)),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey(
          'semester-courses-10000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(
          const ValueKey('course-20000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey(
          'course-rule-reschedule-30000000-0000-4000-8000-000000000001-20260908')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('reschedule-date')), '2026-09-23');
      await tester.enterText(
          find.byKey(const ValueKey('reschedule-start')), '09:00');
      await tester.enterText(
          find.byKey(const ValueKey('reschedule-end')), '09:45');
      tester.testTextInput.hide();
      await tester.pump();
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reschedule-save')));
      await tester.pumpAndSettle();

      var updated = await AcademicRepository(store).read();
      expect(updated.sessionRules.single.reschedules.single.originalDate,
          DateTime(2026, 9, 8));
      expect(updated.sessionRules.single.reschedules.single.targetDate,
          DateTime(2026, 9, 23));
      expect(find.text('2026-09-08 08:00–08:45 · 教学楼 101'), findsNothing);
      expect(find.text('2026-09-23 09:00–09:45 · 教学楼 101'), findsOneWidget);
      expect(find.text('2026-09-08 → 2026-09-23 · 已调课'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey(
          'course-rule-restore-reschedule-30000000-0000-4000-8000-000000000001-20260908')));
      await tester.pumpAndSettle();
      updated = await AcademicRepository(store).read();
      expect(updated.sessionRules.single.reschedules, isEmpty);
      expect(find.text('2026-09-08 08:00–08:45 · 教学楼 101'), findsOneWidget);
      expect(find.text('2026-09-23 09:00–09:45 · 教学楼 101'), findsNothing);
    });

    testWidgets('adds and deletes a makeup without changing weekly sessions',
        (tester) async {
      final profile = _profileWithRules();
      final store = _Store(jsonEncode(profile.toJson()));
      await tester.pumpWidget(CupertinoApp(
        home: SemesterListPage(repository: AcademicRepository(store)),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey(
          'semester-courses-10000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(
          const ValueKey('course-20000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey(
          'course-rule-add-extra-30000000-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('extra-date')), '2026-09-26');
      tester.testTextInput.hide();
      await tester.pump();
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('extra-save')));
      await tester.pumpAndSettle();

      var updated = await AcademicRepository(store).read();
      expect(updated.sessionRules.single.extraOccurrences, hasLength(1));
      expect(
          find.text('2026-09-26 08:00–08:45 · 教学楼 101 · 补课'), findsOneWidget);
      expect(find.text('2026-09-01 08:00–08:45 · 教学楼 101'), findsOneWidget);
      expect(find.text('2026-09-08 08:00–08:45 · 教学楼 101'), findsOneWidget);

      await tester.tap(find.text('删除这次补课'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();
      updated = await AcademicRepository(store).read();
      expect(updated.sessionRules.single.extraOccurrences, isEmpty);
      expect(find.text('2026-09-26 08:00–08:45 · 教学楼 101 · 补课'), findsNothing);
      expect(find.text('2026-09-01 08:00–08:45 · 教学楼 101'), findsOneWidget);
      expect(find.text('2026-09-08 08:00–08:45 · 教学楼 101'), findsOneWidget);
    });
  });
}
