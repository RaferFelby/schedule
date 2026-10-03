import 'package:celechron/manual/data/local_data_error.dart';
import 'package:celechron/manual/data/storage_generation.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Cleaner implements GenerationDirectoryCleaner {
  final deletedPaths = <String>[];

  @override
  Future<void> deleteGenerationDirectory(String path) async {
    deletedPaths.add(path);
  }
}

void main() {
  const root = '/tmp/celechron-generation-test';

  test('active and candidate manifests use disjoint versioned locations', () {
    final active = StorageGenerationManifest.active(
      rootDirectory: root,
      generationId: 'active-1',
    );
    final candidate = StorageGenerationManifest.candidateFor(
      active: active,
      generationId: 'candidate-1',
    );

    expect(active.role, StorageGenerationRole.active);
    expect(candidate.role, StorageGenerationRole.candidate);
    expect(candidate.parentGenerationId, active.generationId);
    expect(candidate.generationDirectory, isNot(active.generationDirectory));
    expect(candidate.academicLocation, isNot(active.academicLocation));
    expect(candidate.taskLocation, isNot(active.taskLocation));
    expect(candidate.settingsLocation, isNot(active.settingsLocation));
  });

  test('manifest round-trips and derives locations instead of trusting JSON',
      () {
    final candidate = StorageGenerationManifest.candidateFor(
      active: StorageGenerationManifest.active(
        rootDirectory: root,
        generationId: 'active-1',
      ),
      generationId: 'candidate-1',
    );
    final decoded = StorageGenerationManifest.fromJson(candidate.toJson());

    expect(decoded.generationDirectory, candidate.generationDirectory);
    expect(decoded.academicLocation, candidate.academicLocation);
    expect(decoded.taskLocation, candidate.taskLocation);
    expect(decoded.settingsLocation, candidate.settingsLocation);

    final tampered = Map<String, dynamic>.from(candidate.toJson());
    tampered['locations'] = {
      'academic': '/outside/active-data',
      'tasks': candidate.taskLocation,
      'settings': candidate.settingsLocation,
    };
    expect(
      () => StorageGenerationManifest.fromJson(tampered),
      throwsA(isA<LocalDataValidationError>()),
    );
  });

  test('cleanup rejects active data without invoking the cleaner', () async {
    final active = StorageGenerationManifest.active(
      rootDirectory: root,
      generationId: 'active-1',
    );
    final cleaner = _Cleaner();

    await expectLater(
      const StorageGenerationCleanup().cleanCandidate(
        active: active,
        candidate: active,
        cleaner: cleaner,
      ),
      throwsA(isA<LocalDataValidationError>()),
    );
    expect(cleaner.deletedPaths, isEmpty);
  });

  test('candidate cleanup passes only that candidate path', () async {
    final active = StorageGenerationManifest.active(
      rootDirectory: root,
      generationId: 'active-1',
    );
    final candidate = StorageGenerationManifest.candidateFor(
      active: active,
      generationId: 'candidate-1',
    );
    final cleaner = _Cleaner();

    await const StorageGenerationCleanup().cleanCandidate(
      active: active,
      candidate: candidate,
      cleaner: cleaner,
    );

    expect(cleaner.deletedPaths, [candidate.generationDirectory]);
    expect(cleaner.deletedPaths, isNot(contains(active.generationDirectory)));
  });

  test(
      'rejects traversal IDs and candidates from a different active generation',
      () async {
    final active = StorageGenerationManifest.active(
      rootDirectory: root,
      generationId: 'active-1',
    );
    expect(
      () => StorageGenerationManifest.candidateFor(
        active: active,
        generationId: '../outside',
      ),
      throwsA(isA<LocalDataValidationError>()),
    );
    final unrelated = StorageGenerationManifest.candidateFor(
      active: StorageGenerationManifest.active(
        rootDirectory: root,
        generationId: 'active-2',
      ),
      generationId: 'candidate-2',
    );
    final cleaner = _Cleaner();

    await expectLater(
      const StorageGenerationCleanup().cleanCandidate(
        active: active,
        candidate: unrelated,
        cleaner: cleaner,
      ),
      throwsA(isA<LocalDataValidationError>()),
    );
    expect(cleaner.deletedPaths, isEmpty);
  });
}
