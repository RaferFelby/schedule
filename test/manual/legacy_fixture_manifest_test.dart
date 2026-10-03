import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy migration fixtures are synthetic and enumerate expected counts',
      () {
    final manifest = jsonDecode(
      File('test/fixtures/legacy_migration_manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['fixtureSet'], 'celechron-legacy-migration-synthetic-v1');
    expect(manifest['syntheticOnly'], isTrue);
    expect(manifest['containsRealUserData'], isFalse);

    final cases = (manifest['cases'] as List).cast<Map<String, dynamic>>();
    expect(cases, hasLength(5));
    final coverage = cases.expand((item) => item['coverage'] as List).toSet();
    expect(
        coverage,
        containsAll({
          'missingSemesterDates',
          'missingCourseId',
          'duplicateCourseNames',
          'gradesWithoutSemester',
          'partialCache',
          'nullEntry',
          'wrongFieldType',
        }));

    for (final item in cases) {
      final fixture = jsonDecode(
        File('test/fixtures/${item['file']}').readAsStringSync(),
      );
      expect(fixture, isA<Map>(), reason: item['id'] as String);
      final data = Map<String, dynamic>.from(fixture as Map);
      final expected = item['expected'] as Map<String, dynamic>;
      expect(
          expected.keys,
          containsAll({
            'sourceRecordCount',
            'readableRecords',
            'needsReview',
            'invalidRecords',
          }));
      final sourceRecords = switch (item['id']) {
        'missing-fields' => (data['semesterList'] as List).length +
            (data['courses'] as List).length,
        'same-name-courses' => (data['courses'] as List).length,
        'grades-without-semester' => (data['grades'] as List).length,
        'corrupt-records' => (data['grades'] as List).length,
        'partial-cache' =>
          (data['courses'] as List).length + (data['sessions'] as List).length,
        _ => throw StateError('Unexpected legacy fixture ${item['id']}'),
      };
      expect(
        expected['sourceRecordCount'],
        sourceRecords,
        reason: item['id'] as String,
      );
    }
  });

  test('fixtures use constructed identifiers and exclude credential fields',
      () {
    final directory = Directory('test/fixtures');
    final legacyFiles = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.uri.pathSegments.last.startsWith('legacy_'));
    expect(legacyFiles, isNotEmpty);
    for (final file in legacyFiles) {
      final content = file.readAsStringSync().toLowerCase();
      expect(content, isNot(contains('password')), reason: file.path);
      expect(content, isNot(contains('cookie')), reason: file.path);
      expect(content, isNot(contains('access_token')), reason: file.path);
      expect(content, isNot(contains('studentnumber')), reason: file.path);
    }
  });
}
