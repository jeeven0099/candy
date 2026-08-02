import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

/// Fetches asset files from a dynamically-discovered server URL, caches to
/// disk (not SharedPreferences), and falls back to bundled assets when offline.
///
/// Large JSON files (all_promotions.json, brand_locations.json) are written to
/// the app's support directory so iOS does not keep them in RAM permanently.
class RemoteDataService {
  static const _dataTtlMs   = 6 * 60 * 60 * 1000; // 6 h
  static const _serverTtlMs = 1 * 60 * 60 * 1000; // 1 h
  static const _timeout     = Duration(seconds: 12);

  static const _serverUrlKey   = '_rds_server_url';
  static const _serverUrlTsKey = '_rds_server_url_ts';

  static String? _serverUrlMem;

  static Future<Directory> _cacheDir() async {
    final base = await getApplicationSupportDirectory();
    final dir  = Directory('${base.path}/rds_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<File> _cacheFile(String filename) async {
    final dir = await _cacheDir();
    return File('${dir.path}/${filename.replaceAll('/', '_')}');
  }

  static Future<File> _tsFile(String filename) async {
    final dir = await _cacheDir();
    return File('${dir.path}/${filename.replaceAll('/', '_')}.ts');
  }

  static Future<String?> _resolveServerUrl() async {
    final prefs = await SharedPreferences.getInstance();

    if (_serverUrlMem != null) {
      final ts = prefs.getInt(_serverUrlTsKey) ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - ts < _serverTtlMs) {
        return _serverUrlMem;
      }
    }

    final cached = prefs.getString(_serverUrlKey);
    final ts     = prefs.getInt(_serverUrlTsKey) ?? 0;
    if (cached != null &&
        DateTime.now().millisecondsSinceEpoch - ts < _serverTtlMs) {
      _serverUrlMem = cached;
      return cached;
    }

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

    if (cached != null && cached.isNotEmpty) {
      _serverUrlMem = cached;
      return cached;
    }

    return null;
  }

  static Future<String> load(String filename) async {
    final cf = await _cacheFile(filename);
    final tf = await _tsFile(filename);

    // 1. Fresh disk cache
    if (cf.existsSync() && tf.existsSync()) {
      final ts    = int.tryParse(await tf.readAsString()) ?? 0;
      final ageMs = DateTime.now().millisecondsSinceEpoch - ts;
      if (ageMs < _dataTtlMs) return cf.readAsString();
    }

    // 2. Try remote
    final serverUrl = await _resolveServerUrl();
    if (serverUrl != null) {
      try {
        final uri      = Uri.parse('$serverUrl/$filename');
        final response = await http.get(uri).timeout(_timeout);
        if (response.statusCode == 200) {
          final body = response.body;
          await cf.writeAsString(body);
          await tf.writeAsString(
              '${DateTime.now().millisecondsSinceEpoch}');
          return body;
        }
      } catch (_) {}
    }

    // 3. Stale disk cache
    if (cf.existsSync()) return cf.readAsString();

    // 4. Bundled assets
    return rootBundle.loadString('assets/$filename');
  }

  static Future<void> clearCache(String filename) async {
    final cf = await _cacheFile(filename);
    final tf = await _tsFile(filename);
    if (cf.existsSync()) cf.deleteSync();
    if (tf.existsSync()) tf.deleteSync();

    // Also clear old SharedPreferences cache entries from previous versions
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('_rds_$filename');
    await prefs.remove('_rds_ts_$filename');
  }

  static Future<void> clearServerUrl() async {
    _serverUrlMem = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_serverUrlKey);
    await prefs.remove(_serverUrlTsKey);
  }
}