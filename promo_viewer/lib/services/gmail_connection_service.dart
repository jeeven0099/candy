import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'supabase_service.dart';
import '../utils/gmail_diagnostics.dart';

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
  static const _attemptKey = 'gmail_connect_attempt_id';
  static String? _attemptId;
  static final diagnosticLog = ValueNotifier<String>('');
  static final lastError = ValueNotifier<String?>(null);
  static final _entries = <String>[];

  static bool get hasPendingConnect => _pendingConnect;

  static Iterable<String?> get _secrets {
    final session = SupabaseService.isReady
        ? SupabaseService.client.auth.currentSession
        : null;
    return [
      session?.accessToken,
      session?.refreshToken,
      session?.providerToken,
      session?.providerRefreshToken,
    ];
  }

  static void log(String stage, String message, {bool isError = false}) {
    final safe = redactGmailDiagnostic(message, secrets: _secrets);
    final entry =
        '${DateTime.now().toUtc().toIso8601String()} '
        '[${_attemptId ?? 'no-attempt'}] $stage: $safe';
    _entries.add(entry);
    if (_entries.length > 40) _entries.removeAt(0);
    diagnosticLog.value = _entries.join('\n');
    debugPrint('[GmailConnection] $entry');
    Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'gmail.connection',
        message: entry,
        level: isError ? SentryLevel.error : SentryLevel.info,
      ),
    );
    if (isError) {
      unawaited(
        Sentry.captureMessage(
          entry,
          level: SentryLevel.error,
        ).then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    }
  }

  static String reportFailure(String stage, Object error) {
    Map<String, dynamic>? details;
    int? status;
    String message;
    if (error is FunctionException) {
      status = error.status;
      var body = error.details;
      if (body is String) {
        try {
          body = jsonDecode(body);
        } catch (_) {}
      }
      if (body is Map) {
        details = {
          for (final key in body.keys)
            if (key is String) key: body[key],
        };
      }
      message = body is String
          ? body
          : error.reasonPhrase ?? 'Backend request failed';
    } else if (error is AuthException) {
      status = int.tryParse(error.statusCode ?? '');
      message = error.message;
      details = {'code': error.code ?? 'auth_error'};
    } else if (error is StateError) {
      message = error.message.toString();
    } else {
      message = error.toString();
    }
    final failure = formatGmailFailure(
      stage: stage,
      kind: error.runtimeType.toString(),
      message: message,
      httpStatus: status,
      details: details,
      secrets: _secrets,
    );
    lastError.value = failure;
    log(stage, failure, isError: true);
    return failure;
  }

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
      reportFailure('load_status', e);
      return null;
    }
  }

  static Future<void> startConnect() async {
    _entries.clear();
    diagnosticLog.value = '';
    lastError.value = null;
    _attemptId =
        '${DateTime.now().millisecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff).toRadixString(16)}';
    log('start', 'Gmail connection requested');
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
    await prefs.setString(_attemptKey, _attemptId!);
    await prefs.setInt(
      _pendingStartedKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    _pendingAuthId = authId;
    _pendingConnect = true;
    try {
      log('open_google', 'Opening Google consent');
      await AuthService.connectGmailForDeals();
      log('open_google', 'Browser opened; waiting for the OAuth return');
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
    _attemptId = prefs.getString(_attemptKey);
    _previousSignInAt = prefs.getString(_previousSignInKey);
    _pendingConnect = true;
  }

  static Future<bool> vaultSessionIfPending(
    Session? session, {
    bool fromOAuthCallback = false,
  }) async {
    if (!_pendingConnect || _vaulting) return false;
    if (session == null) {
      log('oauth_return', 'No session returned');
      if (fromOAuthCallback) {
        throw StateError('Google returned no Candy session.');
      }
      return false;
    }
    log(
      'oauth_return',
      'Session received; same Candy account=${session.user.id == _pendingAuthId}; '
          'new sign-in=${session.user.lastSignInAt != _previousSignInAt}; '
          'Gmail access token present=${session.providerToken?.isNotEmpty ?? false}; '
          'refresh token present=${session.providerRefreshToken?.isNotEmpty ?? false}',
    );
    if (session.user.id != _pendingAuthId) {
      await cancelPendingConnect();
      throw StateError(
        'Use the Google account associated with your Candy account.',
      );
    }
    final providerToken = session.providerToken;
    final providerRefreshToken = session.providerRefreshToken;
    if (session.user.lastSignInAt == _previousSignInAt) {
      log(
        'oauth_return',
        'Still using the previous session; awaiting Google callback',
      );
      if (fromOAuthCallback) {
        throw StateError('Google returned the previous sign-in session.');
      }
      return false;
    }
    if (providerToken == null || providerToken.isEmpty) {
      log('oauth_return', 'Google did not return a Gmail access token');
      if (fromOAuthCallback) {
        throw StateError(
          'Google did not return a Gmail access token. Gmail consent may not have completed.',
        );
      }
      return false;
    }

    _vaulting = true;
    try {
      log('save_connection', 'Calling gmail-token-vault');
      final response = await SupabaseService.client.functions.invoke(
        'gmail-token-vault',
        body: {
          'request_id': _attemptId,
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
      log('save_connection', 'Backend response HTTP ${response.status}');
      if (response.data is! Map || response.data['ok'] != true) {
        throw FunctionException(
          status: response.status,
          details: response.data,
          reasonPhrase: 'Unexpected Gmail connection response',
        );
      }
      log('connected', 'Gmail connection saved successfully');
      lastError.value = null;
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
    await prefs.remove(_attemptKey);
  }
}
