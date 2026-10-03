import 'dart:async';

import 'package:get/get.dart';

import '../data/academic_repository.dart';
import '../model/academic_profile.dart';
import '../model/local_semester.dart';

/// Publishes academic data only after its repository operation succeeds.
final class AcademicController extends GetxController {
  AcademicController({
    required AcademicRepository repository,
    required AcademicProfile initialProfile,
  })  : _repository = repository,
        profile = initialProfile.obs;

  final AcademicRepository _repository;
  final Rx<AcademicProfile> profile;

  LocalSemester? resolveCurrentSemester({DateTime? onDate}) {
    final current = profile.value;
    for (final semester in current.semesters) {
      if (semester.id == current.currentSemesterId) return semester;
    }

    final date = onDate ?? DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    final matches = current.semesters.where(
      (semester) =>
          !day.isBefore(semester.startDate) && !day.isAfter(semester.endDate),
    );
    return matches.length == 1 ? matches.single : null;
  }

  Future<AcademicProfile> save(AcademicProfile candidate) async {
    final saved = await _repository.save(candidate);
    profile.value = saved;
    return saved;
  }

  Future<AcademicProfile> applyUpdate(
    FutureOr<AcademicProfile> Function(AcademicProfile current) transform,
  ) async {
    final saved = await _repository.update(transform);
    profile.value = saved;
    return saved;
  }
}
