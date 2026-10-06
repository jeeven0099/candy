String redactGmailDiagnostic(
  String value, {
  Iterable<String?> secrets = const [],
}) {
  var result = value;
  for (final secret in secrets) {
    if (secret != null && secret.isNotEmpty) {
      result = result.replaceAll(secret, '[redacted]');
    }
  }
  result = result.replaceAll(
    RegExp(
      r'(?:https?://|com\.jeeven\.candy://)[^\s<>]+',
      caseSensitive: false,
    ),
    '[URL redacted]',
  );
  result = result.replaceAll(
    RegExp(r'Bearer\s+[^\s,;]+', caseSensitive: false),
    'Bearer [redacted]',
  );
  result = result.replaceAll(
    RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
    '[JWT redacted]',
  );
  result = result.replaceAll(
    RegExp(r'\b(?:ya29\.|1//)[A-Za-z0-9._/-]+'),
    '[Google token redacted]',
  );
  result = result.replaceAllMapped(
    RegExp(r'\bcode=([^\s&]+)', caseSensitive: false),
    (_) => 'code=[redacted]',
  );
  result = result.replaceAllMapped(
    RegExp(
      r'''["']?(access_token|refresh_token|provider_token|provider_refresh_token|id_token|client_secret|code_verifier|authorization)["']?\s*[:=]\s*(?:"[^"\r\n]*"|'[^'\r\n]*'|[^\s,;}]+)''',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=[redacted]',
  );
  return result.length > 1500 ? '${result.substring(0, 1500)}...' : result;
}

String formatGmailFailure({
  required String stage,
  required String kind,
  required String message,
  int? httpStatus,
  Map<String, dynamic>? details,
  Iterable<String?> secrets = const [],
}) {
  final lines = <String>[
    'Gmail connection failed at $stage${httpStatus == null ? '' : ' (HTTP $httpStatus)'}.',
    '$kind: $message',
  ];
  if (details != null) {
    for (final key in [
      'error',
      'error_description',
      'code',
      'message',
      'stage',
      'provider_status',
      'provider_reason',
      'request_id',
    ]) {
      final value = details[key];
      if (value is String || value is num) lines.add('$key: $value');
    }
  }
  return redactGmailDiagnostic(lines.join('\n'), secrets: secrets);
}
