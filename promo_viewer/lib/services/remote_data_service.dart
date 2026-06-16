import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

/// Fetches asset files from a dynamically-discovered server URL, caches in
/// SharedPreferences, and falls back to bundled assets when offline.
///
/// Server discovery: on first load (or when the cached URL is stale), the
/// service fetches [kConfigUrl] (a stable GitHub raw file) to get the current
/// server URL. Edit server_config.json in the repo and push to update it —
/// no app rebuild required.
///
/// Cache TTLs:
///   Server URL:  1 hour  (propagates server changes within an hour)
///   Asset data:  6 hours (stale data preferred over a network error)
class RemoteDataService {
  static const _dataTtlMs   = 6 * 60 * 60 * 1000; // 6 h
  static const _serverTtlMs = 1 * 60 * 60 * 1000; // 1 h
  static const _timeout     = Duration(seconds: 12);

  static const _serverUrlKey   = '_rds_server_url';
  static const _serverUrlTsKey = '_rds_server_url_ts';

  // In-process cache so parallel load() calls don't all hit SharedPreferences.
  static String? _serverUrlMem;

  /// Returns the current server base URL, discovering it from [kConfigUrl]
  /// if the cached value is absent or stale.
  static Future<String?> _resolveServerUrl() async {
    final prefs = await SharedPreferences.getInstance();

    // In-memory hit
    if (_serverUrlMem != null) {
      final ts = prefs.getInt(_serverUrlTsKey) ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - ts < _serverTtlMs) {
        return _serverUrlMem;
      }
    }

    // SharedPreferences hit
    final cached = prefs.getString(_serverUrlKey);
    final ts     = prefs.getInt(_serverUrlTsKey) ?? 0;
    if (cached != null &&
        DateTime.now().millisecondsSinceEpoch - ts < _serverTtlMs) {
      _serverUrlMem = cached;
      return cached;
    }

    // Fetch from GitHub bootstrap
    try {
      final response =
          await http.get(Uri.parse(kConfigUrl)).timeout(_timeout);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final url  = (data['server_url'] as String?)?.trimRight();
        if (url != null && url.isNotEmpty) {
          _serverUrlMem = url;
          await prefs.setString(_serverUrlKey, url);
          await prefs.setInt(
              _serverUrlTsKey, DateTime.now().millisecondsSinceEpoch);
          return url;
        }
      }
    } catch (_) {}

    // Fall back to stale cached URL rather than nothing
    if (cached != null && cached.isNotEmpty) {
      _serverUrlMem = cached;
      return cached;
    }

    return null; // no server — use bundled assets
  }

  /// Load [filename] (e.g. 'all_promotions.json').
  /// Resolution order:
  ///   1. SharedPreferences cache (if fresh)
  ///   2. Remote server (discovered via kConfigUrl) → updates cache
  ///   3. SharedPreferences cache (stale)
  ///   4. Bundled assets
  static Future<String> load(String filename) async {
    final prefs   = await SharedPreferences.getInstance();
    final cacheKey = '_rds_$filename';
    final tsKey    = '_rds_ts_$filename';

    final cached = prefs.getString(cacheKey);
    final ts     = prefs.getInt(tsKey) ?? 0;
    final ageMs  = DateTime.now().millisecondsSinceEpoch - ts;

    // 1. Fresh cache
    if (cached != null && ageMs < _dataTtlMs) return cached;

    // 2. Try remote
    final serverUrl = await _resolveServerUrl();
    if (serverUrl != null) {
      try {
        final uri      = Uri.parse('$serverUrl/$filename');
        final response = await http.get(uri).timeout(_timeout);
        if (response.statusCode == 200) {
          final body = response.body;
          await prefs.setString(cacheKey, body);
          await prefs.setInt(tsKey, DateTime.now().millisecondsSinceEpoch);
          return body;
        }
      } catch (_) {}
    }

    // 3. Stale cache
    if (cached != null) return cached;

    // 4. Bundled assets
    return rootBundle.loadString('assets/$filename');
  }

  /// Force-clear the data cache for [filename] (e.g. on pull-to-refresh).
  static Future<void> clearCache(String filename) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('_rds_$filename');
    await prefs.remove('_rds_ts_$filename');
  }

  /// Force-clear the cached server URL so it re-discovers on next load.
  static Future<void> clearServerUrl() async {
    _serverUrlMem = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_serverUrlKey);
    await prefs.remove(_serverUrlTsKey);
  }
}
