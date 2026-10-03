import 'dart:io';

import 'package:hive/hive.dart';
import 'package:celechron/manual/data/generation_selection_store.dart';
import 'package:celechron/manual/data/storage_generation.dart';
import 'package:celechron/manual/migration/migration_runner.dart';
import 'package:celechron/manual/migration/migration_validator.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fallback = StorageGenerationManifest.active(
    rootDirectory: '/tmp/celechron-migration-runner-test',
    generationId: 'active-1',
  );
  final candidate = StorageGenerationManifest.candidateFor(
    active: fallback,
    generationId: 'candidate-2',
  );
  final profile = AcademicProfile(schemaVersion: 1, revision: 1);

  test('blocks incomplete accounting before candidate or pointer writes',
      () async {
    final writer = _Writer();
    final selector = _Selector(fallback);
    final runner = ManualMigrationRunner(writer: writer, selector: selector);

    await expectLater(
      runner.run(
        fallbackActive: fallback,
        candidate: candidate,
        profile: profile,
        tasks: const [],
        settings: const {},
        counts: const {
          'courses': MigrationCount(
            sourceRecords: 2,
            convertedRecords: 1,
            unresolvedRecords: 0,
          ),
        },
      ),
      throwsA(isA<MigrationBlockedError>()),
    );
    expect(writer.writes, 0);
    expect(selector.commits, 0);
  });

  test('writes candidate then selects it; a retry is idempotently complete',
      () async {
    final writer = _Writer();
    final selector = _Selector(fallback);
    final runner = ManualMigrationRunner(writer: writer, selector: selector);
    final first = await runner.run(
      fallbackActive: fallback,
      candidate: candidate,
      profile: profile,
      tasks: const [],
      settings: const {},
      counts: const {},
    );
    final retry = await runner.run(
      fallbackActive: fallback,
      candidate: candidate,
      profile: profile,
      tasks: const [],
      settings: const {},
      counts: const {},
    );

    expect(first.alreadyCommitted, isFalse);
    expect(retry.alreadyCommitted, isTrue);
    expect(writer.writes, 1);
    expect(selector.commits, 1);
    expect(selector.active.generationId, candidate.generationId);
  });

  test('durable writer verifies the same interrupted candidate on retry',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('migration-writer-');
    final root = '${directory.path}/store';
    await Directory(root).create(recursive: true);
    Hive.init(root);
    final active = StorageGenerationManifest.active(
      rootDirectory: root,
      generationId: 'active-old',
    );
    final pending = StorageGenerationManifest.candidateFor(
      active: active,
      generationId: 'candidate-new',
    );
    const writer = CandidateRestoreMigrationWriter();
    try {
      await writer.writeAndVerify(
        candidate: pending,
        profile: profile,
        tasks: const [],
        settings: const {},
      );
      await writer.writeAndVerify(
        candidate: pending,
        profile: profile,
        tasks: const [],
        settings: const {},
      );
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });

  test('detects a pointer committed before an exception is surfaced', () async {
    final writer = _Writer();
    final selector = _Selector(fallback)..throwAfterCommit = true;
    final runner = ManualMigrationRunner(writer: writer, selector: selector);

    final result = await runner.run(
      fallbackActive: fallback,
      candidate: candidate,
      profile: profile,
      tasks: const [],
      settings: const {},
      counts: const {},
    );

    expect(result.alreadyCommitted, isTrue);
    expect(result.active.generationId, candidate.generationId);
  });
}

final class _Writer implements MigrationGenerationWriter {
  int writes = 0;

  @override
  Future<void> writeAndVerify({
    required StorageGenerationManifest candidate,
    required AcademicProfile profile,
    required List<Task> tasks,
    required Map<String, Object?> settings,
  }) async {
    writes++;
  }
}

final class _Selector implements MigrationGenerationSelector {
  _Selector(this.active);

  StorageGenerationManifest active;
  int commits = 0;
  bool throwAfterCommit = false;

  @override
  Future<GenerationSelectionResult> selectActive({
    required StorageGenerationManifest fallback,
  }) async =>
      GenerationSelectionResult(
        active: active,
        sequence: commits,
        slot: commits == 0 ? null : 'a',
        usedFallback: commits == 0,
      );

  @override
  Future<GenerationSelectionResult> commitCandidate({
    required StorageGenerationManifest currentActive,
    required StorageGenerationManifest candidate,
  }) async {
    commits++;
    active = StorageGenerationManifest.active(
      rootDirectory: candidate.rootDirectory,
      generationId: candidate.generationId,
    );
    if (throwAfterCommit) throw StateError('simulated lost response');
    return GenerationSelectionResult(
      active: active,
      sequence: commits,
      slot: 'a',
      usedFallback: false,
    );
  }
}
