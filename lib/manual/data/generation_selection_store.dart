import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

import 'local_data_error.dart';
import 'storage_generation.dart';

enum GenerationSelectionWritePhase {
  invalidatedPreviousSlot,
  recordFlushed,
  newSlotCommitted,
}

final class GenerationSelectionResult {
  const GenerationSelectionResult({
    required this.active,
    required this.sequence,
    required this.slot,
    required this.usedFallback,
  });

  final StorageGenerationManifest active;
  final int sequence;
  final String? slot;
  final bool usedFallback;
}

/// Persists two checksummed selection slots; generation data is never removed.
final class GenerationSelectionStore {
  const GenerationSelectionStore({
    required this.rootDirectory,
    this.hive,
    this.afterWritePhase,
  });

  static const boxName = 'manual-generation-selection-v1';
  static const schemaVersion = 1;

  final String rootDirectory;
  final HiveInterface? hive;

  /// Fault injection point used by interruption tests.
  final Future<void> Function(GenerationSelectionWritePhase phase)?
      afterWritePhase;

  Future<GenerationSelectionResult> selectActive({
    required StorageGenerationManifest fallback,
  }) async {
    if (fallback.role != StorageGenerationRole.active ||
        fallback.rootDirectory != _normalizedRoot) {
      throw const LocalDataValidationError('活动代次回退角色或存储根目录无效');
    }
    final box = await _open();
    try {
      final records = _validSlots(box);
      if (records.isEmpty) {
        return GenerationSelectionResult(
          active: fallback,
          sequence: 0,
          slot: null,
          usedFallback: true,
        );
      }
      records.sort((a, b) => b.sequence.compareTo(a.sequence));
      if (records.length > 1 &&
          records[0].sequence == records[1].sequence &&
          jsonEncode(records[0].active.toJson()) !=
              jsonEncode(records[1].active.toJson())) {
        return GenerationSelectionResult(
          active: fallback,
          sequence: 0,
          slot: null,
          usedFallback: true,
        );
      }
      final selected = records.first;
      return GenerationSelectionResult(
        active: selected.active,
        sequence: selected.sequence,
        slot: selected.slot,
        usedFallback: false,
      );
    } finally {
      await box.close();
    }
  }

  Future<GenerationSelectionResult> commitCandidate({
    required StorageGenerationManifest currentActive,
    required StorageGenerationManifest candidate,
  }) async {
    _validateCandidate(currentActive, candidate);
    if (currentActive.rootDirectory != _normalizedRoot) {
      throw const LocalDataValidationError('选择指针必须写入当前代次根目录');
    }
    final box = await _open();
    try {
      final existing = _validSlots(box)
        ..sort(
          (a, b) => b.sequence.compareTo(a.sequence),
        );
      final latest = existing.isEmpty ? null : existing.first;
      if (latest != null &&
          (latest.active.generationId != currentActive.generationId ||
              latest.active.rootDirectory != currentActive.rootDirectory)) {
        throw const LocalDataValidationError('选择指针与传入的活动代次不一致');
      }
      final nextActive = StorageGenerationManifest.active(
        rootDirectory: candidate.rootDirectory,
        generationId: candidate.generationId,
      );
      final sequence = (latest?.sequence ?? 0) + 1;
      final targetSlot = latest?.slot == 'a' ? 'b' : 'a';
      final record = jsonEncode({
        'schemaVersion': schemaVersion,
        'sequence': sequence,
        'active': nextActive.toJson(),
      });
      final prefix = 'slot-$targetSlot';

      await box.put('$prefix-valid', 'false');
      await box.flush();
      await afterWritePhase?.call(
        GenerationSelectionWritePhase.invalidatedPreviousSlot,
      );

      await box.put('$prefix-record', record);
      await box.put('$prefix-checksum', _checksum(record));
      await box.flush();
      await afterWritePhase?.call(GenerationSelectionWritePhase.recordFlushed);

      await box.put('$prefix-valid', 'true');
      await box.flush();
      await afterWritePhase?.call(
        GenerationSelectionWritePhase.newSlotCommitted,
      );
      return GenerationSelectionResult(
        active: nextActive,
        sequence: sequence,
        slot: targetSlot,
        usedFallback: false,
      );
    } finally {
      await box.close();
    }
  }

  Future<Box<String>> _open() async => (hive ?? Hive).openBox<String>(
        boxName,
        path: rootDirectory,
      );

  String get _normalizedRoot => Directory(rootDirectory).absolute.path;

  List<_SelectionSlot> _validSlots(Box<String> box) {
    final result = <_SelectionSlot>[];
    for (final slot in const ['a', 'b']) {
      final prefix = 'slot-$slot';
      if (box.get('$prefix-valid') != 'true') continue;
      final record = box.get('$prefix-record');
      final checksum = box.get('$prefix-checksum');
      if (record == null || checksum != _checksum(record)) continue;
      try {
        final decoded = jsonDecode(record);
        if (decoded is! Map || decoded['schemaVersion'] != schemaVersion) {
          continue;
        }
        final sequence = decoded['sequence'];
        final manifestJson = decoded['active'];
        if (sequence is! int || sequence < 1 || manifestJson is! Map) {
          continue;
        }
        final active = StorageGenerationManifest.fromJson(
          Map<String, dynamic>.from(manifestJson),
        );
        if (active.role != StorageGenerationRole.active ||
            active.rootDirectory != _normalizedRoot) {
          continue;
        }
        result.add(_SelectionSlot(slot, sequence, active));
      } on Object {
        // Invalid slots are ignored so the last complete record can win.
      }
    }
    return result;
  }

  static String _checksum(String record) =>
      sha256.convert(utf8.encode(record)).toString();

  static void _validateCandidate(
    StorageGenerationManifest active,
    StorageGenerationManifest candidate,
  ) {
    if (active.role != StorageGenerationRole.active ||
        candidate.role != StorageGenerationRole.candidate ||
        candidate.parentGenerationId != active.generationId ||
        candidate.rootDirectory != active.rootDirectory ||
        candidate.legacyRoot) {
      throw const LocalDataValidationError('选择指针候选与活动代次不匹配');
    }
  }
}

final class _SelectionSlot {
  const _SelectionSlot(this.slot, this.sequence, this.active);

  final String slot;
  final int sequence;
  final StorageGenerationManifest active;
}
