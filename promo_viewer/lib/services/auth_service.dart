import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

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
    await _sb.from('users').insert({
      'auth_id':     res.user!.id,
      'invite_code': code,
    });

    // Increment use_count
    await _sb.from('invite_codes')
        .update({'use_count': useCount + 1})
        .eq('code', code);
  }

  static Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _sb.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  static Future<void> signOut() async {
    await _sb.auth.signOut();
  }

  /// Human-readable message from a Supabase AuthException.
  static String friendlyError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login')) return 'Incorrect email or password.';
    if (msg.contains('already registered') || msg.contains('already exists')) {
      return 'An account with this email already exists.';
    }
    if (msg.contains('password')) return 'Password must be at least 6 characters.';
    if (msg.contains('email')) return 'Please enter a valid email address.';
    return e.message;
  }
}
