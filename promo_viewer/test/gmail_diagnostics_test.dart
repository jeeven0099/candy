import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/utils/gmail_diagnostics.dart';

void main() {
  test('redacts OAuth secrets, authorization headers, and callback URLs', () {
    const secrets = ['session-secret', 'refresh-secret'];
    final value = redactGmailDiagnostic(
      'session-secret refresh-secret '
      'https://example.com/callback?code=secret-code '
      'com.jeeven.candy://login-callback/#access_token=secret-access '
      'Bearer bearer-secret ya29.google-secret 1//refresh-google '
      'eyJheader.payload.signature '
      'access_token=unknown-secret "client_secret": "unknown-client" '
      'code=standalone-secret',
      secrets: secrets,
    );
    for (final secret in [
      ...secrets,
      'secret-code',
      'secret-access',
      'bearer-secret',
      'google-secret',
      'refresh-google',
      'eyJheader',
      'unknown-secret',
      'unknown-client',
      'standalone-secret',
    ]) {
      expect(value, isNot(contains(secret)));
    }
  });

  test('failure formatter includes only useful scalar diagnostic fields', () {
    final value = formatGmailFailure(
      stage: 'save_connection',
      kind: 'FunctionException',
      message: 'Forbidden',
      httpStatus: 400,
      details: {
        'stage': 'gmail_profile',
        'provider_status': 403,
        'provider_reason': 'insufficientPermissions',
        'request_id': 'attempt-12345',
        'access_token': 'secret',
        'nested': {'refresh_token': 'secret'},
        'message': 'ya29.provider-secret',
      },
    );
    expect(value, contains('save_connection (HTTP 400)'));
    expect(value, contains('gmail_profile'));
    expect(value, contains('provider_status: 403'));
    expect(value, contains('insufficientPermissions'));
    expect(value, contains('attempt-12345'));
    expect(value, isNot(contains('secret')));
    expect(value, isNot(contains('access_token')));
  });

  test('diagnostic output is bounded', () {
    expect(redactGmailDiagnostic('x' * 5000).length, lessThanOrEqualTo(1503));
  });
}
