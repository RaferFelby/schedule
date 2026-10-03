import 'dart:convert';

import 'package:celechron/manual/data/academic_repository.dart';
import 'package:celechron/manual/data/local_data_error.dart';
import 'package:celechron/manual/model/academic_profile.dart';
import 'package:celechron/manual/model/local_semester.dart';
import 'package:celechron/manual/model/time_slot.dart';
import 'package:celechron/manual/service/pdf_timetable_import_service.dart';
import 'package:celechron/manual/service/pdf_timetable_parser.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Store implements AcademicProfileStore {
  _Store(this.value);
  String? value;
  int writes = 0;

  @override
  Future<String?> readSnapshot() async => value;

  @override
  Future<void> writeSnapshot(String value) async {
    writes++;
    this.value = value;
  }
}

AcademicProfile _profile({List<TimeSlot>? slots}) => AcademicProfile(
      schemaVersion: 1,
      revision: 4,
      planningRevision: 2,
      semesters: [
        LocalSemester(
          id: '10000000-0000-4000-8000-000000000001',
          name: '秋季学期',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2027, 1, 31),
          weekOneStart: DateTime(2026, 8, 31),
        ),
      ],
      timeSlots: slots ?? TimeSlot.defaultTemplate(),
    );

TimetableImportDraft _draft() => TimetableImportDraft(courses: [
      TimetableCourseDraft(
        id: 'pdf-1',
        name: '课程甲',
        courseNumber: 'C12345',
        credits: 3,
        sessions: [
          TimetableSessionDraft(
            id: 'session-1',
            weekday: 3,
            weekNumbers: [1, 3, 5],
            startSlot: 2,
            endSlot: 3,
            teacher: '分周教师',
            location: '教三405',
          ),
        ],
      ),
      TimetableCourseDraft(id: 'pdf-skip', name: '已跳过', include: false),
    ]);

void main() {
  test('adds reviewed courses and rules with one snapshot write', () async {
    final initial = _profile();
    final store = _Store(jsonEncode(initial.toJson()));
    final repository = AcademicRepository(store);

    final saved = await PdfTimetableImportService().importReviewedDraft(
      repository: repository,
      semesterId: initial.semesters.single.id,
      draft: _draft(),
    );

    expect(store.writes, 1);
    expect(saved.revision, 5);
    expect(saved.courses, hasLength(1));
    expect(saved.courses.single.name, '课程甲');
    expect(saved.sessionRules, hasLength(1));
    expect(saved.sessionRules.single.weekday, 3);
    expect(saved.sessionRules.single.teacher, '分周教师');
    expect(saved.sessionRules.single.location, '教三405');
    expect(saved.sessionRules.single.weekNumbers, [1, 3, 5]);
  });

  test('incomplete draft fails before writing any data', () async {
    final initial = _profile();
    final store = _Store(jsonEncode(initial.toJson()));
    final draft = _draft();
    draft.courses.first.sessions.single.weekNumbers = [];

    await expectLater(
      PdfTimetableImportService().importReviewedDraft(
        repository: AcademicRepository(store),
        semesterId: initial.semesters.single.id,
        draft: draft,
      ),
      throwsA(isA<LocalDataValidationError>()),
    );
    expect(store.writes, 0);
    expect(store.value, jsonEncode(initial.toJson()));
  });

  test('unconfigured section times fail without partial course writes',
      () async {
    final initial = _profile(slots: [
      TimeSlot(id: 'slot-1', ordinal: 1, startMinute: 480, endMinute: 525),
    ]);
    final store = _Store(jsonEncode(initial.toJson()));
    final draft = _draft(); // section 2 is not present in the custom template

    await expectLater(
      PdfTimetableImportService().importReviewedDraft(
        repository: AcademicRepository(store),
        semesterId: initial.semesters.single.id,
        draft: draft,
      ),
      throwsA(isA<LocalDataValidationError>()),
    );
    expect(store.writes, 0);
  });

  test('weeks beyond the selected semester fail without writing', () async {
    final initial = _profile();
    final store = _Store(jsonEncode(initial.toJson()));
    final draft = _draft();
    draft.courses.first.sessions.single.weekNumbers = [99];

    await expectLater(
      PdfTimetableImportService().importReviewedDraft(
        repository: AcademicRepository(store),
        semesterId: initial.semesters.single.id,
        draft: draft,
      ),
      throwsA(isA<LocalDataValidationError>()),
    );
    expect(store.writes, 0);
  });
}
