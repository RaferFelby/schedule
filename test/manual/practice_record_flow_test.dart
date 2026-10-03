import 'dart:convert';

import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/practice_record.dart';
import 'package:celechron/manual/page/practice_record_list_page.dart';
import 'package:celechron/manual/service/practice_points_calculator.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Store implements AcademicProfileStore {
  String? value;

  @override
  Future<String?> readSnapshot() async => value;

  @override
  Future<void> writeSnapshot(String encoded) async => value = encoded;
}

void main() {
  testWidgets('saves and reloads approved and pending practice records',
      (tester) async {
    final store = _Store()
      ..value =
          jsonEncode(AcademicProfile(schemaVersion: 1, revision: 0).toJson());
    final repository = AcademicRepository(store);
    await tester.pumpWidget(CupertinoApp(
      home: PracticeRecordListPage(repository: repository),
    ));
    await tester.pumpAndSettle();
    expect(find.text('暂无实践记录'), findsOneWidget);

    Future<void> addRecord(
        {required String project, required bool approved}) async {
      await tester.tap(find.byKey(const ValueKey('practice-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('practice-category')), '志愿服务');
      await tester.enterText(
          find.byKey(const ValueKey('practice-project')), project);
      await tester.enterText(
          find.byKey(const ValueKey('practice-date')), '2026-09-10');
      await tester.enterText(
          find.byKey(const ValueKey('practice-points')), '1.5');
      tester.testTextInput.hide();
      await tester.pump();
      if (approved) {
        await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('practice-status')),
          matching: find.text('通过'),
        ));
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('practice-save')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('practice-save')));
      await tester.pumpAndSettle();
    }

    await addRecord(project: '待审核项目', approved: false);
    await addRecord(project: '已通过项目', approved: true);

    final reloaded = await AcademicRepository(store).read();
    expect(reloaded.practiceRecords, hasLength(2));
    expect(
      reloaded.practiceRecords.map((record) => record.status).toSet(),
      {PracticeReviewStatus.pending, PracticeReviewStatus.approved},
    );
    expect(reloaded.practiceRecords.every((record) => record.points == 1.5),
        isTrue);
    expect(
        reloaded.practiceRecords
            .every((record) => record.artsStatus == RequirementStatus.unknown),
        isTrue);
    expect(find.text('志愿服务 · 已通过项目'), findsOneWidget);
    expect(find.text('审核状态：待审核'), findsOneWidget);
    expect(find.textContaining('通过项目合计：1.5'), findsOneWidget);
  });

  testWidgets('edits, cancels and deletes only the target practice record',
      (tester) async {
    final target = PracticeRecord(
      id: '60000000-0000-4000-8000-000000000001',
      category: '志愿服务',
      projectName: '原项目',
      date: DateTime(2026, 9, 10),
      points: 1.5,
      status: PracticeReviewStatus.pending,
    );
    final other = PracticeRecord(
      id: '60000000-0000-4000-8000-000000000002',
      category: '竞赛',
      projectName: '保留项目',
      date: DateTime(2026, 9, 11),
      points: 2,
      status: PracticeReviewStatus.approved,
    );
    final store = _Store()
      ..value = jsonEncode(AcademicProfile(
        schemaVersion: 1,
        revision: 0,
        practiceRecords: [target, other],
      ).toJson());
    final repository = AcademicRepository(store);
    await tester.pumpWidget(CupertinoApp(
      home: PracticeRecordListPage(repository: repository),
    ));
    await tester.pumpAndSettle();

    final editKey = find.byKey(ValueKey('practice-edit-${target.id}'));
    await tester.scrollUntilVisible(editKey, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(editKey);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('practice-project')), '取消的修改');
    await tester.tap(find.byKey(const ValueKey('practice-cancel')));
    await tester.pumpAndSettle();
    expect((await repository.read()).revision, 0);
    expect(find.text('志愿服务 · 原项目'), findsOneWidget);

    await tester.scrollUntilVisible(
      editKey,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(editKey);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('practice-project')), '修改项目');
    await tester.enterText(
        find.byKey(const ValueKey('practice-points')), '2.25');
    tester.testTextInput.hide();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('practice-save')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('practice-save')));
    await tester.pumpAndSettle();
    final updated = await repository.read();
    expect(updated.practiceRecords, hasLength(2));
    final edited =
        updated.practiceRecords.singleWhere((record) => record.id == target.id);
    expect(edited.projectName, '修改项目');
    expect(edited.points, 2.25);
    expect(edited.status, PracticeReviewStatus.pending);
    expect(
        updated.practiceRecords
            .singleWhere((record) => record.id == other.id)
            .projectName,
        '保留项目');

    final deleteKey = find.byKey(ValueKey('practice-delete-${target.id}'));
    await tester.scrollUntilVisible(
      deleteKey,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(deleteKey);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect((await repository.read()).practiceRecords, hasLength(2));

    await tester.scrollUntilVisible(
      deleteKey,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(deleteKey);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    final deleted = await repository.read();
    expect(deleted.practiceRecords, hasLength(1));
    expect(deleted.practiceRecords.single.id, other.id);
    expect(
        deleted.practiceRecords.single.status, PracticeReviewStatus.approved);
  });

  testWidgets('arts and labor states are independent of practice points',
      (tester) async {
    final record = PracticeRecord(
      id: '60000000-0000-4000-8000-000000000003',
      category: '志愿服务',
      projectName: '社区服务',
      date: DateTime(2026, 9, 12),
      points: 1.5,
      status: PracticeReviewStatus.approved,
    );
    final store = _Store()
      ..value = jsonEncode(AcademicProfile(
        schemaVersion: 1,
        revision: 0,
        practiceRecords: [record],
      ).toJson());
    final repository = AcademicRepository(store);
    await tester.pumpWidget(CupertinoApp(
      home: PracticeRecordListPage(repository: repository),
    ));
    await tester.pumpAndSettle();
    final editKey = find.byKey(ValueKey('practice-edit-${record.id}'));
    await tester.tap(editKey);
    await tester.pumpAndSettle();
    final arts = find.byKey(const ValueKey('practice-arts-status'));
    await tester.scrollUntilVisible(arts, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.descendant(of: arts, matching: find.text('通过')));
    await tester.pumpAndSettle();
    final labor = find.byKey(const ValueKey('practice-labor-status'));
    await tester.scrollUntilVisible(labor, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.descendant(of: labor, matching: find.text('未通过')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('practice-save')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('practice-save')));
    await tester.pumpAndSettle();

    final updated = (await repository.read()).practiceRecords.single;
    expect(updated.id, record.id);
    expect(updated.points, 1.5);
    expect(updated.artsStatus, RequirementStatus.passed);
    expect(updated.laborStatus, RequirementStatus.notPassed);
    expect(PracticePointsCalculator.calculate([updated]).total, 1.5);
  });
}
