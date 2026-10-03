import 'dart:convert';
import 'dart:io';

import 'package:celechron/debug/manual_preview_sample_loader.dart';
import 'package:celechron/debug/manual_preview_storage.dart';
import 'package:celechron/debug/manual_preview_task_store.dart';
import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/grade_record.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/local_exam.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/model/session_rule.dart';
import 'package:celechron/manual/page/course_detail_page.dart';
import 'package:celechron/manual/service/course_deletion_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const _semesterId = '10000000-0000-4000-8000-000000000001';
const _courseId = '20000000-0000-4000-8000-000000000001';

final class _Store implements AcademicProfileStore {
  _Store(this.value);

  AcademicProfile value;

  @override
  Future<String?> readSnapshot() async => jsonEncode(value.toJson());

  @override
  Future<void> writeSnapshot(String encoded) async {
    value =
        AcademicProfile.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp(
      'course-delete-ui-',
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await documentsDirectory.exists()) {
      await documentsDirectory.delete(recursive: true);
    }
  });

  testWidgets(
    'cancel preserves data; confirm deletes dependencies and unlinks task',
    (tester) async {
      final previewBox = (await tester.runAsync(
        () => ManualPreviewStorage.openAt(documentsDirectory.path),
      ))!;
      await tester.runAsync(() => ManualPreviewSampleLoader.load(previewBox));
      final taskStore = ManualPreviewTaskStore(previewBox);
      final initialTask = (await taskStore.readTasks()).single;
      var simulatedTasks = [initialTask];
      final academicStore = _Store(_profileWithDependencies());
      final repository = AcademicRepository(academicStore);
      final semester = academicStore.value.semesters.single;
      final course = academicStore.value.courses.single;

      await tester.pumpWidget(CupertinoApp(
        home: CupertinoPageScaffold(
          child: Builder(
            builder: (context) => Center(
              child: CupertinoButton(
                key: const ValueKey('open-course-detail'),
                onPressed: () => Navigator.of(context).push<void>(
                  CupertinoPageRoute<void>(
                    builder: (_) => CourseDetailPage(
                      repository: repository,
                      semester: semester,
                      course: course,
                      previewBox: previewBox,
                      deleteCourse: (courseId) async {
                        final current = await repository.read();
                        await repository.save(
                          CourseDeletionService.removeCourse(current, courseId),
                        );
                        simulatedTasks = simulatedTasks
                            .map((task) => task.courseId == courseId
                                ? task.copyWith(clearCourseId: true)
                                : task)
                            .toList();
                      },
                    ),
                  ),
                ),
                child: const Text('打开课程'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('open-course-detail')));
      await _pumpUi(tester);
      expect(find.text('课程详情'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('course-delete')),
        300,
      );
      expect(find.text('删除此课程'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('course-delete')));
      await _pumpUi(tester);
      expect(find.textContaining('将删除 1 条上课安排、1 场考试和 1 条成绩'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await _pumpUi(tester);

      expect((await repository.read()).courses, hasLength(1));
      expect(simulatedTasks.single.courseId, _courseId);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('course-delete')),
        300,
      );
      await tester.tap(find.byKey(const ValueKey('course-delete')));
      await _pumpUi(tester);
      await tester.tap(find.text('删除课程'));
      await _pumpUi(tester);

      final savedProfile = await repository.read();
      expect(savedProfile.courses, isEmpty);
      expect(savedProfile.sessionRules, isEmpty);
      expect(savedProfile.exams, isEmpty);
      expect(savedProfile.grades, isEmpty);
      expect(simulatedTasks, hasLength(1));
      expect(simulatedTasks.single.courseId, isNull);
      expect(simulatedTasks.single.timeSpent, initialTask.timeSpent);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}

Future<void> _pumpUi(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

AcademicProfile _profileWithDependencies() => AcademicProfile(
      schemaVersion: 1,
      revision: 0,
      currentSemesterId: _semesterId,
      semesters: [
        LocalSemester(
          id: _semesterId,
          name: '秋季学期',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2027, 1, 31),
          weekOneStart: DateTime(2026, 8, 31),
        ),
      ],
      courses: [
        LocalCourse(id: _courseId, semesterId: _semesterId, name: '示例课程'),
      ],
      sessionRules: [
        SessionRule(
          id: '30000000-0000-4000-8000-000000000001',
          courseId: _courseId,
          weekday: DateTime.monday,
          weekNumbers: [1],
          startSlotOrdinal: 1,
          endSlotOrdinal: 1,
        ),
      ],
      exams: [
        LocalExam(
          id: '40000000-0000-4000-8000-000000000001',
          courseId: _courseId,
          type: '期末',
          start: DateTime(2026, 12, 20, 9),
          end: DateTime(2026, 12, 20, 11),
        ),
      ],
      grades: [
        GradeRecord(
          id: '50000000-0000-4000-8000-000000000001',
          courseId: _courseId,
          status: LocalGradeStatus.notRecorded,
          method: LocalGradingMethod.percentage,
        ),
      ],
    );
