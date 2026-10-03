import 'dart:convert';

import 'package:celechron/utils/json_utils.dart';

import 'exceptions.dart';

export 'package:celechron/utils/json_utils.dart';

String responseSummary(String body) {
  // 诊断摘要禁止复制业务正文，只保留定位格式问题所需的结构信息。
  final trimmed = body.trim();
  if (trimmed.isEmpty) return '<空响应>';
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      const commonKeys = [
        'code',
        'status',
        'success',
        'message',
        'msg',
        'data',
        'result',
        'items',
        'rows',
      ];
      final presentKeys = commonKeys.where(decoded.containsKey).join(',');
      return '<JSON对象；字段数=${decoded.length}；'
          '常见字段=${presentKeys.isEmpty ? '无' : presentKeys}>';
    }
    if (decoded is List) return '<JSON数组；条目数=${decoded.length}>';
    if (decoded is String) return '<JSON字符串；长度=${decoded.length}>';
    return '<JSON标量；类型=${decoded.runtimeType}>';
  } on FormatException {
    if (_looksLikeHtml(trimmed)) return '<HTML响应；长度=${trimmed.length}>';
    return '<文本响应；长度=${trimmed.length}>';
  }
}

bool _looksLikeHtml(String body) {
  final normalized = body.trimLeft().toLowerCase();
  return normalized.startsWith('<!doctype html') ||
      normalized.startsWith('<html') ||
      normalized.contains('<body') ||
      normalized.contains('<form');
}

Object? decodeJsonValue(String body, {required String context}) {
  if (body.trim().isEmpty) {
    throw ExceptionWithMessage('$context；无法解析 JSON：响应为空');
  }
  if (_looksLikeHtml(body)) {
    throw ExceptionWithMessage(
      '$context；无法解析 JSON：返回了 HTML',
      details: '响应摘要：${responseSummary(body)}',
    );
  }
  try {
    return jsonDecode(body);
  } on FormatException catch (error) {
    throw ExceptionWithMessage(
      '$context；JSON 格式错误',
      details: [
        '原始异常类型：${error.runtimeType}',
        '原始异常消息：${error.message}',
        '响应摘要：${responseSummary(body)}',
      ].join('\n'),
      originalError: error,
    );
  }
}

Map<String, dynamic> decodeJsonMap(String body, {required String context}) {
  final decoded = decodeJsonValue(body, context: context);
  final map = asStringMap(decoded);
  if (map == null) {
    throw ExceptionWithMessage(
      '$context；JSON 顶层应为对象',
      details: [
        '实际类型：${decoded.runtimeType}',
        '响应摘要：${responseSummary(body)}',
      ].join('\n'),
    );
  }
  return map;
}

List<dynamic> decodeJsonList(String body, {required String context}) {
  final decoded = decodeJsonValue(body, context: context);
  final list = asDynamicList(decoded);
  if (list == null) {
    throw ExceptionWithMessage(
      '$context；JSON 顶层应为数组',
      details: [
        '实际类型：${decoded.runtimeType}',
        '响应摘要：${responseSummary(body)}',
      ].join('\n'),
    );
  }
  return list;
}
