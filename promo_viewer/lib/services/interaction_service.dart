import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/promotion.dart';
import 'supabase_service.dart';
import 'user_prefs_service.dart';

/// Tracks per-deal user interactions.
/// Local SharedPreferences state drives fatigue/affinity in the runtime ranker.
/// Supabase writes are fire-and-forget: they populate analytics tables and
/// the brand/category affinity RPCs for future ML use.
class InteractionService {
  static final InteractionService _i = InteractionService._();
  factory InteractionService() => _i;
  InteractionService._();

  static const _seen     = 'ftg_s_';
  static const _lastSeen = 'ftg_ls_';
  static const _click    = 'ftg_c_';
  static const _redeem   = 'ftg_r_';
  static const _brandSrc = 'ftg_bs_';

  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toRadixString(16);

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
      final next = (p.getInt('$_seen$id') ?? 0) + 1;
      await p.setInt('$_seen$id', next);
      await p.setString('$_lastSeen$id', now);
      debugPrint('[Fatigue] recordSeen $id → seenCount=$next');
    }
  }

  // ── Click ─────────────────────────────────────────────────────────────────

  int clickCount(String id) => _prefs?.getInt('$_click$id') ?? 0;

  Future<void> recordClick(
    String id, {
    String brand = '',
    String category = '',
  }) async {
    final p = _prefs;
    if (p == null) return;
    final nextClick = (p.getInt('$_click$id') ?? 0) + 1;
    await p.setInt('$_click$id', nextClick);
    // Opening the detail counts as a view — bumping seenCount here means
    // fatigue accrues even if ForYouScreen doesn't re-render between sessions.
    final nextSeen = (p.getInt('$_seen$id') ?? 0) + 1;
    await p.setInt('$_seen$id', nextSeen);
    await p.setString('$_lastSeen$id', DateTime.now().toIso8601String());
    debugPrint('[Fatigue] recordClick $id → clicks=$nextClick seenCount=$nextSeen');

    _writeInteraction('deal_card_clicked',
        promotionId: id, brand: brand, category: category);
    if (brand.isNotEmpty) _bumpBrandAffinity(brand, clicks: 1);
    if (category.isNotEmpty) _bumpCategoryAffinity(category, clicks: 1);
  }

  // ── Fast Redeem ───────────────────────────────────────────────────────────

  bool hasFastRedeemed(String id) => _prefs?.getBool('$_redeem$id') ?? false;

  Future<void> recordFastRedeem(String id, {String brand = '', String category = ''}) async {
    await _prefs?.setBool('$_redeem$id', true);

    _writeInteraction('fast_redeem_clicked',
        promotionId: id, brand: brand, category: category);
    if (brand.isNotEmpty) _bumpBrandAffinity(brand, fastRedeems: 1);
    if (category.isNotEmpty) _bumpCategoryAffinity(category, saves: 1);
  }

  // ── Brand search ──────────────────────────────────────────────────────────

  bool isBrandRecentlySearched(String brand, {int withinDays = 3}) {
    final s = _prefs?.getString('$_brandSrc${_norm(brand)}');
    if (s == null) return false;
    final dt = DateTime.tryParse(s);
    return dt != null && DateTime.now().difference(dt).inDays < withinDays;
  }

  Future<void> recordBrandSearch(String brand) async {
    await _prefs?.setString(
        '$_brandSrc${_norm(brand)}', DateTime.now().toIso8601String());
    _writeInteraction('search_submitted', brand: brand);
    _bumpBrandAffinity(brand, searches: 1);
  }

  // ── Query search tracking ─────────────────────────────────────────────────

  static const _srchPrefix   = 'srch_q_';
  static const _srchFailedKey = 'srch_failed_list';

  Future<void> recordSearch(String query, int resultCount, {String context = ''}) async {
    final p = _prefs;
    if (p == null || query.trim().isEmpty) return;
    final normed = _norm(query);

    // Local counts
    final key = '$_srchPrefix$normed';
    await p.setInt(key, (p.getInt(key) ?? 0) + 1);
    if (resultCount == 0) {
      final failed = List<String>.from(p.getStringList(_srchFailedKey) ?? []);
      if (!failed.contains(normed)) {
        failed.add(normed);
        if (failed.length > 50) failed.removeAt(0);
        await p.setStringList(_srchFailedKey, failed);
      }
    }

    // Supabase search_events
    _writeSearchEvent(query, normed, resultCount, context: context);
  }

  List<String> getFailedSearches() =>
      List<String>.from(_prefs?.getStringList(_srchFailedKey) ?? []);

  // ── Recent searches ───────────────────────────────────────────────────────

  static const _recentKey = 'srch_recent';

  Future<void> recordRecentSearch(String query) async {
    final q = query.trim();
    if (q.length < 2) return;
    final p = _prefs;
    if (p == null) return;
    final raw = List<String>.from(p.getStringList(_recentKey) ?? []);
    raw.remove(q);
    raw.insert(0, q);
    if (raw.length > 10) raw.removeLast();
    await p.setStringList(_recentKey, raw);
  }

  List<String> getRecentSearches() =>
      List<String>.from(_prefs?.getStringList(_recentKey) ?? []);

  Future<void> clearRecentSearch(String query) async {
    final p = _prefs;
    if (p == null) return;
    final raw = List<String>.from(p.getStringList(_recentKey) ?? []);
    raw.remove(query.trim());
    await p.setStringList(_recentKey, raw);
  }

  // ── Notification feedback ─────────────────────────────────────────────────

  Future<void> recordNotificationFeedback(
    String promoId, String brand, String category, bool interested) async {
    _writeInteraction(
      interested ? 'notification_interested' : 'notification_dismissed',
      promotionId: promoId,
      brand: brand,
      category: category,
    );
  }

  // ── Deal skip ─────────────────────────────────────────────────────────────

  static const _skipDeal = 'skip_deal_';

  bool isDealSkipped(String id) => _prefs?.getBool('$_skipDeal$id') ?? false;

  Future<void> skipDeal(String id) async {
    await _prefs?.setBool('$_skipDeal$id', true);
    _writeInteraction('not_interested', promotionId: id);
  }

  Future<void> unskipDeal(String id) async {
    await _prefs?.remove('$_skipDeal$id');
  }

  // ── Supabase: user_interactions ───────────────────────────────────────────

  void _writeInteraction(
    String eventType, {
    String promotionId = '',
    String brand = '',
    String category = '',
    String context = '',
    int? rankPosition,
    double? scoreAtEvent,
    Map<String, dynamic>? metadata,
  }) {
    if (!SupabaseService.isLoggedIn) return;
    final uid = UserPrefsService().userId;
    if (uid == null) return;

    final row = <String, dynamic>{
      'user_id':    uid,
      'session_id': _sessionId,
      'event_type': eventType,
    };
    if (promotionId.isNotEmpty) row['promotion_id']  = promotionId;
    if (brand.isNotEmpty)       row['brand']          = brand;
    if (category.isNotEmpty)    row['category']       = category;
    if (context.isNotEmpty)     row['context']        = context;
    if (rankPosition != null)   row['rank_position']  = rankPosition;
    if (scoreAtEvent != null)   row['score_at_event'] = scoreAtEvent;
    if (metadata != null)       row['metadata']       = metadata;

    SupabaseService.client.from('user_interactions').insert(row)
        .then((_) {}, onError: (e) {
      if (kDebugMode) debugPrint('[InteractionService] $eventType: $e');
    });
  }

  // ── Supabase: search_events ───────────────────────────────────────────────

  void _writeSearchEvent(
    String query,
    String normedQuery,
    int resultCount, {
    String context = '',
  }) {
    if (!SupabaseService.isLoggedIn) return;
    final uid = UserPrefsService().userId;

    final row = <String, dynamic>{
      'session_id':       _sessionId,
      'query':            query,
      'normalized_query': normedQuery,
      'result_count':     resultCount,
      'no_result':        resultCount == 0,
    };
    if (uid != null)         row['user_id'] = uid;
    if (context.isNotEmpty)  row['context'] = context;

    SupabaseService.client.from('search_events').insert(row)
        .then((_) {}, onError: (e) {
      if (kDebugMode) debugPrint('[InteractionService] search_event: $e');
    });
  }

  // ── Supabase: brand & category affinity (via RPC) ─────────────────────────

  void _bumpBrandAffinity(
    String brand, {
    int views = 0,
    int clicks = 0,
    int saves = 0,
    int fastRedeems = 0,
    int searches = 0,
    int ignored = 0,
  }) {
    if (!SupabaseService.isLoggedIn) return;
    final uid = UserPrefsService().userId;
    if (uid == null || brand.isEmpty) return;

    SupabaseService.client.rpc('increment_brand_affinity', params: {
      'p_user_id':      uid,
      'p_brand':        brand,
      'p_views':        views,
      'p_clicks':       clicks,
      'p_saves':        saves,
      'p_fast_redeems': fastRedeems,
      'p_searches':     searches,
      'p_ignored':      ignored,
    }).then((_) {}, onError: (e) {
      if (kDebugMode) debugPrint('[InteractionService] brand_affinity: $e');
    });
  }

  void _bumpCategoryAffinity(
    String category, {
    int views = 0,
    int clicks = 0,
    int saves = 0,
    int searches = 0,
    int ignored = 0,
  }) {
    if (!SupabaseService.isLoggedIn) return;
    final uid = UserPrefsService().userId;
    if (uid == null || category.isEmpty) return;

    SupabaseService.client.rpc('increment_category_affinity', params: {
      'p_user_id':   uid,
      'p_category':  category,
      'p_views':     views,
      'p_clicks':    clicks,
      'p_saves':     saves,
      'p_searches':  searches,
      'p_ignored':   ignored,
    }).then((_) {}, onError: (e) {
      if (kDebugMode) debugPrint('[InteractionService] category_affinity: $e');
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void recordSearchEvent(String type, {Map<String, String>? params}) {
    if (kDebugMode) {
      final extra = params?.entries.map((e) => '${e.key}=${e.value}').join(', ') ?? '';
      debugPrint('[Search:$type]${extra.isEmpty ? '' : ' $extra'}');
    }
    _writeInteraction(
      type,
      brand: params?['brand'] ?? '',
      context: params?['chip'] ?? '',
      metadata: params != null ? Map<String, dynamic>.from(params) : null,
    );
  }

  // ── High-level action trackers ────────────────────────────────────────────

  void recordSessionStart() => _writeInteraction('session_start');

  // ── Deal detail analytics ─────────────────────────────────────────────────

  void recordDealCardOpened(
    String promoId, {
    String brand = '',
    String category = '',
    int? rankPosition,
    Map<String, dynamic>? meta,
  }) =>
      _writeInteraction('deal_card_opened',
          promotionId: promoId,
          brand: brand,
          category: category,
          rankPosition: rankPosition,
          metadata: meta);

  void recordDetailScrolled(String promoId, {String brand = '', Map<String, dynamic>? meta}) =>
      _writeInteraction('deal_detail_scrolled',
          promotionId: promoId, brand: brand, metadata: meta);

  void recordRedeemClicked(
    String promoId, {
    String brand = '',
    String actionType = '',
    Map<String, dynamic>? meta,
  }) {
    final merged = <String, dynamic>{
      if (actionType.isNotEmpty) 'action_type': actionType,
      ...?meta,
    };
    _writeInteraction('redeem_clicked',
        promotionId: promoId, brand: brand, metadata: merged.isEmpty ? null : merged);
  }

  void recordCodeCopied(
    String promoId, {
    String brand = '',
    String code = '',
    Map<String, dynamic>? meta,
  }) {
    final merged = <String, dynamic>{
      if (code.isNotEmpty) 'code': code,
      ...?meta,
    };
    _writeInteraction('code_copied',
        promotionId: promoId, brand: brand, metadata: merged.isEmpty ? null : merged);
  }

  void recordRestrictionExpanded(String promoId,
          {String brand = '', Map<String, dynamic>? meta}) =>
      _writeInteraction('restriction_expanded',
          promotionId: promoId, brand: brand, metadata: meta);

  void recordHistoricalComparisonViewed(String promoId,
          {String brand = '', Map<String, dynamic>? meta}) =>
      _writeInteraction('historical_comparison_viewed',
          promotionId: promoId, brand: brand, metadata: meta);

  void recordDealSaved(String promoId,
          {String brand = '', String category = '', Map<String, dynamic>? meta}) =>
      _writeInteraction('deal_saved',
          promotionId: promoId, brand: brand, category: category, metadata: meta);

  // ── Rich event metadata builder ───────────────────────────────────────────
  //
  // Call at every analytics site that has a Promotion in scope:
  //   meta: InteractionService.promoMeta(promo, feedPosition: i, rankingMode: 'forYou')
  //
  static Map<String, dynamic> promoMeta(
    Promotion p, {
    String? rankingMode,
    int? feedPosition,
  }) {
    final m = <String, dynamic>{
      'brand_id': _norm(p.brand),
      'value_tier': _valueTier(p.globalQualityScore),
      'effort_type': _effortType(p),
    };
    if (p.globalQualityScore > 0) m['global_quality_score'] = p.globalQualityScore;
    if (p.economicValueScore > 0) m['economic_value_score'] = p.economicValueScore;
    if (p.effectiveDiscountPct > 0) m['effective_discount_pct'] = p.effectiveDiscountPct;
    final days = _daysUntilExpiry(p);
    if (days != null) m['days_until_expiry'] = days;
    if (rankingMode != null) m['ranking_mode'] = rankingMode;
    if (feedPosition != null) m['feed_position'] = feedPosition;
    return m;
  }

  static String _valueTier(double score) {
    if (score >= 80) return 'excellent';
    if (score >= 65) return 'great';
    if (score >= 50) return 'good';
    if (score >= 35) return 'fair';
    if (score > 0)  return 'low';
    return 'unscored';
  }

  static String _effortType(Promotion p) {
    final fr = p.fastRedemption;
    if (fr != null && fr.eligible) return fr.isLowEffort ? 'instant' : 'easy';
    if (p.requiresApp)      return 'app_required';
    if (p.promoCode != null) return 'code_required';
    if (!p.requiresMembership) return 'easy';
    return 'membership_required';
  }

  static int? _daysUntilExpiry(Promotion p) {
    if (p.endDate == null) return null;
    final end = DateTime.tryParse(p.endDate!);
    if (end == null) return null;
    final diff = end.difference(DateTime.now()).inDays;
    return diff >= 0 ? diff : null;
  }

  void recordTabSwitch(int tabIndex, String tabName) =>
      _writeInteraction('tab_switched',
          context: tabName, metadata: {'tab_index': tabIndex});

  void recordShopNow(String promoId, {String brand = ''}) =>
      _writeInteraction('shop_now_tapped', promotionId: promoId, brand: brand);

  void recordVerifyTap(String promoId, {String brand = ''}) =>
      _writeInteraction('verify_tapped', promotionId: promoId, brand: brand);

  void recordPromoCodeCopy(String promoId, {String brand = '', String code = ''}) =>
      _writeInteraction('promo_code_copied',
          promotionId: promoId,
          brand: brand,
          metadata: code.isNotEmpty ? {'code': code} : null);

  // Public so SavedDealsService can bump affinity on save/unsave
  void bumpBrandAffinityPublic(String brand, {int saves = 0, int ignored = 0}) =>
      _bumpBrandAffinity(brand, saves: saves, ignored: ignored);

  void bumpCategoryAffinityPublic(String category, {int saves = 0, int ignored = 0}) =>
      _bumpCategoryAffinity(category, saves: saves, ignored: ignored);

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
}
