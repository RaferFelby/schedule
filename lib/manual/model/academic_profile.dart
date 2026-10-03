import '../data/local_data_error.dart';
import 'grade_record.dart';
import 'local_course.dart';
import 'local_exam.dart';
import 'local_semester.dart';
import 'practice_record.dart';
import 'session_rule.dart';
import 'time_slot.dart';

/// Versioned local academic data with ID-only relationships.
final class AcademicProfile {
  AcademicProfile({
    required this.schemaVersion,
    required this.revision,
    this.planningRevision = 0,
    this.currentSemesterId,
    List<LocalSemester> semesters = const [],
    List<TimeSlot> timeSlots = const [],
    List<LocalCourse> courses = const [],
    List<SessionRule> sessionRules = const [],
    List<LocalExam> exams = const [],
    List<GradeRecord> grades = const [],
    List<PracticeRecord> practiceRecords = const [],
  })  : semesters = List.unmodifiable(semesters),
        timeSlots = List.unmodifiable(timeSlots),
        courses = List.unmodifiable(courses),
        sessionRules = List.unmodifiable(sessionRules),
        exams = List.unmodifiable(exams),
        grades = List.unmodifiable(grades),
        practiceRecords = List.unmodifiable(practiceRecords) {
    _validate();
  }

  static const supportedSchemaVersion = 1;

  final int schemaVersion;
  final int revision;
  final int planningRevision;
  final String? currentSemesterId;
  final List<LocalSemester> semesters;
  final List<TimeSlot> timeSlots;
  final List<LocalCourse> courses;
  final List<SessionRule> sessionRules;
  final List<LocalExam> exams;
  final List<GradeRecord> grades;
  final List<PracticeRecord> practiceRecords;

  factory AcademicProfile.fromJson(Map<String, dynamic> json) {
    final version = json['schemaVersion'];
    final revision = json['revision'];
    final planningRevision = json['planningRevision'] ?? 0;
    final currentSemesterId = json['currentSemesterId'];
    if (version is! int ||
        revision is! int ||
        planningRevision is! int ||
        (currentSemesterId != null && currentSemesterId is! String)) {
      throw const LocalDataValidationError('学业快照版本或头部数据格式无效');
    }
    if (version != supportedSchemaVersion) {
      throw LocalDataVersionIncompatibleError(
        storedVersion: version,
        supportedVersion: supportedSchemaVersion,
      );
    }

    return AcademicProfile(
      schemaVersion: version,
      revision: revision,
      planningRevision: planningRevision,
      currentSemesterId: currentSemesterId as String?,
      semesters: _decodeList(json['semesters'], LocalSemester.fromJson),
      timeSlots: _decodeList(json['timeSlots'], TimeSlot.fromJson),
      courses: _decodeList(json['courses'], LocalCourse.fromJson),
      sessionRules: _decodeList(json['sessionRules'], SessionRule.fromJson),
      exams: _decodeList(json['exams'], LocalExam.fromJson),
      grades: _decodeList(json['grades'], GradeRecord.fromJson),
      practiceRecords:
          _decodeList(json['practiceRecords'], PracticeRecord.fromJson),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'revision': revision,
        'planningRevision': planningRevision,
        'currentSemesterId': currentSemesterId,
        'semesters': semesters.map((value) => value.toJson()).toList(),
        'timeSlots': timeSlots.map((value) => value.toJson()).toList(),
        'courses': courses.map((value) => value.toJson()).toList(),
        'sessionRules': sessionRules.map((value) => value.toJson()).toList(),
        'exams': exams.map((value) => value.toJson()).toList(),
        'grades': grades.map((value) => value.toJson()).toList(),
        'practiceRecords':
            practiceRecords.map((value) => value.toJson()).toList(),
      };

  void _validate() {
    if (schemaVersion != supportedSchemaVersion) {
      throw LocalDataVersionIncompatibleError(
        storedVersion: schemaVersion,
        supportedVersion: supportedSchemaVersion,
      );
    }
    if (revision < 0) {
      throw const LocalDataValidationError('学业快照 revision 不能为负数');
    }
    if (planningRevision < 0) {
      throw const LocalDataValidationError('规划依赖 revision 不能为负数');
    }

    final allIds = <String>{};
    void addIds(Iterable<String> ids) {
      for (final id in ids) {
        if (id.trim().isEmpty || !allIds.add(id)) {
          throw LocalDataValidationError('学业快照中存在空 ID 或重复 ID：$id');
        }
      }
    }

    addIds(semesters.map((value) => value.id));
    addIds(timeSlots.map((value) => value.id));
    addIds(courses.map((value) => value.id));
    addIds(sessionRules.map((value) => value.id));
    addIds(exams.map((value) => value.id));
    addIds(grades.map((value) => value.id));
    addIds(practiceRecords.map((value) => value.id));
    TimeSlot.validateTemplate(timeSlots);

    final courseIds = courses.map((value) => value.id).toSet();
    final semesterIds = semesters.map((value) => value.id).toSet();
    if (courses.any((value) => !semesterIds.contains(value.semesterId))) {
      throw const LocalDataValidationError('课程引用了不存在的学期');
    }
    if (sessionRules.any((value) => !courseIds.contains(value.courseId))) {
      throw const LocalDataValidationError('上课规则引用了不存在的课程');
    }
    if (exams.any((value) => !courseIds.contains(value.courseId))) {
      throw const LocalDataValidationError('考试引用了不存在的课程');
    }
    if (grades.any((value) => !courseIds.contains(value.courseId))) {
      throw const LocalDataValidationError('成绩引用了不存在的课程');
    }
  }

  static List<T> _decodeList<T>(
    Object? value,
    T Function(Map<String, dynamic>) decode,
  ) {
    if (value is! List) {
      throw const LocalDataValidationError('学业快照列表字段格式无效');
    }
    return value.map((item) {
      if (item is! Map) {
        throw const LocalDataValidationError('学业快照实体格式无效');
      }
      return decode(Map<String, dynamic>.from(item));
    }).toList();
  }
}
