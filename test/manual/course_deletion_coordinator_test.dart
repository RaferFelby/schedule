import 'dart:convert';
import 'dart:io';

import 'package:celechron/debug/manual_preview_sample_loader.dart';
import 'package:celechron/debug/manual_preview_storage.dart';
import 'package:celechron/debug/manual_preview_task_store.dart';
import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/service/course_deletion_coordinator.dart';
import 'package:celechron/manual/service/manual_homework_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const _semesterId = '10000000-0000-4000-8000-000000000001';
const _courseId = '20000000-0000-4000-8000-000000000001';
const _secondCourseId = '20000000-0000-4000-8000-000000000002';

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
      'course-delete-recovery-',
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await documentsDirectory.exists()) {
      await documentsDirectory.delete(recursive: true);
    }
  });

  test('restart recovery finishes unlink after the academic save', () async {
    final previewBox = await ManualPreviewStorage.openAt(
      documentsDirectory.path,
    );
    await ManualPreviewSampleLoader.load(previewBox);
    final taskStore = ManualPreviewTaskStore(previewBox);
    final initialTasks = await taskStore.readTasks();
    final initialTimeSpent = initialTasks.single.timeSpent;
    final academicStore = _Store(_profileWithCourse());
    final repository = AcademicRepository(academicStore);
    var shouldFailUnlink = true;

    final interrupted = CourseDeletionCoordinator(
      repository: repository,
      previewBox: previewBox,
      unlinkCourse: (courseId) async {
        if (shouldFailUnlink) throw StateError('simulated task-store failure');
        return taskStore.unlinkCourse(courseId);
      },
    );
    await expectLater(
      interrupted.removeCourse(_courseId),
      throwsA(isA<StateError>()),
    );

    expect(
      academicStore.value.courses.map((course) => course.id),
      [_secondCourseId],
    );
    expect(
        previewBox.containsKey(CourseDeletionCoordinator.journalKey), isTrue);
    final pendingTasks = await taskStore.readTasks();
    expect(pendingTasks, hasLength(initialTasks.length));
    expect(pendingTasks.single.courseId, _courseId);
    expect(
      ManualHomeworkAdapter.pending(tasks: pendingTasks, courses: [])
          .single
          .courseName,
      '关联课程不可用',
    );

    shouldFailUnlink = false;
    await CourseDeletionCoordinator(
      repository: repository,
      previewBox: previewBox,
    ).recoverPending();

    final restoredTasks = await taskStore.readTasks();
    expect(restoredTasks, hasLength(initialTasks.length));
    expect(restoredTasks.single.courseId, isNull);
    expect(restoredTasks.single.timeSpent, initialTimeSpent);
    expect(
        previewBox.containsKey(CourseDeletionCoordinator.journalKey), isFalse);
  });

  test('semester recovery unlinks every affected course after interruption',
      () async {
    final previewBox = await ManualPreviewStorage.openAt(
      documentsDirectory.path,
    );
    await ManualPreviewSampleLoader.load(previewBox);
    final taskStore = ManualPreviewTaskStore(previewBox);
    final academicStore = _Store(_profileWithCourse());
    final repository = AcademicRepository(academicStore);
    var shouldFailUnlink = true;

    final interrupted = CourseDeletionCoordinator(
      repository: repository,
      previewBox: previewBox,
      unlinkCourse: (courseId) async {
        if (shouldFailUnlink) {
          shouldFailUnlink = false;
          throw StateError('simulated task-store failure');
        }
        return taskStore.unlinkCourse(courseId);
      },
    );
    await expectLater(
      interrupted.removeSemester(_semesterId),
      throwsA(isA<StateError>()),
    );

    expect(academicStore.value.semesters, isEmpty);
    expect(academicStore.value.courses, isEmpty);
    expect((await taskStore.readTasks()).single.courseId, _courseId);
    expect(
        previewBox.containsKey(CourseDeletionCoordinator.journalKey), isTrue);

    await CourseDeletionCoordinator(
      repository: repository,
      previewBox: previewBox,
    ).recoverPending();

    expect((await taskStore.readTasks()).single.courseId, isNull);
    expect(
        previewBox.containsKey(CourseDeletionCoordinator.journalKey), isFalse);
  });

  test('recovers the previous course-only journal format', () async {
    final previewBox = await ManualPreviewStorage.openAt(
      documentsDirectory.path,
    );
    await ManualPreviewSampleLoader.load(previewBox);
    final taskStore = ManualPreviewTaskStore(previewBox);
    final academicStore = _Store(_profileWithCourse());
    final repository = AcademicRepository(academicStore);
    await previewBox.put(
      CourseDeletionCoordinator.journalKey,
      jsonEncode({'courseId': _courseId}),
    );

    await CourseDeletionCoordinator(
      repository: repository,
      previewBox: previewBox,
    ).recoverPending();

    expect(
      (await repository.read()).courses.map((course) => course.id),
      [_secondCourseId],
    );
    expect((await taskStore.readTasks()).single.courseId, isNull);
    expect(
        previewBox.containsKey(CourseDeletionCoordinator.journalKey), isFalse);
  });
}

AcademicProfile _profileWithCourse() => AcademicProfile(
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
        LocalCourse(
          id: _secondCourseId,
          semesterId: _semesterId,
          name: '示例课程二',
        ),
      ],
    );
