import 'dart:convert';

import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:celechron/manual/model/time_slot.dart';
import 'package:celechron/manual/page/course_list_page.dart';
import 'package:celechron/manual/page/manual_course_schedule_page.dart';
import 'package:celechron/manual/service/manual_calendar_period_adapter.dart';
import 'package:celechron/manual/service/local_schedule_device_sync_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Store implements AcademicProfileStore {
  _Store([AcademicProfile? profile])
      : value = jsonEncode((profile ?? _profile()).toJson());
  String value;
  int writes = 0;
  @override
  Future<String?> readSnapshot() async => value;
  @override
  Future<void> writeSnapshot(String encoded) async {
    writes++;
    value = encoded;
  }
}

AcademicProfile _profile() => AcademicProfile(
      schemaVersion: 1,
      revision: 0,
      semesters: [
        LocalSemester(
          id: '10000000-0000-4000-8000-000000000001',
          name: '合成学期',
          startDate: DateTime(2026, 9, 7),
          endDate: DateTime(2027, 1, 3),
          weekOneStart: DateTime(2026, 9, 7),
        ),
      ],
    );

Map<String, Object> _document(String name) {
  Map<String, Object> span(String text, double x, double y) => {
        'text': text,
        'x': x - .025,
        'y': y,
        'width': .05,
        'height': .015,
      };
  return {
    'pages': [
      {
        'index': 0,
        'rotation': 90,
        'source': 'pdf',
        'spans': [
          for (var day = 1; day <= 7; day++)
            span('星期${'一二三四五六日'[day - 1]}', day * .1, .1),
          span(name, .1, .2),
          span('(1-2节)1,3,5周', .1, .23),
          span('教师:合成教师/地点:教学楼A/教学班:C12345', .1, .26),
        ],
      },
    ],
  };
}

const _channel = MethodChannel('top.celechron/pdf_timetable');
const _confirmKey = ValueKey('confirm-pdf-import');
Finder _field(String label) => find.byKey(ValueKey('$label-pdf-course-1'));

Future<void> _open(WidgetTester tester, _Store store) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    CupertinoApp(
      home: CourseListPage(
        repository: AcademicRepository(store),
        semester: _profile().semesters.single,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('course-import-pdf')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  testWidgets('reviewed PDF creates saved rules and a visible timetable', (
    tester,
  ) async {
    final store = _Store();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async => _document('合成课程'));
    await _open(tester, store);
    expect(store.writes, 0);
    expect(find.textContaining('已识别 1 门课程'), findsOneWidget);
    await tester.ensureVisible(find.byKey(_confirmKey));
    await tester.tap(find.byKey(_confirmKey));
    await tester.pumpAndSettle();
    expect(store.writes, 0);
    await tester.tap(find.text('确认导入'));
    await tester.pumpAndSettle();
    expect(store.writes, 1);
    final repository = AcademicRepository(store);
    final saved = await repository.read();
    expect(saved.sessionRules.single.weekNumbers, [1, 3, 5]);
    expect(saved.sessionRules.single.teacher, '合成教师');
    final periods = await ManualCalendarPeriodAdapter(repository).readPeriods();
    expect(periods, hasLength(3));
    expect(periods.first.startTime, DateTime(2026, 9, 7, 8));
    var sent = false;
    await LocalScheduleDeviceSyncService(repository, sender: (message) async {
      sent = true;
      expect(message.flowListDto, hasLength(3));
      return true;
    }).sync();
    expect(sent, isTrue);
    await tester.pumpWidget(
      MaterialApp(home: ManualCourseSchedulePage(repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('合成课程'), findsOneWidget);
    expect(find.text('教师：合成教师'), findsOneWidget);
    expect(find.text('教学楼A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reselecting a PDF replaces form values with the new draft', (
    tester,
  ) async {
    final store = _Store();
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _channel,
      (_) async => _document(++calls == 1 ? '旧课程' : '新课程'),
    );
    await _open(tester, store);
    await tester.enterText(_field('课程名称（必填）'), '已编辑的旧课程');
    await tester.tap(find.text('重选 PDF'));
    await tester.pumpAndSettle();
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: _field('课程名称（必填）'),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.controller.text, '新课程');
    expect(store.writes, 0);
  });

  testWidgets(
    'invalid weeks or credits block saving; valid ranges can be completed',
    (tester) async {
      final store = _Store();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (_) async => _document('合成课程'));
      await _open(tester, store);
      final weeks = find.byKey(const ValueKey('周次，如 1,3,5-pdf-session-1'));
      await tester.enterText(weeks, '1,错误,3');
      await tester.pump();
      expect(
        tester.widget<CupertinoButton>(find.byKey(_confirmKey)).onPressed,
        isNull,
      );
      await tester.enterText(weeks, '1-3');
      await tester.enterText(_field('学分（可选）'), '-1');
      await tester.pump();
      expect(
        tester.widget<CupertinoButton>(find.byKey(_confirmKey)).onPressed,
        isNull,
      );
      await tester.enterText(_field('学分（可选）'), '3.5');
      await tester.pump();
      expect(
        tester.widget<CupertinoButton>(find.byKey(_confirmKey)).onPressed,
        isNotNull,
      );
      expect(store.writes, 0);
    },
  );

  testWidgets('file selection cancellation writes nothing', (tester) async {
    final store = _Store();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async => null);
    await _open(tester, store);
    expect(store.writes, 0);
    expect(find.text('这个学期还没有课程'), findsOneWidget);
  });

  testWidgets('draft fits an iPhone-sized viewport without overflow',
      (tester) async {
    final store = _Store();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async => _document('合成课程'));
    await _open(tester, store);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final label in ['周次，如 1,3,5', '起始节次']) {
      final input = find.descendant(
        of: find.byKey(ValueKey('$label-pdf-session-1')),
        matching: find.byType(EditableText),
      );
      expect(tester.getSize(input).width, greaterThanOrEqualTo(48),
          reason: 'iPhone 上的输入区域必须保留可读宽度');
    }
    expect(store.writes, 0);
  });

  testWidgets('leaving a reviewed draft does not save courses', (tester) async {
    final store = _Store();
    final original = store.value;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async => _document('合成课程'));
    await _open(tester, store);
    await tester.tap(find.byType(CupertinoNavigationBarBackButton));
    await tester.pumpAndSettle();
    expect(store.value, original);
    expect(store.writes, 0);
  });

  testWidgets(
      'a suspected duplicate can be skipped without changing existing courses',
      (tester) async {
    final initial = _profile();
    final store = _Store(AcademicProfile(
      schemaVersion: 1,
      revision: 0,
      semesters: initial.semesters,
      courses: [
        LocalCourse(
          id: '20000000-0000-4000-8000-000000000001',
          semesterId: initial.semesters.single.id,
          name: '合成课程',
        )
      ],
    ));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async => _document('合成课程'));
    await _open(tester, store);
    expect(find.textContaining('疑似与本学期已有课程重复'), findsOneWidget);
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pump();
    expect(tester.widget<CupertinoButton>(find.byKey(_confirmKey)).onPressed,
        isNull);
    expect(store.writes, 0);
  });

  testWidgets(
      'encrypted file reports its reason and allows selecting another PDF',
      (tester) async {
    final store = _Store();
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async {
      if (++calls == 1) {
        throw PlatformException(code: 'encrypted_pdf', message: 'PDF 已加密或需要密码');
      }
      return _document('合成课程');
    });
    await _open(tester, store);
    expect(find.text('PDF 已加密或需要密码'), findsOneWidget);
    await tester.tap(find.text('重新选择文件'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已识别 1 门课程'), findsOneWidget);
    expect(store.writes, 0);
  });

  testWidgets('missing section times block import and offer configuration',
      (tester) async {
    final initial = _profile();
    final store = _Store(AcademicProfile(
      schemaVersion: 1,
      revision: 0,
      semesters: initial.semesters,
      timeSlots: [TimeSlot.defaultTemplate().first],
    ));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async => _document('合成课程'));
    await _open(tester, store);
    expect(tester.widget<CupertinoButton>(find.byKey(_confirmKey)).onPressed,
        isNull);
    expect(
        find.byKey(const ValueKey('configure-import-slots')), findsOneWidget);
    expect(store.writes, 0);
  });

  testWidgets('removing and adding arrangements keeps unique editor identities',
      (tester) async {
    final store = _Store();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async => _document('合成课程'));
    await _open(tester, store);
    final add = find.byKey(const ValueKey('add-session-pdf-course-1'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pump();
    await tester.ensureVisible(find.text('删除此安排').first);
    await tester.tap(find.text('删除此安排').first);
    await tester.pump();
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pump();
    expect(find.text('上课安排 · 待补全'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    expect(store.writes, 0);
  });
}
