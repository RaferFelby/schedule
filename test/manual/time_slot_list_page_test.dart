import 'dart:convert';

import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/model/session_rule.dart';
import 'package:celechron/manual/model/time_slot.dart';
import 'package:celechron/manual/page/time_slot_list_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Store implements AcademicProfileStore {
  _Store([this.value]);

  String? value;

  @override
  Future<String?> readSnapshot() async => value;

  @override
  Future<void> writeSnapshot(String encoded) async => value = encoded;
}

AcademicProfile _referencedProfile() {
  const semesterId = '10000000-0000-4000-8000-000000000001';
  const courseId = '20000000-0000-4000-8000-000000000001';
  return AcademicProfile(
    schemaVersion: 1,
    revision: 3,
    currentSemesterId: semesterId,
    semesters: [
      LocalSemester(
        id: semesterId,
        name: '秋季学期',
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2027, 1, 31),
        weekOneStart: DateTime(2026, 8, 31),
      ),
    ],
    timeSlots: TimeSlot.defaultTemplate(),
    courses: [LocalCourse(id: courseId, semesterId: semesterId, name: '课程')],
    sessionRules: [
      SessionRule(
        id: '30000000-0000-4000-8000-000000000001',
        courseId: courseId,
        weekday: DateTime.monday,
        weekNumbers: [1],
        startSlotOrdinal: 1,
        endSlotOrdinal: 2,
      ),
    ],
  );
}

void main() {
  group('TimeSlotListPage', () {
    testWidgets('edits and persists the first default period', (tester) async {
      final store = _Store();
      final repository = AcademicRepository(store);
      await tester.pumpWidget(
          CupertinoApp(home: TimeSlotListPage(repository: repository)));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('edit-slot-1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('slot-start')), '08:10');
      await tester.enterText(find.byKey(const ValueKey('slot-end')), '08:55');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final saved = AcademicProfile.fromJson(
        jsonDecode(store.value!) as Map<String, dynamic>,
      );
      expect(saved.revision, 1);
      expect(saved.timeSlots, hasLength(15));
      expect(saved.timeSlots.first.startMinute, 490);
      expect(saved.timeSlots.first.endMinute, 535);
    });

    testWidgets('blocks deletion of a period referenced by a session rule',
        (tester) async {
      final original = _referencedProfile();
      final encoded = jsonEncode(original.toJson());
      final store = _Store(encoded);
      await tester.pumpWidget(
        CupertinoApp(
            home: TimeSlotListPage(repository: AcademicRepository(store))),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('delete-slot-1')));
      await tester.pumpAndSettle();

      expect(find.text('已有上课规则引用该节次，请先修改或移除规则。'), findsOneWidget);
      expect(store.value, encoded);
    });

    testWidgets('deletes an unreferenced period after confirmation',
        (tester) async {
      final original = _referencedProfile();
      final store = _Store(jsonEncode(original.toJson()));
      await tester.pumpWidget(
        CupertinoApp(
            home: TimeSlotListPage(repository: AcademicRepository(store))),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('delete-slot-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-delete-slot')));
      await tester.pumpAndSettle();

      final saved = AcademicProfile.fromJson(
        jsonDecode(store.value!) as Map<String, dynamic>,
      );
      expect(saved.revision, 4);
      expect(saved.timeSlots, hasLength(14));
      expect(saved.timeSlots.any((slot) => slot.ordinal == 3), isFalse);
      expect(saved.sessionRules, hasLength(1));
    });
  });
}
