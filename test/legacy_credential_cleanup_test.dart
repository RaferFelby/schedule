import 'dart:io';

import 'package:celechron/services/legacy_credential_cleanup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory support;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('legacy-credentials-');
  });

  tearDown(() async {
    if (await support.exists()) await support.delete(recursive: true);
  });

  test('deletes only known legacy keys from both app-owned scopes', () async {
    final store = _MemoryKeyStore({
      LegacyCredentialScope.appGroup: {
        'username',
        'password',
        'zju_sso_cookie_old-user',
        'synjonesAuth',
        'eCardAccount',
        'gpa',
      },
      LegacyCredentialScope.ungrouped: {
        'username',
        'zju_sso_cookie_another-user',
        'unrelated-app-setting',
      },
    });
    final cleanup = LegacyCredentialCleanup(keyStore: store);

    expect(await cleanup.run(applicationSupportPath: support.path), isTrue);
    expect(store.keys[LegacyCredentialScope.appGroup], {'gpa'});
    expect(store.keys[LegacyCredentialScope.ungrouped], {
      'unrelated-app-setting',
    });
    expect(
      await cleanup.run(applicationSupportPath: support.path),
      isFalse,
    );
    expect(store.readCount, 2);
  });

  test('does not write completion marker when deletion fails', () async {
    final store = _MemoryKeyStore(
      {
        LegacyCredentialScope.appGroup: {'password'}
      },
      failNextDelete: true,
    );
    final cleanup = LegacyCredentialCleanup(keyStore: store);

    await expectLater(
      cleanup.run(applicationSupportPath: support.path),
      throwsStateError,
    );
    expect(
      await File('${support.path}/${LegacyCredentialCleanup.markerFileName}')
          .exists(),
      isFalse,
    );
    expect(await cleanup.run(applicationSupportPath: support.path), isTrue);
    expect(store.keys[LegacyCredentialScope.appGroup], isEmpty);
  });
}

final class _MemoryKeyStore implements LegacyCredentialKeyStore {
  _MemoryKeyStore(this.keys, {this.failNextDelete = false});

  final Map<LegacyCredentialScope, Set<String>> keys;
  bool failNextDelete;
  var readCount = 0;

  @override
  Future<void> deleteKey(LegacyCredentialScope scope, String key) async {
    if (failNextDelete) {
      failNextDelete = false;
      throw StateError('simulated keychain delete failure');
    }
    keys[scope]?.remove(key);
  }

  @override
  Future<Set<String>> readKeys(LegacyCredentialScope scope) async {
    readCount++;
    return {...keys[scope] ?? const <String>{}};
  }
}
