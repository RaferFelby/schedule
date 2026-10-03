import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:celechron/manual/model/practice_record.dart';

final class LegacyPracticeSummary {
  const LegacyPracticeSummary({
    required this.pointsByCategory,
    required this.source,
    required this.scope,
    required this.calculationMethod,
    required this.derivedFromDetails,
    required this.stale,
    required this.updatedAt,
    required this.artsPassed,
    required this.laborPassed,
  });

  /// Category IDs 1/2/3 mean second/third/fourth classroom.
  final Map<int, double?> pointsByCategory;
  final String source;
  final String scope;
  final String calculationMethod;
  final bool derivedFromDetails;
  final bool stale;
  final DateTime? updatedAt;
  final bool? artsPassed;
  final bool? laborPassed;
}

final class LegacyPracticeRecordMetadata {
  const LegacyPracticeRecordMetadata({
    required this.recordId,
    required this.sourceItemId,
    required this.categoryId,
    required this.projectType,
    required this.qualityType,
    required this.role,
    required this.activityEnd,
    required this.updatedAt,
    required this.statusValue,
    required this.statusLabel,
  });

  final String recordId;
  final int sourceItemId;
  final int categoryId;
  final String projectType;
  final String qualityType;
  final String? role;
  final DateTime? activityEnd;
  final DateTime? updatedAt;
  final int? statusValue;
  final String statusLabel;
}

final class LegacyPracticeConversionResult {
  const LegacyPracticeConversionResult({
    required this.records,
    required this.recordMetadata,
    required this.historicalSummary,
    required this.unresolvedRecords,
    required this.unresolvedSummary,
    required this.reviewItems,
  });

  final List<PracticeRecord> records;
  final List<LegacyPracticeRecordMetadata> recordMetadata;
  final LegacyPracticeSummary? historicalSummary;
  final List<Map<String, Object?>> unresolvedRecords;
  final List<Map<String, Object?>> unresolvedSummary;
  final List<String> reviewItems;
}

/// Converts item details and historical totals into separate candidate values.
final class LegacyPracticeConverter {
  const LegacyPracticeConverter();

  LegacyPracticeConversionResult convert(Map<String, Object?> scholar) {
    final records = <PracticeRecord>[];
    final metadata = <LegacyPracticeRecordMetadata>[];
    final unresolvedRecords = <Map<String, Object?>>[];
    final unresolvedSummary = <Map<String, Object?>>[];
    final review = <String>[];
    final rawItems = scholar['practiceScoreItems'];
    final sourceIds = <int, String>{};
    if (rawItems is List) {
      for (var index = 0; index < rawItems.length; index++) {
        final rawItem = rawItems[index];
        if (rawItem is! Map) {
          unresolvedRecords.add({
            'sourceIndex': index,
            'reason': '实践明细格式无效',
          });
          continue;
        }
        final item = Map<String, Object?>.from(rawItem);
        final sourceId = item['id'];
        if (sourceId is! int) {
          unresolvedRecords.add({
            'sourceIndex': index,
            'projectName': item['projectName'],
            'reason': '实践明细缺少有效来源 ID',
          });
          continue;
        }
        final signature = jsonEncode(item);
        final priorSignature = sourceIds[sourceId];
        if (priorSignature != null) {
          if (priorSignature != signature) {
            unresolvedRecords.add({
              'sourceIndex': index,
              'sourceItemId': sourceId,
              'reason': '来源 ID 重复但内容不同，未合并',
            });
            review.add('实践来源 ID $sourceId 重复且内容不同，后续记录待核对');
          }
          continue;
        }
        sourceIds[sourceId] = signature;
        if (item['deleted'] == true) {
          review.add('实践来源 ID $sourceId 已删除，未恢复');
          continue;
        }

        final categoryId = item['categoryId'];
        final categoryName = item['categoryName'];
        final projectName = item['projectName'];
        final points = item['score'];
        final date = _date(item['activityStart']);
        String? reason;
        if (categoryId is! int || categoryId < 1 || categoryId > 3) {
          reason = '实践类别 ID 不在第二/三/四课堂范围';
        } else if (categoryName is! String || categoryName.trim().isEmpty) {
          reason = '实践类别名称缺失';
        } else if (projectName is! String || projectName.trim().isEmpty) {
          reason = '实践项目名称缺失';
        } else if (points is! num || !points.isFinite || points < 0) {
          reason = '实践记点不是非负有限值';
        } else if (date == null) {
          reason = '缺少明确活动开始日期';
        }
        if (reason != null ||
            categoryId is! int ||
            categoryName is! String ||
            projectName is! String ||
            points is! num ||
            date == null) {
          unresolvedRecords.add({
            'sourceIndex': index,
            'sourceItemId': sourceId,
            'projectName': projectName,
            'reason': reason ?? '实践明细字段无法转换',
          });
          review.add('实践来源 ID $sourceId 待核对：${reason ?? '字段无法转换'}');
          continue;
        }

        final status = _reviewStatus(item, review, sourceId);
        final recordId = _stableRecordId(sourceId, index, item);
        records.add(PracticeRecord(
          id: recordId,
          category: categoryName,
          projectName: projectName,
          date: date,
          points: points.toDouble(),
          status: status,
          note: _nonEmpty(item['remark']),
        ));
        final projectType = _nonEmpty(item['projectType']) ?? '未填写';
        final qualityType = _nonEmpty(item['qualityType']) ?? '未填写';
        final role = _nonEmpty(item['role']);
        final activityEnd = _date(item['activityEnd']);
        final updatedAt = _date(item['updatedAt']);
        final statusValue = item['statusValue'];
        final statusLabel = _nonEmpty(item['statusLabel']) ?? '状态未知';
        metadata.add(LegacyPracticeRecordMetadata(
          recordId: recordId,
          sourceItemId: sourceId,
          categoryId: categoryId,
          projectType: projectType,
          qualityType: qualityType,
          role: role,
          activityEnd: activityEnd,
          updatedAt: updatedAt,
          statusValue: statusValue is int ? statusValue : null,
          statusLabel: statusLabel,
        ));
        if (projectType != '未填写' ||
            qualityType != '未填写' ||
            role != null ||
            activityEnd != null ||
            updatedAt != null ||
            statusValue != null) {
          review.add('实践来源 ID $sourceId 的项目类别/角色/结束日期/更新时间保存在转换 sidecar 元数据');
        }
      }
    } else if (rawItems != null) {
      unresolvedRecords.add({'reason': 'practiceScoreItems 必须是列表'});
    }

    final summary = _readSummary(scholar, unresolvedSummary, review);
    if (summary?.derivedFromDetails == true && records.isNotEmpty) {
      final totals = <int, double>{1: 0, 2: 0, 3: 0};
      for (final record in records) {
        if (record.status == PracticeReviewStatus.approved) {
          final recordMetadata = metadata.firstWhere(
            (entry) => entry.recordId == record.id,
          );
          totals[recordMetadata.categoryId] =
              totals[recordMetadata.categoryId]! + record.points;
        }
      }
      for (final entry in totals.entries) {
        final historical = summary!.pointsByCategory[entry.key];
        if (historical != null && historical != entry.value) {
          review.add('实践类别 ${entry.key} 的已存明细汇总与转换明细合计不同；保留两份来源，不叠加');
        }
      }
      review.add('历史实践汇总由明细派生；目标项目明细将重算合计，不重复导入为额外记录');
    } else if (summary != null && records.isNotEmpty) {
      review.add('独立历史实践汇总与项目明细分别保留；目标合计不得将两者相加');
    } else if (summary != null && records.isEmpty) {
      review.add('仅有历史实践汇总，没有足够项目资料生成实践明细');
    }

    return LegacyPracticeConversionResult(
      records: List.unmodifiable(records),
      recordMetadata: List.unmodifiable(metadata),
      historicalSummary: summary,
      unresolvedRecords: List.unmodifiable(unresolvedRecords),
      unresolvedSummary: List.unmodifiable(unresolvedSummary),
      reviewItems: List.unmodifiable(review),
    );
  }

  static LegacyPracticeSummary? _readSummary(
    Map<String, Object?> scholar,
    List<Map<String, Object?>> unresolved,
    List<String> review,
  ) {
    final sourceValue = scholar['practiceSummarySource'];
    final legacyAvailable = scholar['isPracticeScoresGet'] == true;
    final source = sourceValue is String ? sourceValue : 'unavailable';
    if (source == 'unavailable' && !legacyAvailable) return null;

    double? total(String field) {
      final value = scholar[field];
      if (value is num && value.isFinite && value >= 0) return value.toDouble();
      unresolved.add({
        'field': field,
        'value': value,
        'reason': value == null ? '汇总字段缺失' : '汇总值必须是非负有限数值',
      });
      review.add('历史实践汇总 $field 无法无损转换');
      return null;
    }

    final sourceToMethod = switch (source) {
      'calculatedFromSqjl' => 'approvedPracticeItems',
      'networkMyInfo' || 'cachedMyInfo' => 'officialSummaryFields',
      'legacyPersisted' => 'legacyPersistedTotals',
      'zdbkLive' || 'zdbkCache' => 'legacyPersistedTotals',
      _ => 'unknownLegacyMethod',
    };
    if (sourceToMethod == 'unknownLegacyMethod') {
      review.add('历史实践汇总来源未知，保留原类别总数并标记人工核对');
    }
    final updatedAt = _date(scholar['practiceUpdatedAt']);
    final myPassed = scholar['practiceMyPassed'];
    final lyPassed = scholar['practiceLyPassed'];
    if (myPassed != null && myPassed is! bool) {
      review.add('历史美育状态格式无效，按未知保留');
    }
    if (lyPassed != null && lyPassed is! bool) {
      review.add('历史劳育状态格式无效，按未知保留');
    }
    return LegacyPracticeSummary(
      pointsByCategory: Map.unmodifiable({
        1: total('pt2'),
        2: total('pt3'),
        3: total('pt4'),
      }),
      source: source,
      scope: 'Scholar 全局历史汇总（非单学期、非单项目）',
      calculationMethod: sourceToMethod,
      derivedFromDetails: source == 'calculatedFromSqjl',
      stale: scholar['practiceSummaryStale'] == true ||
          scholar['practiceDetailsStale'] == true,
      updatedAt: updatedAt,
      artsPassed: myPassed is bool ? myPassed : null,
      laborPassed: lyPassed is bool ? lyPassed : null,
    );
  }

  static PracticeReviewStatus _reviewStatus(
    Map<String, Object?> item,
    List<String> review,
    int sourceId,
  ) {
    final approved = item['approved'];
    final label = _nonEmpty(item['statusLabel'])?.toLowerCase();
    if (approved == true) return PracticeReviewStatus.approved;
    if (approved is! bool) {
      review.add('实践来源 ID $sourceId 审核标记缺失，状态按待审核保存');
    }
    if (const {'未通过', '审核未通过', '审核不通过', '不通过', 'rejected'}.contains(label)) {
      return PracticeReviewStatus.rejected;
    }
    if (!const {'待审核', '审核中', 'pending', '处理中'}.contains(label)) {
      review.add('实践来源 ID $sourceId 审核标签未知，状态按待审核保存');
    }
    return PracticeReviewStatus.pending;
  }

  static String _stableRecordId(
      int sourceId, int index, Map<String, Object?> item) {
    final bytes = sha256
        .convert(
            utf8.encode('legacy-practice:$sourceId:$index:${jsonEncode(item)}'))
        .bytes
        .take(16)
        .toList();
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  static DateTime? _date(Object? value) {
    if (value is! String) return null;
    final parsed = DateTime.tryParse(value);
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String? _nonEmpty(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}
