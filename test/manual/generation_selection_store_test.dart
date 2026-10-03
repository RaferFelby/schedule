import 'dart:io';

import 'package:celechron/manual/data/generation_selection_store.dart';
import 'package:celechron/manual/data/storage_generation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory root;
  late StorageGenerationManifest legacy;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('generation-selection-');
    legacy = StorageGenerationManifest.legacyActive(
      rootDirectory: root.path,
    );
    Hive.init(root.path);
  });

  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test('selects fallback before first commit and new generation after restart',
      () async {
    final oldData = File('${legacy.generationDirectory}/keep-user-data.txt');
    await oldData.writeAsString('keep');
    final store = GenerationSelectionStore(rootDirectory: root.path);
    final initial = await store.selectActive(fallback: legacy);
    expect(initial.active.generationId, legacy.generationId);
    expect(initial.usedFallback, isTrue);

    final candidate = StorageGenerationManifest.candidateFor(
      active: legacy,
      generationId: 'candidate-1',
    );
    final committed = await store.commitCandidate(
      currentActive: legacy,
      candidate: candidate,
    );
    expect(committed.sequence, 1);
    expect(committed.active.generationId, 'candidate-1');
    expect(committed.active.role, StorageGenerationRole.active);

    await Hive.close();
    Hive.init(root.path);
    final restarted = await store.selectActive(fallback: legacy);
    expect(restarted.active.generationId, 'candidate-1');
    expect(restarted.usedFallback, isFalse);
    expect(await oldData.readAsString(), 'keep');
  });

  test('rejects a selection store rooted outside its active data root',
      () async {
    final otherRoot =
        await Directory.systemTemp.createTemp('other-generation-');
    addTearDown(() => otherRoot.delete(recursive: true));
    final outsideActive = StorageGenerationManifest.legacyActive(
      rootDirectory: otherRoot.path,
    );
    final outsideCandidate = StorageGenerationManifest.candidateFor(
      active: outsideActive,
      generationId: 'outside-candidate',
    );

    await expectLater(
      GenerationSelectionStore(rootDirectory: root.path).commitCandidate(
        currentActive: outsideActive,
        candidate: outsideCandidate,
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('interruption before commit keeps the last complete generation',
      () async {
    final store = GenerationSelectionStore(rootDirectory: root.path);
    final firstCandidate = StorageGenerationManifest.candidateFor(
      active: legacy,
      generationId: 'candidate-1',
    );
    final first = await store.commitCandidate(
      currentActive: legacy,
      candidate: firstCandidate,
    );
    final secondActive = first.active;
    final secondCandidate = StorageGenerationManifest.candidateFor(
      active: secondActive,
      generationId: 'candidate-2',
    );
    final interruptedStore = GenerationSelectionStore(
      rootDirectory: root.path,
      afterWritePhase: (phase) async {
        if (phase == GenerationSelectionWritePhase.recordFlushed) {
          throw StateError('simulated interruption before valid marker');
        }
      },
    );

    await expectLater(
      interruptedStore.commitCandidate(
        currentActive: secondActive,
        candidate: secondCandidate,
      ),
      throwsA(isA<StateError>()),
    );
    final selected = await store.selectActive(fallback: legacy);
    expect(selected.active.generationId, 'candidate-1');
    expect(selected.sequence, 1);
  });

  test('interruption after commit selects the complete new generation',
      () async {
    final candidate = StorageGenerationManifest.candidateFor(
      active: legacy,
      generationId: 'candidate-1',
    );
    final interruptedStore = GenerationSelectionStore(
      rootDirectory: root.path,
      afterWritePhase: (phase) async {
        if (phase == GenerationSelectionWritePhase.newSlotCommitted) {
          throw StateError('simulated interruption after commit');
        }
      },
    );

    await expectLater(
      interruptedStore.commitCandidate(
        currentActive: legacy,
        candidate: candidate,
      ),
      throwsA(isA<StateError>()),
    );
    final selected = await GenerationSelectionStore(rootDirectory: root.path)
        .selectActive(fallback: legacy);
    expect(selected.active.generationId, 'candidate-1');
    expect(selected.sequence, 1);
  });

  test('corrupt latest checksum falls back to previous valid slot', () async {
    final store = GenerationSelectionStore(rootDirectory: root.path);
    final firstCandidate = StorageGenerationManifest.candidateFor(
      active: legacy,
      generationId: 'candidate-1',
    );
    final first = await store.commitCandidate(
      currentActive: legacy,
      candidate: firstCandidate,
    );
    final secondCandidate = StorageGenerationManifest.candidateFor(
      active: first.active,
      generationId: 'candidate-2',
    );
    final second = await store.commitCandidate(
      currentActive: first.active,
      candidate: secondCandidate,
    );
    final box = await Hive.openBox<String>(
      GenerationSelectionStore.boxName,
      path: root.path,
    );
    await box.put('slot-${second.slot}-checksum', 'corrupted');
    await box.flush();
    await box.close();

    final selected = await store.selectActive(fallback: legacy);
    expect(selected.active.generationId, 'candidate-1');
    expect(selected.sequence, 1);
  });
}
