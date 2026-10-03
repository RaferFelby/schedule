import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';

import '../model/academic_profile.dart';
import '../service/manual_planning_revision.dart';
import 'local_data_error.dart';

abstract interface class AcademicProfileStore {
  Future<String?> readSnapshot();

  Future<void> writeSnapshot(String value);
}

/// Reads the versioned manual-entry snapshot without opening legacy boxes.
final class AcademicRepository {
  AcademicRepository(this._store);

  static const boxName = 'manual-academic-profile-v1';
  static const snapshotKey = 'snapshot';

  final AcademicProfileStore _store;
  Future<void> _writeQueue = Future<void>.value();

  static Future<AcademicRepository> open({
    HiveInterface? hive,
    String boxName = AcademicRepository.boxName,
    String? path,
  }) async {
    try {
      final box = await (hive ?? Hive).openBox<String>(boxName, path: path);
      return AcademicRepository(_HiveProfileStore(box));
    } catch (error) {
      throw LocalDataStorageError('无法打开本地学业数据', cause: error);
    }
  }

  Future<AcademicProfile> read() async {
    final String? encoded;
    try {
      encoded = await _store.readSnapshot();
    } catch (error) {
      throw LocalDataStorageError('无法读取本地学业数据', cause: error);
    }

    if (encoded == null) {
      return AcademicProfile(
        schemaVersion: AcademicProfile.supportedSchemaVersion,
        revision: 0,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException catch (error) {
      throw LocalDataValidationError('本地学业快照 JSON 损坏：${error.message}');
    }
    if (decoded is! Map) {
      throw const LocalDataValidationError('本地学业快照必须是 JSON 对象');
    }
    return AcademicProfile.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<AcademicProfile> save(AcademicProfile candidate) => _enqueue(() async {
        final current = await read();
        return _saveCandidate(candidate, current);
      });

  Future<AcademicProfile> update(
    FutureOr<AcademicProfile> Function(AcademicProfile current) transform,
  ) =>
      _enqueue(() async {
        final current = await read();
        final candidate = await transform(current);
        return _saveCandidate(candidate, current);
      });

  Future<AcademicProfile> _saveCandidate(
    AcademicProfile candidate,
    AcademicProfile current,
  ) async {
    final next = AcademicProfile(
      schemaVersion: candidate.schemaVersion,
      revision: current.revision + 1,
      planningRevision: current.planningRevision +
          (ManualPlanningRevision.academicInputsChanged(current, candidate)
              ? 1
              : 0),
      currentSemesterId: candidate.currentSemesterId,
      semesters: candidate.semesters,
      timeSlots: candidate.timeSlots,
      courses: candidate.courses,
      sessionRules: candidate.sessionRules,
      exams: candidate.exams,
      grades: candidate.grades,
      practiceRecords: candidate.practiceRecords,
    );
    final encoded = jsonEncode(next.toJson());
    try {
      await _store.writeSnapshot(encoded);
    } catch (error) {
      throw LocalDataStorageError('无法保存本地学业数据', cause: error);
    }
    return next;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _writeQueue.then((_) => operation());
    _writeQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }
}

final class _HiveProfileStore implements AcademicProfileStore {
  _HiveProfileStore(this._box);

  final Box<String> _box;

  @override
  Future<String?> readSnapshot() async =>
      _box.get(AcademicRepository.snapshotKey);

  @override
  Future<void> writeSnapshot(String value) =>
      _box.put(AcademicRepository.snapshotKey, value);
}
