import 'package:flutter/services.dart';
import 'pdf_timetable_document.dart';

export 'pdf_timetable_document.dart';

/// Reads PDF text locally through PDFKit and Vision on iOS.
final class PdfTimetableReader {
  static const _channel = MethodChannel('top.celechron/pdf_timetable');

  Future<PdfTimetableDocument?> pickAndRead() async {
    try {
      final raw =
          await _channel.invokeMapMethod<String, Object?>('pickAndRead');
      if (raw == null) return null;
      final pages = raw['pages'];
      if (pages is! List || pages.isEmpty) {
        throw const FormatException('PDF 中没有可读取的页面');
      }
      return PdfTimetableDocument(
        pages: pages.map(_page).toList(growable: false),
      );
    } on PlatformException catch (error) {
      final message = switch (error.code) {
        'encrypted_pdf' => error.message ?? 'PDF 已加密或需要密码',
        'invalid_pdf' || 'empty_pdf' => error.message ?? '无法读取这个 PDF 文件',
        'pdf_read_failed' => error.message ?? 'PDF 文字提取失败',
        _ => '无法读取 PDF：${error.message ?? error.code}',
      };
      throw FormatException(message);
    }
  }

  static PdfTimetablePage _page(Object? raw) {
    if (raw is! Map) throw const FormatException('PDF 页面数据格式无效');
    final page = Map<String, Object?>.from(raw);
    final spans = page['spans'];
    if (page['index'] is! int ||
        page['rotation'] is! int ||
        page['source'] is! String ||
        spans is! List) {
      throw const FormatException('PDF 页面字段无效');
    }
    return PdfTimetablePage(
      index: page['index']! as int,
      rotation: page['rotation']! as int,
      source: page['source']! as String,
      spans: spans.map(_span).toList(growable: false),
    );
  }

  static PdfTextSpan _span(Object? raw) {
    if (raw is! Map) throw const FormatException('PDF 文字片段格式无效');
    final span = Map<String, Object?>.from(raw);
    if (span['text'] is! String ||
        span['x'] is! num ||
        span['y'] is! num ||
        span['width'] is! num ||
        span['height'] is! num) {
      throw const FormatException('PDF 文字片段字段无效');
    }
    return PdfTextSpan(
      text: span['text']! as String,
      x: (span['x']! as num).toDouble(),
      y: (span['y']! as num).toDouble(),
      width: (span['width']! as num).toDouble(),
      height: (span['height']! as num).toDouble(),
    );
  }
}
