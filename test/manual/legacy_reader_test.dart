import 'dart:convert';
import 'dart:io';

import 'package:celechron/manual/migration/legacy_reader.dart';
import 'package:celechron/manual/migration/legacy_scholar_record.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/model/todo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory temporaryRoot;
  late Directory source;
  late Directory backup;

  setUp(() async {
    temporaryRoot = await Directory.systemTemp.createTemp('legacy-reader-');
    source = Directory('${temporaryRoot.path}/old-hive');
    backup = Directory('${temporaryRoot.path}/snapshot');
    await source.create();
    Hive.init(source.path);
    LegacyHiveSnapshotReader.registerLegacyAdapters(Hive);
    final scholarBox = await Hive.openBox('dbUser');
    await scholarBox.put(
      'user',
      LegacyScholarRecord({
        'username': 'synthetic-account',
        'password': 'synthetic-password',
        'todos': [
          Todo.fromJson({
            'id': 'synthetic-todo',
            'title': '作业',
            'course_name': '课程文本',
            'end_time': '2026-10-10T12:00:00.000',
          }),
        ],
      }),
    );
    final optionsBox = await Hive.openBox('dbOptions');
    await optionsBox.put('syntheticOption', 'preserve-me');
    await optionsBox.put('gpaStrategy', 1);
    await optionsBox.put('brightnessMode', 2);
    await optionsBox.put('workTime', const Duration(minutes: 50));
    await optionsBox.put('restTime', const Duration(minutes: 10));
    await optionsBox.put('allowTime', {
      DateTime(0, 1, 1, 8): DateTime(0, 1, 1, 12),
    });
    await optionsBox.put('asyncRefresh', true);
    await optionsBox.put('pushOnGradeChange', true);
    final taskBox = await Hive.openBox('dbDeadline');
    final taskDate = DateTime(2026, 10, 10);
    await taskBox.put('deadlineList', [
      Task(
        uid: 'synthetic-task',
        endTime: taskDate,
        startTime: taskDate,
        repeatEndsTime: taskDate,
      ),
    ]);
    final cacheBox = await Hive.openBox('dbOriginalWebPage');
    await cacheBox.put('syntheticCache', '<html>constructed</html>');
    await Future.wait([
      scholarBox.flush(),
      optionsBox.flush(),
      cacheBox.flush(),
    ]);
  });

  tearDown(() async {
    await Hive.close();
    await temporaryRoot.delete(recursive: true);
  });

  test(
      'backs up old boxes byte-for-byte and writes a credential-free scholar projection',
      () async {
    final sourceFiles = [
      File('${source.path}/dbUser.hive'),
      File('${source.path}/dbOptions.hive'),
      File('${source.path}/dbDeadline.hive'),
      File('${source.path}/dbOriginalWebPage.hive'),
    ];
    final beforeBytes = {
      for (final file in sourceFiles)
        file.uri.pathSegments.last: await file.readAsBytes(),
    };
    final beforeKeys = {
      'dbUser': Hive.box('dbUser').keys.toList(),
      'dbOptions': Hive.box('dbOptions').keys.toList(),
      'dbDeadline': Hive.box('dbDeadline').keys.toList(),
      'dbOriginalWebPage': Hive.box('dbOriginalWebPage').keys.toList(),
    };

    final result = await const LegacyHiveSnapshotReader().createBackup(
      sourceDirectory: source.path,
      destinationDirectory: backup.path,
    );

    expect(result.boxFiles, 4);
    expect(result.scholarProjectionWritten, isTrue);
    for (final file in sourceFiles) {
      expect(await file.readAsBytes(), beforeBytes[file.uri.pathSegments.last]);
    }
    expect(Hive.box('dbUser').keys.toList(), beforeKeys['dbUser']);
    expect(Hive.box('dbOptions').get('syntheticOption'), 'preserve-me');
    expect(Hive.box('dbDeadline').get('deadlineList'), hasLength(1));
    expect(
      Hive.box('dbOriginalWebPage').get('syntheticCache'),
      '<html>constructed</html>',
    );

    final projectionFile = File(
      '${backup.path}/${LegacyHiveSnapshotReader.projectionFileName}',
    );
    final projectionText = await projectionFile.readAsString();
    final projection = jsonDecode(projectionText) as Map<String, dynamic>;
    expect(projection['containsCredentials'], isFalse);
    expect(projectionText, isNot(contains('synthetic-account')));
    expect(projectionText, isNot(contains('synthetic-password')));
    expect((projection['scholar'] as Map).containsKey('username'), isFalse);
    expect((projection['scholar'] as Map).containsKey('password'), isFalse);
    expect(
      await File('${backup.path}/boxes/dbOptions.hive').readAsBytes(),
      beforeBytes['dbOptions.hive'],
    );
    expect(
      await File('${backup.path}/boxes/dbOriginalWebPage.hive').readAsBytes(),
      beforeBytes['dbOriginalWebPage.hive'],
    );
    expect(
      await File('${backup.path}/boxes/dbUser.hive').exists(),
      isFalse,
    );
    final manifest = jsonDecode(
      await File(
        '${backup.path}/${LegacyHiveSnapshotReader.manifestFileName}',
      ).readAsString(),
    ) as Map<String, dynamic>;
    expect(manifest['secureStorageCopied'], isFalse);

    await Hive.close();
    final input = await const LegacyHiveSnapshotReader().readBackup(
      backupDirectory: backup.path,
    );
    expect(input.scholar.containsKey('username'), isFalse);
    expect(input.scholar.containsKey('password'), isFalse);
    expect(input.tasks.single.uid, 'synthetic-task');
    expect(input.todos.single.id, 'synthetic-todo');
    expect(
        input.options.keys,
        containsAll([
          'gpaStrategy',
          'brightnessMode',
          'workTime',
          'restTime',
          'allowTime',
        ]));
    expect(input.options.containsKey('asyncRefresh'), isFalse);
    expect(input.options.containsKey('pushOnGradeChange'), isFalse);
    expect(input.options.containsKey('syntheticOption'), isFalse);
  });

  test('refuses existing or source-nested backup destinations', () async {
    await backup.create();
    await expectLater(
      const LegacyHiveSnapshotReader().createBackup(
        sourceDirectory: source.path,
        destinationDirectory: backup.path,
      ),
      throwsA(isA<Exception>()),
    );
    await backup.delete();
    await expectLater(
      const LegacyHiveSnapshotReader().createBackup(
        sourceDirectory: source.path,
        destinationDirectory: '${source.path}/nested-backup',
      ),
      throwsA(isA<Exception>()),
    );
  });
}
