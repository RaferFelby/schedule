import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'diagnostic_report.dart';
import 'diagnostic_sanitizer.dart';

enum CelechronLogLevel { debug, info, warning, error }

/// 统一收集、脱敏并串行落盘诊断信息，避免并发写入互相覆盖。
class DiagnosticLogService {
  static const _maxMemoryLines = 2000;
  static const _maxExportFiles = 10;
  static const _bufferFileName = 'celechron-diagnostic-buffer.log';

  static final DiagnosticLogService instance = DiagnosticLogService._();

  final List<String> _memoryLines = [];
  Future<void> _fileQueue = Future<void>.value();

  DiagnosticLogService._();

  void record({
    CelechronLogLevel level = CelechronLogLevel.info,
    required String module,
    required String operation,
    String? message,
    Object? error,
    StackTrace? stackTrace,
  }) {
    // 所有自由文本都在进入内存、文件前完成脱敏。
    final fields = <String>[
      DateTime.now().toUtc().toIso8601String(),
      'level=${level.name}',
      'module=${_sanitize(module)}',
      'operation=${_sanitize(operation)}',
      'exceptionType=${error?.runtimeType ?? '-'}',
      'exception=${error == null ? '-' : _sanitize(error.toString())}',
      if (message != null) 'message=${_sanitize(message)}',
      'stack=${stackTrace == null ? '-' : _sanitizeStack(stackTrace)}',
    ];
    final line = fields.join(' | ');
    _memoryLines.add(line);
    if (_memoryLines.length > _maxMemoryLines) {
      _memoryLines.removeRange(0, _memoryLines.length - _maxMemoryLines);
    }
    if (kDebugMode) debugPrint(line);
    _enqueuePersist(line);
  }

  String currentText() => _memoryLines.join('\n');

  Future<String> recentText() async {
    await _fileQueue;
    return _readRecentLines();
  }

  Future<void> copyReadyText(void Function(String text) copy) async {
    await _fileQueue;
    copy(await _readRecentLines());
  }

  Future<String> exportAndShare({
    required String version,
    required String buildNumber,
  }) async {
    await _fileQueue;
    final directory = await _exportDirectory();
    final now = DateTime.now();
    final fileName = 'celechron-test-log-${_fileTimestamp(now)}.txt';
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    final logs = await _readRecentLines();
    final bundle = const DiagnosticReportParser().parse(logs);
    final contents = formatDiagnosticExport(
      bundle: bundle,
      rawLog: logs,
      version: version,
      buildNumber: buildNumber,
      platform: Platform.operatingSystem,
      exportedAt: now,
    );
    await file.writeAsString(
      contents,
      encoding: utf8,
      flush: true,
    );
    await _pruneExports(directory);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        text: 'Celechron 测试日志：$fileName',
      ),
    );
    return fileName;
  }

  Future<void> clear() async {
    _memoryLines.clear();
    await _fileQueue;
    final file = await _bufferFile();
    if (await file.exists()) {
      await file.writeAsString('', encoding: utf8, flush: true);
    }
    final exportDirectory = await _exportDirectory();
    await for (final entity in exportDirectory.list()) {
      if (entity is File &&
          entity.path.contains('celechron-test-log-') &&
          entity.path.endsWith('.txt')) {
        await entity.delete();
      }
    }
  }

  void _enqueuePersist(String line) {
    // 写入链保证日志顺序；单次失败被吸收，不能反向影响业务刷新。
    _fileQueue = _fileQueue.then((_) async {
      final file = await _bufferFile();
      await file.writeAsString(
        '$line\n',
        mode: FileMode.append,
        encoding: utf8,
        flush: false,
      );
      if (await file.length() > 2 * 1024 * 1024) {
        final recent = await _readRecentLines(file: file);
        await file.writeAsString(
          recent.isEmpty ? '' : '$recent\n',
          encoding: utf8,
          flush: true,
        );
      }
    }).catchError((Object error, StackTrace stackTrace) {
      if (kDebugMode) {
        debugPrint('诊断日志持久化失败：$error\n$stackTrace');
      }
    });
  }

  Future<File> _bufferFile() async {
    final logDirectory = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'celechron_diagnostic_logs',
    );
    await logDirectory.create(recursive: true);
    return File(
        '${logDirectory.path}${Platform.pathSeparator}$_bufferFileName');
  }

  Future<Directory> _exportDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final exportDirectory =
        Directory('${directory.path}${Platform.pathSeparator}CelechronLogs');
    await exportDirectory.create(recursive: true);
    return exportDirectory;
  }

  Future<String> _readRecentLines({File? file}) async {
    final target = file ?? await _bufferFile();
    if (!await target.exists()) return currentText();
    final lines = await target.readAsLines(encoding: utf8);
    final start =
        lines.length > _maxMemoryLines ? lines.length - _maxMemoryLines : 0;
    return lines.sublist(start).join('\n');
  }

  Future<void> _pruneExports(Directory directory) async {
    final files = await directory
        .list()
        .where((entity) =>
            entity is File &&
            entity.path.contains('celechron-test-log-') &&
            entity.path.endsWith('.txt'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final file in files.skip(_maxExportFiles)) {
      await file.delete();
    }
  }

  @visibleForTesting
  static String sanitizeForDiagnostic(String value) =>
      sanitizeDiagnosticText(value);

  static String _sanitizeStack(StackTrace stackTrace) {
    return _sanitize(stackTrace.toString())
        .replaceAll('\r\n', r'\n')
        .replaceAll('\n', r'\n');
  }

  static String _sanitize(String value) {
    return sanitizeDiagnosticText(value);
  }

  static String _fileTimestamp(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}-'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }
}
