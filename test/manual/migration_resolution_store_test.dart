import 'dart:io';

import 'package:celechron/manual/migration/migration_resolution_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('migration-resolution-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('persists unique skip decisions and reads them after recreation',
      () async {
    final path = '${directory.path}/${MigrationResolutionStore.fileName}';
    final store = MigrationResolutionStore(path);
    const issue = 'legacy-unresolved:学期:0';

    expect(await store.skipIssue(issue), {issue});
    expect(await MigrationResolutionStore(path).skipIssue(issue), {issue});
    expect(
        await MigrationResolutionStore(path).readSkippedIssueCodes(), {issue});
  });

  test('refuses decisions for structural validation issues', () async {
    final store = MigrationResolutionStore(
      '${directory.path}/${MigrationResolutionStore.fileName}',
    );

    await expectLater(
      store.skipIssue('missing-course-semester:course-1'),
      throwsArgumentError,
    );
    expect(await store.readSkippedIssueCodes(), isEmpty);
  });

  test('persists correction records alongside skip decisions', () async {
    final path = '${directory.path}/${MigrationResolutionStore.fileName}';
    final store = MigrationResolutionStore(path);
    const issue = 'legacy-unresolved:学期:0';
    final corrected = {
      'name': '旧学期',
      'startDate': '2026-09-01',
      'endDate': '2027-01-15',
      'weekOneStart': '2026-08-31',
    };

    await store.skipIssue('legacy-unresolved:课程:2');
    await store.saveCorrection(issue, corrected);

    final reopened = MigrationResolutionStore(path);
    expect(await reopened.readSkippedIssueCodes(),
        {'legacy-unresolved:课程:2'});
    expect(await reopened.readCorrections(), {issue: corrected});
  });
}
