import 'package:celechron/manual/data/local_data_error.dart';
import 'package:celechron/manual/model/local_course.dart';
import 'package:flutter_test/flutter_test.dart';

const _semesterId = '10000000-0000-4000-8000-000000000001';

void main() {
  group('LocalCourse', () {
    test('optional course number and unknown credits remain absent', () {
      final course = LocalCourse(
        id: '20000000-0000-4000-8000-000000000001',
        semesterId: _semesterId,
        name: '暑期班课程',
      );

      final restored = LocalCourse.fromJson(course.toJson());
      expect(restored.courseNumber, isNull);
      expect(restored.credits, isNull);
      expect(restored.teacher, isNull);
      expect(restored.isMajor, isFalse);
      expect(restored.semesterId, _semesterId);
    });

    test('same names can have distinct explicit IDs', () {
      final first = LocalCourse(
        id: '20000000-0000-4000-8000-000000000001',
        semesterId: _semesterId,
        name: '重复课程名',
        credits: 2.5,
        teacher: '教师甲',
        isMajor: true,
      );
      final second = LocalCourse(
        id: '20000000-0000-4000-8000-000000000002',
        semesterId: _semesterId,
        name: '重复课程名',
      );

      expect(first.name, second.name);
      expect(first.id, isNot(second.id));
      expect(first.credits, 2.5);
      expect(first.isMajor, isTrue);
    });

    test('rejects negative credits and malformed IDs', () {
      expect(
        () => LocalCourse(
          id: 'not-a-uuid',
          semesterId: _semesterId,
          name: '课程',
        ),
        throwsA(isA<LocalDataValidationError>()),
      );
      expect(
        () => LocalCourse(
          id: '20000000-0000-4000-8000-000000000001',
          semesterId: _semesterId,
          name: '课程',
          credits: -0.5,
        ),
        throwsA(isA<LocalDataValidationError>()),
      );
    });
  });
}
