import 'package:hive/hive.dart';
import 'package:workmanager/workmanager.dart';

const legacyBackgroundScholarTaskName =
    'top.celechron.celechron.backgroundScholarFetch';

abstract interface class BackgroundTaskCanceller {
  Future<void> cancelByUniqueName(String uniqueName);
}

final class WorkmanagerTaskCanceller implements BackgroundTaskCanceller {
  const WorkmanagerTaskCanceller();

  @override
  Future<void> cancelByUniqueName(String uniqueName) =>
      Workmanager().cancelByUniqueName(uniqueName);
}

/// Retries cancellation until its success marker is durably stored.
final class LegacyBackgroundTaskCleanup {
  const LegacyBackgroundTaskCleanup({
    this.canceller = const WorkmanagerTaskCanceller(),
    this.hive,
  });

  static const boxName = 'legacy-background-cleanup-v1';
  static const completionKey = 'cancelled:$legacyBackgroundScholarTaskName';

  final BackgroundTaskCanceller canceller;
  final HiveInterface? hive;

  Future<bool> run() async {
    final box = await (hive ?? Hive).openBox<String>(boxName);
    try {
      if (box.get(completionKey) == 'true') return false;
      await canceller.cancelByUniqueName(legacyBackgroundScholarTaskName);
      await box.put(completionKey, 'true');
      await box.flush();
      return true;
    } finally {
      await box.close();
    }
  }
}
