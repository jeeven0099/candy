import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'supabase_service.dart';

class GmailConnectionStatus {
  final String? googleEmail;
  final String status;
  final DateTime? lastSyncAt;
  final String? syncError;

  const GmailConnectionStatus({
    this.googleEmail,
    required this.status,
    this.lastSyncAt,
    this.syncError,
  });

  bool get isConnected => status == 'connected';

  factory GmailConnectionStatus.fromJson(Map<String, dynamic> json) {
    return GmailConnectionStatus(
      googleEmail: json['google_email'] as String?,
      status: json['status'] as String? ?? 'unknown',
      lastSyncAt: _parseDate(json['last_sync_at']),
      syncError: json['sync_error'] as String?,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

class GmailConnectionService {
  static bool _pendingConnect = false;
  static String? _pendingAuthId;
  static String? _previousSignInAt;
  static bool _vaulting = false;
  static const _pendingAuthKey = 'gmail_connect_auth_id';
  static const _pendingStartedKey = 'gmail_connect_started_at';
  static const _previousSignInKey = 'gmail_connect_previous_sign_in';

  static bool get hasPendingConnect => _pendingConnect;

  static Future<GmailConnectionStatus?> loadStatus() async {
    if (!SupabaseService.isLoggedIn) return null;
    try {
      final row = await SupabaseService.client
          .from('gmail_connections')
          .select('google_email,status,last_sync_at,sync_error')
          .maybeSingle();
      if (row == null) return null;
      return GmailConnectionStatus.fromJson(row);
    } catch (e) {
      debugPrint('[GmailConnectionService] loadStatus: $e');
      return null;
    }
  }

  static Future<void> startConnect() async {
    final authId = SupabaseService.currentUserId;
    if (authId == null) throw StateError('Sign in before connecting Gmail.');
    final prefs = await SharedPreferences.getInstance();
    _previousSignInAt = SupabaseService.currentUser?.lastSignInAt;
    if (_previousSignInAt != null) {
      await prefs.setString(_previousSignInKey, _previousSignInAt!);
    } else {
      await prefs.remove(_previousSignInKey);
    }
    await prefs.setString(_pendingAuthKey, authId);
    await prefs.setInt(
      _pendingStartedKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    _pendingAuthId = authId;
    _pendingConnect = true;
    try {
      await AuthService.connectGmailForDeals();
    } catch (_) {
      await cancelPendingConnect();
      rethrow;
    }
  }

  static Future<void> restorePendingConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final started = prefs.getInt(_pendingStartedKey);
    final authId = prefs.getString(_pendingAuthKey);
    if (started == null || authId == null) return;
    if (DateTime.now().millisecondsSinceEpoch - started >
        const Duration(minutes: 30).inMilliseconds) {
      await cancelPendingConnect();
      return;
    }
    _pendingAuthId = authId;
    _previousSignInAt = prefs.getString(_previousSignInKey);
    _pendingConnect = true;
  }

  static Future<bool> vaultSessionIfPending(Session? session) async {
    if (!_pendingConnect || session == null || _vaulting) return false;
    if (session.user.id != _pendingAuthId) {
      await cancelPendingConnect();
      throw StateError(
        'Use the Google account associated with your Candy account.',
      );
    }
    final providerToken = session.providerToken;
    final providerRefreshToken = session.providerRefreshToken;
    if (session.user.lastSignInAt == _previousSignInAt) return false;
    if (providerToken == null || providerToken.isEmpty) {
      return false;
    }

    _vaulting = true;
    try {
      await SupabaseService.client.functions.invoke(
        'gmail-token-vault',
        body: {
          'access_token': providerToken,
          'refresh_token': providerRefreshToken,
          'token_type': 'Bearer',
          'google_email': session.user.email,
          'scopes': [
            'openid',
            'email',
            'profile',
            'https://www.googleapis.com/auth/gmail.readonly',
          ],
        },
      );
      await cancelPendingConnect();
      return true;
    } finally {
      _vaulting = false;
    }
  }

  static Future<void> cancelPendingConnect() async {
    _pendingConnect = false;
    _pendingAuthId = null;
    _previousSignInAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingAuthKey);
    await prefs.remove(_pendingStartedKey);
    await prefs.remove(_previousSignInKey);
  }
}
