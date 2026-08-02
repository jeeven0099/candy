import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'supabase_service.dart';

class PushTokenService {
  static Future<void> register() async {
    if (!SupabaseService.isLoggedIn) {
      Sentry.addBreadcrumb(Breadcrumb(message: '[PushToken] skipped: not logged in'));
      return;
    }
    if (Firebase.apps.isEmpty) {
      Sentry.addBreadcrumb(Breadcrumb(message: '[PushToken] skipped: Firebase not initialized'));
      return;
    }

    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    Sentry.addBreadcrumb(Breadcrumb(
      message: '[PushToken] permission: ${settings.authorizationStatus}',
    ));
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await messaging.getToken();
    Sentry.addBreadcrumb(Breadcrumb(
      message: '[PushToken] getToken result: ${token == null ? "NULL" : "ok (${token.substring(0, 20)}...)"}',
    ));
    if (token == null) {
      await Sentry.captureMessage(
        '[PushToken] getToken returned null — APNs key may be missing in Firebase',
        level: SentryLevel.warning,
      );
      return;
    }

    await _upsertToken(token);

    // Refresh token whenever FCM rotates it
    messaging.onTokenRefresh.listen(_upsertToken);
  }

  static Future<void> _upsertToken(String token) async {
    if (!SupabaseService.isLoggedIn) return;
    final authId = SupabaseService.currentUserId;
    if (authId == null) return;

    try {
      final userRow = await SupabaseService.client
          .from('users')
          .select('id')
          .eq('auth_id', authId)
          .maybeSingle();
      if (userRow == null) {
        await Sentry.captureMessage(
          '[PushToken] no users row found for auth_id $authId',
          level: SentryLevel.warning,
        );
        return;
      }
      final userId = userRow['id'] as String;

      await SupabaseService.client.from('device_tokens').upsert(
        {
          'user_id':    userId,
          'token':      token,
          'platform':   'ios',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id, token',
      );
      Sentry.addBreadcrumb(Breadcrumb(
        message: '[PushToken] token upserted for user $userId',
      ));
    } catch (e, st) {
      await Sentry.captureException(e, stackTrace: st,
          hint: Hint.withMap({'context': '[PushToken] upsert failed'}));
    }
  }

  static Future<void> deleteToken() async {
    if (!SupabaseService.isLoggedIn) return;
    if (Firebase.apps.isEmpty) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    final authId = SupabaseService.currentUserId;
    if (authId == null) return;

    try {
      final userRow = await SupabaseService.client
          .from('users')
          .select('id')
          .eq('auth_id', authId)
          .maybeSingle();
      if (userRow == null) return;
      final userId = userRow['id'] as String;

      await SupabaseService.client
          .from('device_tokens')
          .delete()
          .eq('user_id', userId)
          .eq('token', token);
    } catch (_) {}
  }
}