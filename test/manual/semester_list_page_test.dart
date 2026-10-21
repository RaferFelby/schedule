import 'dart:convert';

import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/grade_record.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/page/semester_list_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Store implements AcademicProfileStore {
  _Store(this.encoded);

  String? encoded;

  @override
  Future<String?> readSnapshot() async => encoded;

  @override
  Future<void> writeSnapshot(String value) async => encoded = value;
}

LocalSemester _semester({
  required String id,
  required String name,
  required DateTime start,
}) =>
    LocalSemester(
      id: id,
      name: name,
      startDate: start,
      endDate: DateTime(start.year, start.month + 2, 1),
      weekOneStart: DateTime(2026, 6, 29),
    );

Future<void> _show(WidgetTester tester, AcademicProfile profile) async {
  await tester.pumpWidget(
    CupertinoApp(
      home: SemesterListPage(
        repository: AcademicRepository(_Store(jsonEncode(profile.toJson()))),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('SemesterListPage', () {
    testWidgets('empty snapshot displays a creation hint', (tester) async {
      await _show(tester, AcademicProfile(schemaVersion: 1, revision: 0));

      expect(find.text('还没有学期'), findsOneWidget);
      expect(find.text('创建学期后会显示在这里。'), findsOneWidget);
    });

    testWidgets('sorts by start date and displays free-form names',
        (tester) async {
      final profile = AcademicProfile(
        schemaVersion: 1,
        revision: 0,
        semesters: [
          _semester(
            id: '10000000-0000-4000-8000-000000000002',
            name: '秋季',
            start: DateTime(2026, 9),
          ),
          _semester(
            id: '10000000-0000-4000-8000-000000000001',
            name: '暑期班',
            start: DateTime(2026, 7),
          ),
        ],
      );
      await _show(tester, profile);

      final summer = find.text('暑期班');
      final autumn = find.text('秋季');
      expect(summer, findsOneWidget);
      expect(autumn, findsOneWidget);
      expect(
          tester.getTopLeft(summer).dy, lessThan(tester.getTopLeft(autumn).dy));
      expect(find.text('2026-07-01 — 2026-09-01'), findsOneWidget);
    });

    testWidgets('selecting a semester persists the current ID', (tester) async {
      final profile = AcademicProfile(
        schemaVersion: 1,
        revision: 0,
        semesters: [
          _semester(
            id: '10000000-0000-4000-8000-000000000001',
            name: '暑期班',
            start: DateTime(2026, 7),
          ),
        ],
      );
      final store = _Store(jsonEncode(profile.toJson()));
      await tester.pumpWidget(
        CupertinoApp(
          home: SemesterListPage(repository: AcademicRepository(store)),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('设为当前'));
      await tester.pump();
      await tester.pump();

      final saved = AcademicProfile.fromJson(
        jsonDecode(store.encoded!) as Map<String, dynamic>,
      );
      expect(saved.revision, 1);
      expect(saved.currentSemesterId, profile.semesters.single.id);
      expect(find.text('当前学期'), findsOneWidget);
      expect(find.text('设为当前'), findsNothing);
      expect(find.textContaining('setState()'), findsNothing);
    });

    testWidgets('shows total and semester GPA plus earned credits',
        (tester) async {
      final firstSemester = _semester(
        id: '10000000-0000-4000-8000-000000000001',
        name: '秋季',
        start: DateTime(2026, 9),
      );
      final secondSemester = _semester(
        id: '10000000-0000-4000-8000-000000000002',
        name: '春季',
        start: DateTime(2027, 2),
      );
      final firstCourse = LocalCourse(
        id: '20000000-0000-4000-8000-000000000001',
        semesterId: firstSemester.id,
        name: '课程一',
        credits: 2,
        gpaWeight: 0.5,
      );
      final secondCourse = LocalCourse(
        id: '20000000-0000-4000-8000-000000000002',
        semesterId: secondSemester.id,
        name: '课程二',
        credits: 3,
      );
      final profile = AcademicProfile(
        schemaVersion: 1,
        revision: 0,
        semesters: [firstSemester, secondSemester],
        courses: [firstCourse, secondCourse],
        grades: [
          GradeRecord(
            id: '50000000-0000-4000-8000-000000000001',
            courseId: firstCourse.id,
            status: LocalGradeStatus.recorded,
            method: LocalGradingMethod.directGpa,
            gradePoint: 4,
          ),
          GradeRecord(
            id: '50000000-0000-4000-8000-000000000002',
            courseId: secondCourse.id,
            status: LocalGradeStatus.recorded,
            method: LocalGradingMethod.directGpa,
            gradePoint: 3,
          ),
        ],
      );
      await _show(tester, profile);

      expect(find.textContaining('全部学期'), findsOneWidget);
      expect(find.textContaining('GPA：2.6'), findsOneWidget);
      expect(find.textContaining('GPA 计入学分：5.0'), findsOneWidget);
      expect(find.textContaining('已获学分：5.0'), findsOneWidget);
      expect(find.textContaining('GPA：2.0'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('GPA：3.0'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('GPA：3.0'), findsOneWidget);
    });

    testWidgets('does not invent GPA when credits are unknown', (tester) async {
      final semester = _semester(
        id: '10000000-0000-4000-8000-000000000001',
        name: '秋季',
        start: DateTime(2026, 9),
      );
      final course = LocalCourse(
        id: '20000000-0000-4000-8000-000000000001',
        semesterId: semester.id,
        name: '未知学分课',
      );
      final profile = AcademicProfile(
        schemaVersion: 1,
        revision: 0,
        semesters: [semester],
        courses: [course],
        grades: [
          GradeRecord(
            id: '50000000-0000-4000-8000-000000000001',
            courseId: course.id,
            status: LocalGradeStatus.recorded,
            method: LocalGradingMethod.directGpa,
            gradePoint: 4,
          ),
        ],
      );
      await _show(tester, profile);

      expect(find.textContaining('GPA 暂无结果'), findsNWidgets(2));
      expect(find.textContaining('GPA 学分未知：1 门'), findsNWidgets(2));
    });
  });
}
