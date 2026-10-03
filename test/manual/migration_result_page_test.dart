import 'package:celechron/manual/migration/migration_validator.dart';
import 'package:celechron/manual/page/migration_result_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('shows migration counts, blocking issues, and correction routes',
      (tester) async {
    var editedSemesters = false;
    var editedCourses = false;
    const report = MigrationValidationReport(
      counts: {
        '课程': MigrationCount(
          sourceRecords: 3,
          convertedRecords: 2,
          unresolvedRecords: 1,
        ),
      },
      issues: [
        MigrationValidationIssue(
          code: 'missing-course',
          message: '课程关联需要检查',
          blocking: true,
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: MigrationResultPage(
        report: report,
        onEditSemesters: () => editedSemesters = true,
        onEditCourses: () => editedCourses = true,
      ),
    ));

    expect(find.text('迁移候选需要处理'), findsOneWidget);
    expect(find.textContaining('来源 3 条'), findsOneWidget);
    expect(find.text('课程关联需要检查'), findsOneWidget);
    await tester.tap(find.text('检查学期日期'));
    await tester.tap(find.text('检查课程关联'));
    expect(editedSemesters, isTrue);
    expect(editedCourses, isTrue);
    expect(find.textContaining('旧数据备份会保留'), findsOneWidget);
  });

  testWidgets('hides correction actions without destinations', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MigrationResultPage(
        report: MigrationValidationReport(counts: {}, issues: []),
      ),
    ));

    expect(find.text('迁移校验完成'), findsOneWidget);
    expect(find.text('检查学期日期'), findsNothing);
    expect(find.text('检查课程关联'), findsNothing);
  });

  testWidgets('requires explicit confirmation before skipping a legacy row',
      (tester) async {
    String? skippedIssue;
    const issueCode = 'legacy-unresolved:学期:0';
    await tester.pumpWidget(MaterialApp(
      home: MigrationResultPage(
        report: const MigrationValidationReport(
          counts: {},
          issues: [
            MigrationValidationIssue(
              code: issueCode,
              message: '学期缺少日期',
              blocking: true,
            ),
          ],
        ),
        onSkipIssue: (code) async => skippedIssue = code,
      ),
    ));

    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    expect(find.text('确认跳过'), findsOneWidget);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(skippedIssue, isNull);

    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认跳过'));
    await tester.pumpAndSettle();
    expect(skippedIssue, issueCode);
  });

  testWidgets('edits a correctable source record as JSON', (tester) async {
    String? correctedIssue;
    Object? correctedRecord;
    const issueCode = 'legacy-unresolved:学期:0';
    await tester.pumpWidget(MaterialApp(
      home: MigrationResultPage(
        report: const MigrationValidationReport(
          counts: {},
          issues: [
            MigrationValidationIssue(
              code: issueCode,
              message: '学期缺少日期',
              blocking: true,
              sourcePath: ['scholar', 'semesters', 0],
              sourceRecord: {'name': '旧学期'},
            ),
          ],
        ),
        onCorrectIssue: (code, value) async {
          correctedIssue = code;
          correctedRecord = value;
        },
      ),
    ));

    await tester.tap(find.text('修正'));
    await tester.pumpAndSettle();
    final editor = tester.widget<TextField>(find.byType(TextField).last);
    final controller = editor.controller!;
    controller.text = '[]';
    await tester.tap(find.text('保存并重新校验'));
    await tester.pumpAndSettle();
    expect(find.text('这条记录必须保持 JSON 对象格式'), findsOneWidget);
    expect(correctedIssue, isNull);

    controller.text = '{"name":"旧学期","startDate":"2026-09-01"}';
    await tester.tap(find.text('保存并重新校验'));
    await tester.pumpAndSettle();

    expect(correctedIssue, issueCode);
    expect(correctedRecord, {
      'name': '旧学期',
      'startDate': '2026-09-01',
    });
  });
}
