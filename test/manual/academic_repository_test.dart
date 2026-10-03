import 'dart:convert';
import 'dart:io';

import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/data/local_data_error.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/local_exam.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/service/manual_planning_revision.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

final class _Reader implements AcademicProfileStore {
  _Reader(this.value, {this.readError, this.writeError});

  String? value;
  final Object? readError;
  final Object? writeError;

  @override
  Future<String?> readSnapshot() {
    if (readError != null) return Future.error(readError!);
    return Future.value(value);
  }

  @override
  Future<void> writeSnapshot(String newValue) {
    if (writeError != null) return Future.error(writeError!);
    value = newValue;
    return Future.value();
  }
}

AcademicProfile _scheduledProfile({
  DateTime? examStart,
  double? credits,
}) {
  const semesterId = '10000000-0000-4000-8000-000000000001';
  const courseId = '20000000-0000-4000-8000-000000000001';
  final start = examStart ?? DateTime(2026, 7, 6, 9);
  return AcademicProfile(
    schemaVersion: 1,
    revision: 0,
    semesters: [
      LocalSemester(
        id: semesterId,
        name: '暑期班',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 8, 31),
        weekOneStart: DateTime(2026, 6, 29),
      ),
    ],
    courses: [
      LocalCourse(
        id: courseId,
        semesterId: semesterId,
        name: '课程甲',
        credits: credits,
      ),
    ],
    exams: [
      LocalExam(
        id: '30000000-0000-4000-8000-000000000001',
        courseId: courseId,
        type: '期末',
        start: start,
        end: start.add(const Duration(hours: 2)),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('academic-repository-');
    Hive.init(directory.path);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  group('AcademicRepository.read', () {
    test('missing snapshot returns an empty versioned profile', () async {
      final repository = await AcademicRepository.open();

      final profile = await repository.read();
      expect(profile.schemaVersion, AcademicProfile.supportedSchemaVersion);
      expect(profile.revision, 0);
      expect(profile.semesters, isEmpty);
      expect(profile.courses, isEmpty);
    });

    test('reads a valid snapshot from the dedicated box', () async {
      final profile = AcademicProfile(
        schemaVersion: 1,
        revision: 4,
      );
      final box = await Hive.openBox<String>(AcademicRepository.boxName);
      await box.put(
          AcademicRepository.snapshotKey, jsonEncode(profile.toJson()));

      final restored = await (await AcademicRepository.open()).read();
      expect(restored.toJson(), profile.toJson());
      expect(box.name, AcademicRepository.boxName);
    });

    test('corrupt JSON reports an error and remains unchanged', () async {
      const corrupt = '{invalid-json';
      final box = await Hive.openBox<String>(AcademicRepository.boxName);
      await box.put(AcademicRepository.snapshotKey, corrupt);
      final repository = await AcademicRepository.open();

      await expectLater(
        repository.read(),
        throwsA(isA<LocalDataValidationError>()),
      );
      expect(box.get(AcademicRepository.snapshotKey), corrupt);
    });

    test('storage read failures retain the cause', () async {
      final cause = StateError('read failed');
      final repository = AcademicRepository(_Reader(null, readError: cause));

      await expectLater(
        repository.read(),
        throwsA(
          isA<LocalDataStorageError>()
              .having((error) => error.cause, 'cause', same(cause)),
        ),
      );
    });

    test('successful save writes the candidate with the next revision',
        () async {
      final store = _Reader(
        jsonEncode(AcademicProfile(schemaVersion: 1, revision: 5).toJson()),
      );
      final repository = AcademicRepository(store);
      final candidate = AcademicProfile(schemaVersion: 1, revision: 0);

      final saved = await repository.save(candidate);
      expect(saved.revision, 6);
      expect(
        AcademicProfile.fromJson(
                jsonDecode(store.value!) as Map<String, dynamic>)
            .revision,
        6,
      );
    });

    test('exam schedule bumps only the independent planning revision',
        () async {
      final store = _Reader(jsonEncode(_scheduledProfile().toJson()));
      final repository = AcademicRepository(store);
      final original = await repository.read();
      final originalPlanStamp = ManualPlanRevisionStamp(
        academicRevision: original.planningRevision,
        taskRevision: 0,
      );

      final movedExam = await repository.save(
        _scheduledProfile(examStart: DateTime(2026, 7, 6, 10)),
      );
      expect(movedExam.revision, 1);
      expect(movedExam.planningRevision, 1);
      expect(
        originalPlanStamp.needsReplan(
          currentProfile: movedExam,
          currentTaskRevision: 0,
        ),
        isTrue,
      );

      final currentPlanStamp = ManualPlanRevisionStamp(
        academicRevision: movedExam.planningRevision,
        taskRevision: 0,
      );

      final editedCredits = await repository.save(
        _scheduledProfile(
          examStart: DateTime(2026, 7, 6, 10),
          credits: 3,
        ),
      );
      expect(editedCredits.revision, 2);
      expect(editedCredits.planningRevision, 1);
      expect(
        currentPlanStamp.needsReplan(
          currentProfile: editedCredits,
          currentTaskRevision: 0,
        ),
        isFalse,
      );
    });

    test('older snapshots default planning revision to zero', () {
      final json = AcademicProfile(schemaVersion: 1, revision: 4).toJson()
        ..remove('planningRevision');

      expect(AcademicProfile.fromJson(json).planningRevision, 0);
    });

    test('failed save preserves stored snapshot and old revision', () async {
      final old = AcademicProfile(schemaVersion: 1, revision: 7);
      final original = jsonEncode(old.toJson());
      final cause = StateError('write failed');
      final store = _Reader(original, writeError: cause);
      final repository = AcademicRepository(store);

      await expectLater(
        repository.save(AcademicProfile(schemaVersion: 1, revision: 7)),
        throwsA(
          isA<LocalDataStorageError>()
              .having((error) => error.cause, 'cause', same(cause)),
        ),
      );
      expect(store.value, original);
      expect((await repository.read()).revision, 7);
    });

    test('concurrent updates both apply to the latest snapshot', () async {
      const semesterId = '10000000-0000-4000-8000-000000000001';
      final initial = AcademicProfile(
        schemaVersion: 1,
        revision: 0,
        semesters: [
          LocalSemester(
            id: semesterId,
            name: '暑期班',
            startDate: DateTime(2026, 7, 1),
            endDate: DateTime(2026, 8, 31),
            weekOneStart: DateTime(2026, 6, 29),
          ),
        ],
      );
      final store = _Reader(jsonEncode(initial.toJson()));
      final repository = AcademicRepository(store);

      Future<AcademicProfile> addCourse(
        AcademicProfile current,
        String id,
        String name,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return AcademicProfile(
          schemaVersion: current.schemaVersion,
          revision: current.revision,
          semesters: current.semesters,
          courses: [
            ...current.courses,
            LocalCourse(id: id, semesterId: semesterId, name: name),
          ],
        );
      }

      final results = await Future.wait([
        repository.update(
          (current) => addCourse(
            current,
            '20000000-0000-4000-8000-000000000001',
            '课程甲',
          ),
        ),
        repository.update(
          (current) => addCourse(
            current,
            '20000000-0000-4000-8000-000000000002',
            '课程乙',
          ),
        ),
      ]);

      final finalProfile = await repository.read();
      expect(finalProfile.courses.map((course) => course.name).toSet(), {
        '课程甲',
        '课程乙',
      });
      expect(finalProfile.revision, 2);
      expect(results.map((profile) => profile.revision), [1, 2]);
    });

    test('a failed queued update does not block later work', () async {
      final repository = AcademicRepository(
        _Reader(jsonEncode(
            AcademicProfile(schemaVersion: 1, revision: 0).toJson())),
      );
      await expectLater(
        repository.update((_) => throw StateError('transform failed')),
        throwsA(isA<StateError>()),
      );

      final saved = await repository.update((current) => current);
      expect(saved.revision, 1);
    });
  });
}
