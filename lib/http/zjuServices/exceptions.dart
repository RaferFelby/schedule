const refreshErrorDetailMarker = '\n<<<CELECHRON_ERROR_DETAIL>>>\n';

/// 面向用户展示短消息，同时保留已脱敏的诊断详情。
class ExceptionWithMessage implements Exception {
  final Object message;
  final String? details;
  final Object? originalError;

  ExceptionWithMessage(
    this.message, {
    this.details,
    this.originalError,
  });

  @override
  String toString() {
    final safeMessage = redactSensitive(message.toString());
    final safeDetails = details == null ? null : redactSensitive(details!);
    if (safeDetails == null || safeDetails.isEmpty) return safeMessage;
    return '$safeMessage$refreshErrorDetailMarker$safeDetails';
  }
}

String redactSensitive(String value) {
  var result = value;
  result = result.replaceAllMapped(
    RegExp(
      r'(authorization|proxy-authorization|cookie|set-cookie)'
      r'\s*[:=]\s*[^\r\n]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=<已隐藏>',
  );
  result = result.replaceAllMapped(
    RegExp(
      r'(password|passwd|token|ticket|synjones-auth|'
      r'iplanetdirectorypro|jsessionid)'
      r'\s*[:=]\s*[^;,\s]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=<已隐藏>',
  );
  result = result.replaceAllMapped(
    RegExp(r'https?://[^\s]+'),
    (match) {
      final uri = Uri.tryParse(match.group(0) ?? '');
      if (uri == null) return '<已隐藏 URL>';
      return Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path,
      ).toString();
    },
  );
  return result;
}
