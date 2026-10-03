import 'package:celechron/manual/migration/legacy_migration_assembler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const assembler = LegacyMigrationAssembler();

  test('assembles an explicitly dated empty term and stable report', () {
    final scholar = <String, Object?>{
      'semesters': [
        {
          'name': '短学期',
          'startDate': '2026-09-01',
          'endDate': '2026-10-01',
          'weekOneStart': '2026-08-31',
          'courses': <String, Object?>{},
        },
      ],
    };

    final first = assembler.assemble(scholar: scholar);
    final second = assembler.assemble(scholar: scholar);

    expect(first.profile.semesters, hasLength(1));
    expect(first.profile.currentSemesterId, isNull);
    expect(
        first.profile.semesters.single.id, second.profile.semesters.single.id);
    expect(first.report.counts['学期']?.sourceRecords, 1);
    expect(first.report.counts['学期']?.convertedRecords, 1);
    expect(first.report.blockingCount, 0);
    expect(first.reviewItems, contains(contains('当前学期留空')));
  });

  test('blocks records that cannot be converted without guessing dates', () {
    final result = assembler.assemble(
      scholar: <String, Object?>{
        'semesters': [
          {
            'name': '2026秋冬',
            'courses': <String, Object?>{},
          },
        ],
      },
    );

    expect(result.profile.semesters, isEmpty);
    expect(result.report.blockingCount, greaterThan(0));
    expect(
        result.report.issues.any(
          (issue) => issue.code.startsWith('legacy-unresolved:学期:'),
        ),
        isTrue);
  });

  test('imports only local appearance and planning preferences', () {
    final result = assembler.assemble(
      scholar: const {},
      legacyOptions: {
        'brightnessMode': 1,
        'workTime': const Duration(minutes: 45),
        'restTime': const Duration(minutes: 15),
        'allowTime': {
          DateTime(0, 1, 1, 9): DateTime(0, 1, 1, 12),
        },
        'asyncRefresh': true,
        'pushOnGradeChange': true,
      },
    );
    expect(result.settings, {
      'theme': 'light',
      'workMinutes': 45,
      'restMinutes': 15,
      'availableWindows': [
        {'startMinutes': 540, 'endMinutes': 720},
      ],
    });
  });
}
