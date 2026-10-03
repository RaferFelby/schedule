import 'dart:convert';
import 'dart:io';

import 'package:celechron/debug/manual_preview_sample_loader.dart';
import 'package:celechron/debug/manual_preview_storage.dart';
import 'package:celechron/debug/manual_preview_task_store.dart';
import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/page/semester_list_page.dart';
import 'package:celechron/manual/service/semester_deletion_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const _semesterId = '10000000-0000-4000-8000-000000000001';
const _otherSemesterId = '10000000-0000-4000-8000-000000000002';
const _courseId = '20000000-0000-4000-8000-000000000001';
const _otherCourseId = '20000000-0000-4000-8000-000000000002';

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
      'semester-delete-ui-',
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await documentsDirectory.exists()) {
      await documentsDirectory.delete(recursive: true);
    }
  });

  testWidgets(
      'cancel preserves data; confirm shows impact and removes semester',
      (tester) async {
    final previewBox = (await tester.runAsync(
      () => ManualPreviewStorage.openAt(documentsDirectory.path),
    ))!;
    await tester.runAsync(() => ManualPreviewSampleLoader.load(previewBox));
    final taskStore = ManualPreviewTaskStore(previewBox);
    final originalTask = (await taskStore.readTasks()).single;
    var simulatedTasks = [originalTask];
    final store = _Store(_profile());
    final repository = AcademicRepository(store);

    await tester.pumpWidget(CupertinoApp(
      home: SemesterListPage(
        repository: repository,
        previewBox: previewBox,
        deleteSemester: (semesterId) async {
          final current = await repository.read();
          await repository.save(
            SemesterDeletionService.removeSemester(current, semesterId),
          );
          final courseIds = current.courses
              .where((course) => course.semesterId == semesterId)
              .map((course) => course.id)
              .toSet();
          simulatedTasks = simulatedTasks
              .map((task) => courseIds.contains(task.courseId)
                  ? task.copyWith(clearCourseId: true)
                  : task)
              .toList();
        },
      ),
    ));
    await _pumpUi(tester);

    await tester
        .tap(find.byKey(const ValueKey('semester-delete-$_semesterId')));
    await _pumpUi(tester);
    expect(find.textContaining('将删除 1 门课程'), findsOneWidget);
    expect(find.textContaining('解除 1 个作业关联'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await _pumpUi(tester);

    expect((await repository.read()).semesters, hasLength(2));
    expect((await repository.read()).currentSemesterId, _semesterId);
    expect(simulatedTasks.single.courseId, _courseId);

    await tester
        .tap(find.byKey(const ValueKey('semester-delete-$_semesterId')));
    await _pumpUi(tester);
    await tester.tap(find.text('删除学期'));
    await _pumpUi(tester);

    final saved = await repository.read();
    expect(saved.semesters.map((semester) => semester.id), [_otherSemesterId]);
    expect(saved.courses.map((course) => course.id), [_otherCourseId]);
    expect(saved.currentSemesterId, isNull);
    expect(simulatedTasks, hasLength(1));
    expect(simulatedTasks.single.courseId, isNull);
    expect(simulatedTasks.single.timeSpent, originalTask.timeSpent);
  });
}

AcademicProfile _profile() => AcademicProfile(
      schemaVersion: 1,
      revision: 0,
      currentSemesterId: _semesterId,
      semesters: [
        _semester(_semesterId, '秋季学期'),
        _semester(_otherSemesterId, '春季学期'),
      ],
      courses: [
        LocalCourse(id: _courseId, semesterId: _semesterId, name: '目标课程'),
        LocalCourse(
          id: _otherCourseId,
          semesterId: _otherSemesterId,
          name: '保留课程',
        ),
      ],
    );

LocalSemester _semester(String id, String name) => LocalSemester(
      id: id,
      name: name,
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2027, 1, 31),
      weekOneStart: DateTime(2026, 8, 31),
    );

Future<void> _pumpUi(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
