import 'package:celechron/manual/data/local_data_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalDataError', () {
    test('validation failures have a distinct type and message', () {
      const error = LocalDataValidationError('课程名称不能为空');

      expect(error, isA<Exception>());
      expect(error, isA<LocalDataError>());
      expect(error.message, '课程名称不能为空');
      expect(error.toString(), contains('LocalDataValidationError'));
    });

    test('storage failures retain their cause', () {
      final cause = StateError('disk unavailable');
      final error = LocalDataStorageError('保存失败', cause: cause);

      expect(error.cause, same(cause));
      expect(error.toString(), contains('LocalDataStorageError'));
    });

    test('version failures report stored and supported versions', () {
      const error = LocalDataVersionIncompatibleError(
        storedVersion: 4,
        supportedVersion: 2,
      );

      expect(error.storedVersion, 4);
      expect(error.supportedVersion, 2);
      expect(error.toString(), contains('version 4'));
      expect(error.toString(), contains('version 2'));
    });
  });
}
