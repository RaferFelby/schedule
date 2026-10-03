import 'dart:convert';

import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/model/session_rule.dart';
import 'package:celechron/manual/model/time_slot.dart';
import 'package:celechron/manual/page/manual_course_schedule_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Store implements AcademicProfileStore {
  _Store(this.value);
  String? value;
  @override
  Future<String?> readSnapshot() async => value;
  @override
  Future<void> writeSnapshot(String encoded) async => value = encoded;
}

AcademicProfile _profile() => AcademicProfile(
      schemaVersion: 1,
      revision: 0,
      currentSemesterId: '10000000-0000-4000-8000-000000000001',
      semesters: [
        LocalSemester(
          id: '10000000-0000-4000-8000-000000000001',
          name: '暑期班',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2027, 1, 3),
          weekOneStart: DateTime(2026, 8, 31),
        ),
      ],
      timeSlots: TimeSlot.defaultTemplate(),
      courses: [
        LocalCourse(
          id: '20000000-0000-4000-8000-000000000001',
          semesterId: '10000000-0000-4000-8000-000000000001',
          name: '第十八周课程',
        ),
      ],
      sessionRules: [
        SessionRule(
          id: '30000000-0000-4000-8000-000000000001',
          courseId: '20000000-0000-4000-8000-000000000001',
          weekday: DateTime.tuesday,
          weekNumbers: [18],
          startSlotOrdinal: 1,
          endSlotOrdinal: 1,
        ),
      ],
    );

void main() {
  testWidgets('uses explicit semester title and displays week eighteen',
      (tester) async {
    final store = _Store(jsonEncode(_profile().toJson()));
    await tester.pumpWidget(MaterialApp(
      home: ManualCourseSchedulePage(repository: AcademicRepository(store)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('暑期班 · 共 18 周'), findsOneWidget);
    expect(find.text('第十八周课程'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('schedule-week-picker')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('第 18 周'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('第 18 周'));
    await tester.pumpAndSettle();
    expect(find.text('第十八周课程'), findsOneWidget);
  });
}
