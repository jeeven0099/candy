import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'supabase_service.dart';

class PushTokenService {
  static Future<void> register() async {
    if (!SupabaseService.isLoggedIn) return;
    if (Firebase.apps.isEmpty) return;

    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await messaging.getToken();
    if (token == null) return;

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
      if (userRow == null) return;
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
    } catch (e) {
      // Non-fatal — push will still work on next successful register
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
