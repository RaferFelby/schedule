import 'dart:convert';
import 'dart:io';

/// Stores explicit, per-record migration skips separately from the immutable
/// source backup so a blocked migration can be retried after app restarts.
final class MigrationResolutionStore {
  const MigrationResolutionStore(this.path);

  static const fileName = 'celechron-migration-resolutions-v1.json';
  static const schemaVersion = 1;

  final String path;

  Future<Set<String>> readSkippedIssueCodes() async {
    final document = await _readDocument();
    return _readSkipCodes(document);
  }

  Future<Map<String, Object?>> readCorrections() async {
    final document = await _readDocument();
    final raw = document['corrections'] ?? const <String, Object?>{};
    if (raw is! Map ||
        raw.keys.any((key) => key is! String) ||
        raw.keys.any((key) => !(key as String).startsWith('legacy-unresolved:'))) {
      throw const FormatException('迁移修正列表格式无效');
    }
    return Map.unmodifiable(Map<String, Object?>.from(raw));
  }

  Future<Map<String, Object?>> _readDocument() async {
    final file = File(path);
    if (!await file.exists()) {
      return {
        'schemaVersion': schemaVersion,
        'skippedIssueCodes': <String>[],
        'corrections': <String, Object?>{},
      };
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException catch (error) {
      throw FormatException('迁移决策文件损坏：${error.message}');
    }
    if (decoded is! Map || decoded['schemaVersion'] != schemaVersion) {
      throw const FormatException('迁移决策文件版本无效');
    }
    final document = Map<String, Object?>.from(decoded);
    _readSkipCodes(document);
    final rawCorrections = document['corrections'] ?? const <String, Object?>{};
    if (rawCorrections is! Map ||
        rawCorrections.keys.any((key) => key is! String) ||
        rawCorrections.keys
            .any((key) => !(key as String).startsWith('legacy-unresolved:'))) {
      throw const FormatException('迁移修正列表格式无效');
    }
    return document;
  }

  Set<String> _readSkipCodes(Map<String, Object?> document) {
    final rawCodes = document['skippedIssueCodes'];
    if (rawCodes is! List || rawCodes.any((value) => value is! String)) {
      throw const FormatException('迁移跳过列表格式无效');
    }
    final codes = rawCodes.cast<String>();
    if (codes.any((code) => !code.startsWith('legacy-unresolved:'))) {
      throw const FormatException('迁移决策中包含不支持跳过的问题');
    }
    return Set.unmodifiable(codes);
  }

  Future<Set<String>> skipIssue(String issueCode) async {
    if (!issueCode.startsWith('legacy-unresolved:')) {
      throw ArgumentError.value(issueCode, 'issueCode', '该问题不能跳过');
    }
    final document = await _readDocument();
    final codes = {..._readSkipCodes(document), issueCode};
    document['skippedIssueCodes'] = codes.toList()..sort();
    await _writeDocument(document);
    return Set.unmodifiable(codes);
  }

  Future<void> saveCorrection(String issueCode, Object? correctedRecord) async {
    if (!issueCode.startsWith('legacy-unresolved:')) {
      throw ArgumentError.value(issueCode, 'issueCode', '该问题不能修正');
    }
    final document = await _readDocument();
    final corrections = Map<String, Object?>.from(
      document['corrections'] as Map? ?? const <String, Object?>{},
    );
    corrections[issueCode] = correctedRecord;
    document['corrections'] = corrections;
    await _writeDocument(document);
  }

  Future<void> _writeDocument(Map<String, Object?> document) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(document),
      flush: true,
    );
    await temporary.rename(file.path);
  }
}
