import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/utils.dart';

enum LegacyCredentialScope { appGroup, ungrouped }

abstract interface class LegacyCredentialKeyStore {
  Future<Set<String>> readKeys(LegacyCredentialScope scope);
  Future<void> deleteKey(LegacyCredentialScope scope, String key);
}

final class FlutterSecureStorageLegacyCredentialKeyStore
    implements LegacyCredentialKeyStore {
  const FlutterSecureStorageLegacyCredentialKeyStore({
    this.storage = const FlutterSecureStorage(),
  });

  final FlutterSecureStorage storage;

  static const _ungroupedOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
    accountName: 'Celechron',
  );

  IOSOptions _optionsFor(LegacyCredentialScope scope) =>
      scope == LegacyCredentialScope.appGroup
          ? secureStorageIOSOptions
          : _ungroupedOptions;

  @override
  Future<Set<String>> readKeys(LegacyCredentialScope scope) async =>
      (await storage.readAll(iOptions: _optionsFor(scope))).keys.toSet();

  @override
  Future<void> deleteKey(LegacyCredentialScope scope, String key) =>
      storage.delete(key: key, iOptions: _optionsFor(scope));
}

/// Removes only known legacy Celechron credentials, leaving other secure
/// storage entries untouched. The marker is written only after all deletes.
final class LegacyCredentialCleanup {
  const LegacyCredentialCleanup({
    this.keyStore = const FlutterSecureStorageLegacyCredentialKeyStore(),
  });

  static const markerFileName = 'celechron-legacy-credentials-cleaned-v1';
  static const exactKeys = {
    'username',
    'password',
    'synjonesAuth',
    'eCardAccount',
  };
  static const ssoKeyPrefix = 'zju_sso_cookie_';

  final LegacyCredentialKeyStore keyStore;

  Future<bool> run({required String applicationSupportPath}) async {
    final marker = File(
      '$applicationSupportPath${Platform.pathSeparator}$markerFileName',
    );
    if (await marker.exists()) return false;

    for (final scope in LegacyCredentialScope.values) {
      final keys = await keyStore.readKeys(scope);
      for (final key in keys) {
        if (exactKeys.contains(key) || key.startsWith(ssoKeyPrefix)) {
          await keyStore.deleteKey(scope, key);
        }
      }
    }

    await marker.parent.create(recursive: true);
    final temporary = File('${marker.path}.tmp.$pid');
    await temporary.writeAsString('1', flush: true);
    await temporary.rename(marker.path);
    return true;
  }
}
