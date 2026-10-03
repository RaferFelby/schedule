import 'dart:convert';

import 'package:celechron/model/task.dart';

import '../model/academic_profile.dart';

/// Stable signatures for fields that can change a generated schedule.
final class ManualPlanningRevision {
  const ManualPlanningRevision._();

  static bool academicInputsChanged(
    AcademicProfile before,
    AcademicProfile after,
  ) =>
      academicSignature(before) != academicSignature(after);

  static String academicSignature(AcademicProfile profile) => jsonEncode({
        'currentSemesterId': profile.currentSemesterId,
        'semesters': _sorted(profile.semesters.map((value) => value.toJson())),
        'timeSlots': _sorted(profile.timeSlots.map((value) => value.toJson())),
        'courses': _sorted(profile.courses.map((value) => {
              'id': value.id,
              'semesterId': value.semesterId,
              'name': value.name,
            })),
        'sessionRules':
            _sorted(profile.sessionRules.map((value) => value.toJson())),
        'exams': _sorted(profile.exams.map((value) => {
              'id': value.id,
              'courseId': value.courseId,
              'start': value.start?.toIso8601String(),
              'end': value.end?.toIso8601String(),
            })),
      });

  static bool tasksChanged(Iterable<Task> before, Iterable<Task> after) =>
      taskSignature(before) != taskSignature(after);

  static String taskSignature(Iterable<Task> tasks) => jsonEncode(
        tasks
            .map((task) => {
                  'uid': task.uid,
                  'status': task.status.index,
                  'timeSpent': task.timeSpent.inMicroseconds,
                  'timeNeeded': task.timeNeeded.inMicroseconds,
                  'endTime': task.endTime.toIso8601String(),
                  'startTime': task.startTime.toIso8601String(),
                  'repeatType': task.repeatType.index,
                  'repeatPeriod': task.repeatPeriod,
                  'repeatEndsTime': task.repeatEndsTime.toIso8601String(),
                  'type': task.type.index,
                  'isBreakable': task.isBreakable,
                  'blockArrangements': task.blockArrangements,
                  'isCoursework': task.isCoursework,
                  'isTimeEstimated': task.isTimeEstimated,
                })
            .toList()
          ..sort((left, right) =>
              (left['uid']! as String).compareTo(right['uid']! as String)),
      );

  static List<Map<String, dynamic>> _sorted(
    Iterable<Map<String, dynamic>> values,
  ) =>
      values.toList()
        ..sort((left, right) =>
            (left['id']! as String).compareTo(right['id']! as String));
}

/// Revisions captured when a plan is generated, compared with current inputs.
final class ManualPlanRevisionStamp {
  const ManualPlanRevisionStamp({
    required this.academicRevision,
    required this.taskRevision,
  });

  final int academicRevision;
  final int taskRevision;

  bool needsReplan({
    required AcademicProfile currentProfile,
    required int currentTaskRevision,
  }) =>
      academicRevision != currentProfile.planningRevision ||
      taskRevision != currentTaskRevision;
}
