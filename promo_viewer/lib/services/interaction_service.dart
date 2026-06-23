import 'package:shared_preferences/shared_preferences.dart';

/// Tracks per-deal user interactions to power fatigue penalties and affinity boosts.
/// Singleton — call InteractionService() anywhere after init().
class InteractionService {
  static final InteractionService _i = InteractionService._();
  factory InteractionService() => _i;
  InteractionService._();

  static const _seen     = 'ftg_s_';   // → int (seen count)
  static const _lastSeen = 'ftg_ls_';  // → ISO date string
  static const _click    = 'ftg_c_';   // → int (click count)
  static const _redeem   = 'ftg_r_';   // → bool
  static const _brandSrc = 'ftg_bs_';  // → ISO date string (last searched)

  SharedPreferences? _prefs;

  static Future<void> init() async {
    _i._prefs = await SharedPreferences.getInstance();
  }

  // ── Seen ──────────────────────────────────────────────────────────────────

  int seenCount(String id) => _prefs?.getInt('$_seen$id') ?? 0;

  DateTime? lastSeenAt(String id) {
    final s = _prefs?.getString('$_lastSeen$id');
    return s != null ? DateTime.tryParse(s) : null;
  }

  Future<void> recordSeen(List<String> ids) async {
    final p = _prefs;
    if (p == null || ids.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    for (final id in ids) {
      await p.setInt('$_seen$id', (p.getInt('$_seen$id') ?? 0) + 1);
      await p.setString('$_lastSeen$id', now);
    }
  }

  // ── Click ─────────────────────────────────────────────────────────────────

  int clickCount(String id) => _prefs?.getInt('$_click$id') ?? 0;

  Future<void> recordClick(String id) async {
    final p = _prefs;
    if (p == null) return;
    await p.setInt('$_click$id', (p.getInt('$_click$id') ?? 0) + 1);
  }

  // ── Fast Redeem ───────────────────────────────────────────────────────────

  bool hasFastRedeemed(String id) => _prefs?.getBool('$_redeem$id') ?? false;

  Future<void> recordFastRedeem(String id) async {
    await _prefs?.setBool('$_redeem$id', true);
  }

  // ── Brand search ──────────────────────────────────────────────────────────

  bool isBrandRecentlySearched(String brand, {int withinDays = 3}) {
    final s = _prefs?.getString('$_brandSrc${_norm(brand)}');
    if (s == null) return false;
    final dt = DateTime.tryParse(s);
    return dt != null && DateTime.now().difference(dt).inDays < withinDays;
  }

  Future<void> recordBrandSearch(String brand) async {
    await _prefs?.setString('$_brandSrc${_norm(brand)}', DateTime.now().toIso8601String());
  }

  // ── Query search tracking ─────────────────────────────────────────────────

  static const _srchPrefix = 'srch_q_';
  static const _srchFailedKey = 'srch_failed_list';

  Future<void> recordSearch(String query, int resultCount) async {
    final p = _prefs;
    if (p == null || query.trim().isEmpty) return;
    final key = '$_srchPrefix${_norm(query)}';
    await p.setInt(key, (p.getInt(key) ?? 0) + 1);
    if (resultCount == 0) {
      final normed = _norm(query);
      final failed = List<String>.from(p.getStringList(_srchFailedKey) ?? []);
      if (!failed.contains(normed)) {
        failed.add(normed);
        if (failed.length > 50) failed.removeAt(0);
        await p.setStringList(_srchFailedKey, failed);
      }
    }
  }

  List<String> getFailedSearches() =>
      List<String>.from(_prefs?.getStringList(_srchFailedKey) ?? []);

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
}
