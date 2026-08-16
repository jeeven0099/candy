import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'push_token_service.dart';

String _appPlatform() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:     return 'ios';
    case TargetPlatform.android: return 'android';
    case TargetPlatform.macOS:   return 'macos';
    case TargetPlatform.windows: return 'windows';
    default:                     return 'unknown';
  }
}

class AuthService {
  static SupabaseClient get _sb => SupabaseService.client;

  /// Sign up with email + password + beta invite code.
  static Future<void> signUp({
    required String email,
    required String password,
    required String inviteCode,
  }) async {
    final code = inviteCode.trim().toUpperCase();

    // Validate invite code against DB
    final row = await _sb
        .from('invite_codes')
        .select('code, max_uses, use_count')
        .eq('code', code)
        .maybeSingle();

    if (row == null) {
      throw const AuthException('Invalid invite code. Check with the Candy team.');
    }
    final maxUses  = (row['max_uses']  as int?) ?? 0;
    final useCount = (row['use_count'] as int?) ?? 0;
    if (useCount >= maxUses) {
      throw const AuthException('This invite code has reached its limit.');
    }

    // Create Supabase auth account
    final res = await _sb.auth.signUp(email: email.trim(), password: password);
    if (res.user == null) {
      throw const AuthException('Sign up failed. Please try again.');
    }

    // Insert user profile row
    try {
      await _sb.from('users').insert({
        'auth_id':      res.user!.id,
        'email':        res.user!.email,
        'invite_code':  code,
        'app_platform': _appPlatform(),
      });
    } catch (_) {}

    // Increment use_count (best-effort â€” non-fatal if RLS blocks it)
    try {
      await _sb.from('invite_codes')
          .update({'use_count': useCount + 1})
          .eq('code', code);
    } catch (_) {}

    PushTokenService.register();
  }

  static Future<void> signIn({
    required String email,
    required String password,
  }) async {
    final res = await _sb.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    // Update last_login_at (and backfill email/platform for accounts created before these columns)
    if (res.user != null) {
      try {
        await _sb.from('users').update({
          'last_login_at': DateTime.now().toIso8601String(),
          'email':         res.user!.email,
          'app_platform':  _appPlatform(),
        }).eq('auth_id', res.user!.id);
      } catch (_) {}
      PushTokenService.register();
    }
  }

  static Future<void> signOut() async {
    await _sb.auth.signOut();
  }

  // Deep link scheme registered in iOS Info.plist / Android manifest.
  // Must match the redirect URL configured in Supabase dashboard → Auth → URL Config.
  static const _redirectUrl = 'com.jeeven.candy://login-callback/';

  static Future<void> signInWithGoogle() async {
    await _sb.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _redirectUrl,
    );
  }

  static Future<void> signInWithApple() async {
    await _sb.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: _redirectUrl,
    );
  }

  /// Upserts the users table row after OAuth sign-in (non-fatal if it fails).
  static Future<void> ensureUserRow() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    try {
      await _sb.from('users').upsert({
        'auth_id':      user.id,
        'email':        user.email,
        'app_platform': _appPlatform(),
      }, onConflict: 'auth_id');
    } catch (_) {}
    PushTokenService.register();
  }

  /// Human-readable message from a Supabase AuthException.
  static String friendlyError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login')) return 'Incorrect email or password.';
    if (msg.contains('already registered') || msg.contains('already exists')) {
      return 'An account with this email already exists.';
    }
    if (msg.contains('password')) {
      return 'Password must be at least 8 characters, with letters and numbers.';
    }
    if (msg.contains('email')) return 'Please enter a valid email address.';
    return e.message;
  }
}

