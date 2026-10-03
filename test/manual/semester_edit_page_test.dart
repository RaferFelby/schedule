import 'dart:convert';

import 'package:celechron/manual/controller/academic_controller.dart';
import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/page/semester_edit_page.dart';
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

AcademicProfile _existingProfile() {
  const semesterId = '10000000-0000-4000-8000-000000000001';
  return AcademicProfile(
    schemaVersion: 1,
    revision: 4,
    currentSemesterId: semesterId,
    semesters: [
      LocalSemester(
        id: semesterId,
        name: '原学期',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 8, 31),
        weekOneStart: DateTime(2026, 6, 29),
      ),
    ],
    courses: [
      LocalCourse(
        id: '20000000-0000-4000-8000-000000000001',
        semesterId: semesterId,
        name: '原有课程',
      ),
    ],
  );
}

void main() {
  group('SemesterEditPage', () {
    testWidgets('saves a semester and refreshes the list', (tester) async {
      final store = _Store();
      final repository = AcademicRepository(store);
      await tester.pumpWidget(
        CupertinoApp(home: SemesterListPage(repository: repository)),
      );
      await tester.pump();
      await tester.tap(find.text('新增'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.byKey(const ValueKey('semester-name')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('semester-name')),
        '暑期班',
      );
      await tester.enterText(
        find.byKey(const ValueKey('semester-start-date')),
        '2026-07-01',
      );
      await tester.enterText(
        find.byKey(const ValueKey('semester-end-date')),
        '2026-08-31',
      );
      await tester.enterText(
        find.byKey(const ValueKey('semester-week-one')),
        '2026-06-29',
      );
      await tester.ensureVisible(find.text('保存'));
      tester.testTextInput.hide();
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();

      expect(find.byKey(const ValueKey('semester-name')), findsNothing);
      expect(find.text('暑期班'), findsOneWidget);
      final saved = AcademicProfile.fromJson(
        jsonDecode(store.value!) as Map<String, dynamic>,
      );
      expect(saved.revision, 1);
      expect(saved.semesters.single.name, '暑期班');
      expect(saved.semesters.single.weekOneStart, DateTime(2026, 6, 29));
    });

    testWidgets('invalid date does not write to the repository',
        (tester) async {
      final store = _Store();
      final repository = AcademicRepository(store);
      final initial = await repository.read();
      final controller = AcademicController(
        repository: repository,
        initialProfile: initial,
      );
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: Builder(
              builder: (context) => CupertinoButton(
                onPressed: () => Navigator.of(context).push<void>(
                  CupertinoPageRoute<void>(
                    builder: (_) => SemesterEditPage(controller: controller),
                  ),
                ),
                child: const Text('打开表单'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开表单'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.byKey(const ValueKey('semester-name')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('semester-name')),
        '错误日期学期',
      );
      await tester.enterText(
        find.byKey(const ValueKey('semester-start-date')),
        '2026-02-30',
      );
      await tester.enterText(
        find.byKey(const ValueKey('semester-end-date')),
        '2026-08-31',
      );
      await tester.enterText(
        find.byKey(const ValueKey('semester-week-one')),
        '2026-06-29',
      );
      await tester.ensureVisible(find.text('保存'));
      tester.testTextInput.hide();
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(find.textContaining('不是有效日期'), findsOneWidget);
      expect(store.value, isNull);
      expect(controller.profile.value.semesters, isEmpty);
    });

    testWidgets('editing preserves the ID and unrelated course data',
        (tester) async {
      final original = _existingProfile();
      final store = _Store(jsonEncode(original.toJson()));
      final repository = AcademicRepository(store);
      await tester.pumpWidget(
        CupertinoApp(home: SemesterListPage(repository: repository)),
      );
      await tester.pump();
      await tester.tap(find.text('原学期'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();

      expect(find.text('编辑学期'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('semester-name')),
        '修改后名称',
      );
      tester.testTextInput.hide();
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();

      final saved = AcademicProfile.fromJson(
        jsonDecode(store.value!) as Map<String, dynamic>,
      );
      expect(saved.revision, 5);
      expect(saved.semesters.single.id, original.semesters.single.id);
      expect(saved.semesters.single.name, '修改后名称');
      expect(saved.courses.single.id, original.courses.single.id);
      expect(saved.currentSemesterId, original.currentSemesterId);
      expect(find.text('修改后名称'), findsOneWidget);
    });

    testWidgets('canceling an edit leaves the stored snapshot unchanged',
        (tester) async {
      final original = _existingProfile();
      final encoded = jsonEncode(original.toJson());
      final store = _Store(encoded);
      await tester.pumpWidget(
        CupertinoApp(
          home: SemesterListPage(repository: AcademicRepository(store)),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('原学期'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('semester-name')),
        '不应保存的名称',
      );
      tester.testTextInput.hide();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('semester-cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();

      expect(store.value, encoded);
      expect(find.text('原学期'), findsOneWidget);
      expect(find.text('不应保存的名称'), findsNothing);
    });
  });
}
