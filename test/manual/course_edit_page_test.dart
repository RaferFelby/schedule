import 'dart:convert';

import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/controller/academic_controller.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/page/course_list_page.dart';
import 'package:celechron/manual/page/course_edit_page.dart';
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

AcademicProfile _emptyProfile() => AcademicProfile(
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
      ],
    );

AcademicProfile _profileWithCourse() {
  final profile = _emptyProfile();
  return AcademicProfile(
    schemaVersion: profile.schemaVersion,
    revision: profile.revision,
    semesters: profile.semesters,
    courses: [
      LocalCourse(
        id: '20000000-0000-4000-8000-000000000001',
        semesterId: profile.semesters.single.id,
        name: '旧名称',
        courseNumber: 'CS101',
        credits: 3,
        teacher: '王老师',
        isMajor: true,
        selectedForGpa: false,
      ),
    ],
  );
}

void main() {
  group('CourseEditPage', () {
    testWidgets('saves with only a name and the selected semester',
        (tester) async {
      final original = _emptyProfile();
      final store = _Store(jsonEncode(original.toJson()));
      await tester.pumpWidget(
        CupertinoApp(
          home: CourseListPage(
            repository: AcademicRepository(store),
            semester: original.semesters.single,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('course-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('course-name')),
        '数据结构',
      );
      tester.testTextInput.hide();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('course-save')));
      await tester.pumpAndSettle();

      final saved = AcademicProfile.fromJson(
        jsonDecode(store.value!) as Map<String, dynamic>,
      );
      expect(saved.revision, 1);
      expect(saved.courses, hasLength(1));
      expect(saved.courses.single.name, '数据结构');
      expect(saved.courses.single.semesterId, original.semesters.single.id);
      expect(saved.courses.single.courseNumber, isNull);
      expect(saved.courses.single.credits, isNull);
      expect(saved.courses.single.teacher, isNull);
      expect(saved.courses.single.isMajor, isFalse);
      expect(find.text('数据结构'), findsOneWidget);
    });

    testWidgets('rejects negative credits without writing', (tester) async {
      final original = _emptyProfile();
      final encoded = jsonEncode(original.toJson());
      final store = _Store(encoded);
      await tester.pumpWidget(
        CupertinoApp(
          home: CourseListPage(
            repository: AcademicRepository(store),
            semester: original.semesters.single,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('course-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('course-name')),
        '负学分课程',
      );
      await tester.enterText(
        find.byKey(const ValueKey('course-credits')),
        '-1',
      );
      tester.testTextInput.hide();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('course-save')));
      await tester.pump();

      expect(find.textContaining('课程学分必须是非负有限数值'), findsOneWidget);
      expect(store.value, encoded);
    });

    testWidgets('edits while preserving course ID and semester relation',
        (tester) async {
      final original = _profileWithCourse();
      final store = _Store(jsonEncode(original.toJson()));
      await tester.pumpWidget(
        CupertinoApp(
          home: CourseListPage(
            repository: AcademicRepository(store),
            semester: original.semesters.single,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
            const ValueKey('edit-course-20000000-0000-4000-8000-000000000001')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-detail-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('course-name')),
        '新名称',
      );
      await tester.enterText(
        find.byKey(const ValueKey('course-gpa-weight')),
        '0.5',
      );
      tester.testTextInput.hide();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('course-save')));
      await tester.pumpAndSettle();

      final saved = AcademicProfile.fromJson(
        jsonDecode(store.value!) as Map<String, dynamic>,
      );
      final course = saved.courses.single;
      expect(saved.revision, 1);
      expect(course.id, original.courses.single.id);
      expect(course.semesterId, original.semesters.single.id);
      expect(course.name, '新名称');
      expect(course.teacher, '王老师');
      expect(course.courseNumber, 'CS101');
      expect(course.credits, 3);
      expect(course.isMajor, isTrue);
      expect(course.selectedForGpa, isFalse);
      expect(course.gpaWeight, 0.5);
    });

    testWidgets('canceling an edit leaves the stored snapshot unchanged',
        (tester) async {
      final original = _profileWithCourse();
      final encoded = jsonEncode(original.toJson());
      final store = _Store(encoded);
      await tester.pumpWidget(
        CupertinoApp(
          home: CourseListPage(
            repository: AcademicRepository(store),
            semester: original.semesters.single,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
            const ValueKey('edit-course-20000000-0000-4000-8000-000000000001')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-detail-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('course-name')),
        '未保存名称',
      );
      await tester.tap(find.byKey(const ValueKey('course-cancel')));
      await tester.pumpAndSettle();
      expect(store.value, encoded);
    });

    testWidgets('explicitly joins a same-named course to a retake group',
        (tester) async {
      const groupId = '30000000-0000-4000-8000-000000000001';
      final firstSemester = _emptyProfile().semesters.single;
      final secondSemester = LocalSemester(
        id: '10000000-0000-4000-8000-000000000002',
        name: '春季学期',
        startDate: DateTime(2027, 2, 1),
        endDate: DateTime(2027, 6, 30),
        weekOneStart: DateTime(2027, 2, 1),
      );
      final first = LocalCourse(
        id: '20000000-0000-4000-8000-000000000001',
        semesterId: firstSemester.id,
        name: '同名课程',
        retakeGroupId: groupId,
      );
      final second = LocalCourse(
        id: '20000000-0000-4000-8000-000000000002',
        semesterId: secondSemester.id,
        name: '同名课程',
      );
      final profile = AcademicProfile(
        schemaVersion: 1,
        revision: 0,
        semesters: [firstSemester, secondSemester],
        courses: [first, second],
      );
      final store = _Store(jsonEncode(profile.toJson()));
      final repository = AcademicRepository(store);
      await tester.pumpWidget(CupertinoApp(
        home: CourseEditPage(
          controller: AcademicController(
            repository: repository,
            initialProfile: profile,
          ),
          semester: secondSemester,
          course: second,
        ),
      ));
      await tester.pumpAndSettle();
      expect(second.retakeGroupId, isNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('course-retake-group')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('course-retake-group')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('retake-group-$groupId')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('首次修读'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('course-name')), '改名后的课程');
      tester.testTextInput.hide();
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('course-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-save')));
      await tester.pumpAndSettle();

      final saved = await repository.read();
      expect(saved.courses[0].retakeGroupId, groupId);
      expect(saved.courses[1].retakeGroupId, groupId);
      expect(saved.courses[1].name, '改名后的课程');
      expect(saved.courses[0].retakeStrategy.name, 'firstAttempt');
      expect(saved.courses[1].retakeStrategy.name, 'firstAttempt');
      expect(saved.courses.map((course) => course.id).toSet(),
          {first.id, second.id});
    });
  });
}
