final _sensitiveUrlPattern = RegExp(
  r'\b(?:https?|hiddify|vless|vmess|trojan|ss|ssr|tuic|hy2)://[^\s"<>]+',
  caseSensitive: false,
);

final _authorizationPattern = RegExp(r'\b(?:Bearer|Api-Key)\s+[^\s,;]+', caseSensitive: false);

final _emailPattern = RegExp(r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,63}\b', caseSensitive: false);
final _ipv4Pattern = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');
final _ipv6Pattern = RegExp(r'\b[0-9a-f]{1,4}(?::[0-9a-f]{0,4}){2,7}\b', caseSensitive: false);
final _hostPattern = RegExp(r'\b(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\b', caseSensitive: false);
final _absolutePathPattern = RegExp('(?<![A-Za-z0-9])(?:/[A-Za-z0-9._~ -]+){2,}');

final _sensitiveValuePattern = RegExp(
  r'''["']?\b(authorization|token|password|passwd|secret|receipt|api[-_]?key|private[-_]?key)\b["']?\s*[:=]\s*(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^,;}\r\n]+?(?=\s+\w[\w-]*\s*[:=]|[,;}\r\n]|$))''',
  caseSensitive: false,
);

/// Removes credentials, private access URLs and payment material before a log
/// record reaches console, disk or a remote error-monitoring integration.
String sanitizeLogText(Object? value) {
  if (value == null) return '';
  final sanitized = value
      .toString()
      .replaceAll(_sensitiveUrlPattern, '<redacted-url>')
      .replaceAll(_authorizationPattern, '<redacted-authorization>')
      .replaceAllMapped(_sensitiveValuePattern, (match) => '${match.group(1)}=<redacted>')
      .replaceAll(_emailPattern, '<redacted-email>')
      .replaceAll(_ipv4Pattern, '<redacted-ip>')
      .replaceAll(_ipv6Pattern, '<redacted-ip>')
      .replaceAll(_hostPattern, '<redacted-host>')
      .replaceAll(_absolutePathPattern, '<redacted-path>');
  return sanitized.length > 4096 ? '${sanitized.substring(0, 4096)}<truncated>' : sanitized;
}
