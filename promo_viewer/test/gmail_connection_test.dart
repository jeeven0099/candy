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

  Session session(String userId) => Session.fromJson({
    'access_token': 'test-session',
    'refresh_token': 'test-refresh',
    'provider_token': 'prior-google-token',
    'token_type': 'bearer',
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'app_metadata': {},
      'user_metadata': {},
      'created_at': '2026-10-01T12:00:00Z',
      'last_sign_in_at': '2026-10-06T12:00:00Z',
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
}
