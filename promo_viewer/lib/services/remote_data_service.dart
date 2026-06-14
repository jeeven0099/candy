import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

/// Fetches asset files from [kDataBaseUrl], caches in SharedPreferences,
/// and falls back to bundled assets when the server is unreachable.
///
/// Cache TTL: 6 hours. Stale cache is always preferred over a network error
/// so the app works offline after the first successful fetch.
class RemoteDataService {
  static const _ttlMs = 6 * 60 * 60 * 1000; // 6 hours
  static const _timeout = Duration(seconds: 12);

  static bool get _hasRemote => kDataBaseUrl.isNotEmpty;

  /// Load [filename] (e.g. 'all_promotions.json').
  /// Resolution order:
  ///   1. SharedPreferences cache (if fresh)
  ///   2. Remote URL (if reachable) → updates cache
  ///   3. SharedPreferences cache (stale but present)
  ///   4. Bundled assets
  static Future<String> load(String filename) async {
    if (!_hasRemote) {
      return rootBundle.loadString('assets/$filename');
    }

    final prefs = await SharedPreferences.getInstance();
    final cacheKey = '_rds_$filename';
    final tsKey = '_rds_ts_$filename';

    final cached = prefs.getString(cacheKey);
    final ts = prefs.getInt(tsKey) ?? 0;
    final ageMs = DateTime.now().millisecondsSinceEpoch - ts;

    // 1. Fresh cache
    if (cached != null && ageMs < _ttlMs) return cached;

    // 2. Try remote
    try {
      final uri = Uri.parse('${kDataBaseUrl.trimRight()}/$filename');
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode == 200) {
        final body = response.body;
        await prefs.setString(cacheKey, body);
        await prefs.setInt(tsKey, DateTime.now().millisecondsSinceEpoch);
        return body;
      }
    } catch (_) {}

    // 3. Stale cache — better than nothing
    if (cached != null) return cached;

    // 4. Bundled assets
    return rootBundle.loadString('assets/$filename');
  }

  /// Force-clear the cache for [filename] (e.g. after a manual refresh).
  static Future<void> clearCache(String filename) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('_rds_$filename');
    await prefs.remove('_rds_ts_$filename');
  }
}
