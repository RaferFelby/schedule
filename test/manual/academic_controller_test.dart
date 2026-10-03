import 'dart:convert';

import 'package:celechron/manual/controller/academic_controller.dart';
import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/data/local_data_error.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Store implements AcademicProfileStore {
  _Store(this.value, {this.writeError});

  String? value;
  final Object? writeError;

  @override
  Future<String?> readSnapshot() async => value;

  @override
  Future<void> writeSnapshot(String encoded) async {
    if (writeError != null) throw writeError!;
    value = encoded;
  }
}

void main() {
  group('AcademicController', () {
    test('publishes exactly once after a successful save', () async {
      final initial = AcademicProfile(schemaVersion: 1, revision: 0);
      final controller = AcademicController(
        repository: AcademicRepository(
          _Store(jsonEncode(initial.toJson())),
        ),
        initialProfile: initial,
      );
      final published = <AcademicProfile>[];
      final subscription = controller.profile.listen(published.add);

      final saved = await controller.save(
        AcademicProfile(schemaVersion: 1, revision: 0),
      );
      await Future<void>.delayed(Duration.zero);

      expect(saved.revision, 1);
      expect(controller.profile.value, same(saved));
      expect(published, [same(saved)]);
      await subscription.cancel();
    });

    test('keeps the old state when repository persistence fails', () async {
      final initial = AcademicProfile(schemaVersion: 1, revision: 3);
      final controller = AcademicController(
        repository: AcademicRepository(
          _Store(
            jsonEncode(initial.toJson()),
            writeError: StateError('write failed'),
          ),
        ),
        initialProfile: initial,
      );
      final published = <AcademicProfile>[];
      final subscription = controller.profile.listen(published.add);

      await expectLater(
        controller.save(AcademicProfile(schemaVersion: 1, revision: 3)),
        throwsA(isA<LocalDataStorageError>()),
      );

      expect(controller.profile.value, same(initial));
      expect(published, isEmpty);
      await subscription.cancel();
    });

    test('resolves a stale current ID by a unique date match', () {
      final semester = LocalSemester(
        id: '10000000-0000-4000-8000-000000000001',
        name: '暑期班',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 8, 31),
        weekOneStart: DateTime(2026, 6, 29),
      );
      final profile = AcademicProfile(
        schemaVersion: 1,
        revision: 0,
        currentSemesterId: '10000000-0000-4000-8000-000000000099',
        semesters: [semester],
      );
      final controller = AcademicController(
        repository: AcademicRepository(_Store(null)),
        initialProfile: profile,
      );

      expect(
        controller.resolveCurrentSemester(onDate: DateTime(2026, 7, 15)),
        same(semester),
      );
      expect(
        controller.resolveCurrentSemester(onDate: DateTime(2026, 1, 15)),
        isNull,
      );
    });

    test('returns null when the fallback date matches overlapping semesters',
        () {
      LocalSemester create(String id, String name) => LocalSemester(
            id: id,
            name: name,
            startDate: DateTime(2026, 7, 1),
            endDate: DateTime(2026, 8, 31),
            weekOneStart: DateTime(2026, 6, 29),
          );
      final controller = AcademicController(
        repository: AcademicRepository(_Store(null)),
        initialProfile: AcademicProfile(
          schemaVersion: 1,
          revision: 0,
          semesters: [
            create('10000000-0000-4000-8000-000000000001', '暑期班甲'),
            create('10000000-0000-4000-8000-000000000002', '暑期班乙'),
          ],
        ),
      );

      expect(
        controller.resolveCurrentSemester(onDate: DateTime(2026, 7, 15)),
        isNull,
      );
    });
  });
}
