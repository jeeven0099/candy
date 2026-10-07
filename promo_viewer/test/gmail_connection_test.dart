import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:promo_viewer/services/gmail_connection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GmailConnectionService.cancelPendingConnect();
  });

  Future<void> restoreAttempt({int? startedAt}) async {
    SharedPreferences.setMockInitialValues({
      'gmail_connect_auth_id': 'owner',
      'gmail_connect_started_at':
          startedAt ?? DateTime.now().millisecondsSinceEpoch,
      'gmail_connect_previous_sign_in': '2026-10-06T12:00:00Z',
    });
    await GmailConnectionService.restorePendingConnect();
  }

  Session session(
    String userId, {
    String signInAt = '2026-10-06T12:00:00Z',
    String? providerToken = 'prior-google-token',
  }) => Session.fromJson({
    'access_token': 'test-session',
    'refresh_token': 'test-refresh',
    'provider_token': providerToken,
    'token_type': 'bearer',
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-10-01T12:00:00Z',
      'last_sign_in_at': signInAt,
    },
  })!;

  test(
    'returning before OAuth completes does not vault the previous token',
    () async {
      await restoreAttempt();
      expect(
        await GmailConnectionService.vaultSessionIfPending(session('owner')),
        isFalse,
      );
      expect(GmailConnectionService.hasPendingConnect, isTrue);
    },
  );

  test(
    'a different Candy account cannot receive the pending Gmail connection',
    () async {
      await restoreAttempt();
      await expectLater(
        GmailConnectionService.vaultSessionIfPending(session('different-user')),
        throwsStateError,
      );
      expect(GmailConnectionService.hasPendingConnect, isFalse);
    },
  );

  test('abandoned connection attempts expire after 30 minutes', () async {
    await restoreAttempt(
      startedAt: DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch,
    );
    expect(GmailConnectionService.hasPendingConnect, isFalse);
  });

  test('explicit callback with an old session surfaces the failure', () async {
    await restoreAttempt();
    await expectLater(
      GmailConnectionService.vaultSessionIfPending(
        session('owner'),
        fromOAuthCallback: true,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('previous sign-in'),
        ),
      ),
    );
  });

  test(
    'explicit callback without a Gmail token surfaces the failure',
    () async {
      await restoreAttempt();
      await expectLater(
        GmailConnectionService.vaultSessionIfPending(
          session(
            'owner',
            signInAt: '2026-10-06T13:00:00Z',
            providerToken: null,
          ),
          fromOAuthCallback: true,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Gmail access token'),
          ),
        ),
      );
    },
  );

  test('backend failures retain safe details without exposing tokens', () {
    final message = GmailConnectionService.reportFailure(
      'save_connection',
      FunctionException(
        status: 400,
        details: {
          'error': 'gmail_access_not_granted',
          'provider_status': 403,
          'provider_reason': 'insufficientPermissions',
          'request_id': 'attempt-12345',
          'access_token': 'private-token',
        },
      ),
    );
    expect(message, contains('HTTP 400'));
    expect(message, contains('provider_status: 403'));
    expect(message, contains('insufficientPermissions'));
    expect(message, isNot(contains('private-token')));
    expect(GmailConnectionService.lastError.value, message);
    expect(
      GmailConnectionService.diagnosticLog.value,
      contains('attempt-12345'),
    );
  });
}
