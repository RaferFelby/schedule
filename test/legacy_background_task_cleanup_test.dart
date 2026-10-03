import 'dart:io';

import 'package:celechron/services/legacy_background_task_cleanup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late _Canceller canceller;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('legacy-task-cleanup-');
    Hive.init(directory.path);
    canceller = _Canceller();
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('cancels only once after persisting the completion marker', () async {
    final service = LegacyBackgroundTaskCleanup(canceller: canceller);

    expect(await service.run(), isTrue);
    expect(
        await LegacyBackgroundTaskCleanup(canceller: canceller).run(), isFalse);
    expect(canceller.calls, 1);
    expect(canceller.names, [legacyBackgroundScholarTaskName]);
    expect(await Hive.boxExists(LegacyBackgroundTaskCleanup.boxName), isTrue);
  });

  test('cancellation failure leaves no marker and retries next run', () async {
    canceller.failuresRemaining = 1;
    final service = LegacyBackgroundTaskCleanup(canceller: canceller);

    await expectLater(service.run(), throwsStateError);
    final markerBox = await Hive.openBox<String>(
      LegacyBackgroundTaskCleanup.boxName,
    );
    expect(markerBox.get(LegacyBackgroundTaskCleanup.completionKey), isNull);
    await markerBox.close();
    expect(await service.run(), isTrue);
    expect(canceller.calls, 2);
  });
}

final class _Canceller implements BackgroundTaskCanceller {
  int calls = 0;
  int failuresRemaining = 0;
  final names = <String>[];

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    calls++;
    names.add(uniqueName);
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('cancel failed');
    }
  }
}
