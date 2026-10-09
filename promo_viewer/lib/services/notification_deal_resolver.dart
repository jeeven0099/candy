import 'dart:convert';

import '../models/promotion.dart';
import 'email_deals_service.dart';
import 'promotions_service.dart';
import 'remote_data_service.dart';
import 'supabase_service.dart';

class NotificationDealResolver {
  NotificationDealResolver({
    Future<String> Function(bool forceRefresh)? loadCatalog,
    Future<List<Promotion>> Function()? loadEmailDeals,
  }) : _loadCatalog =
           loadCatalog ??
           ((refresh) => RemoteDataService.load(
             'all_promotions.json',
             forceRefresh: refresh,
           )),
       _loadEmailDeals = loadEmailDeals ?? EmailDealsService.loadForCurrentUser;

  final Future<String> Function(bool) _loadCatalog;
  final Future<List<Promotion>> Function() _loadEmailDeals;

  static bool matches(Promotion promo, String id) {
    if (promo.id == id) return true;
    // The existing push generator trims the slug before its 100-character cap.
    final slug = '${promo.brand}_${promo.title}'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return (slug.length > 100 ? slug.substring(0, 100) : slug) == id;
  }

  static Promotion? _find(Iterable<Promotion> deals, String id) {
    for (final promo in deals) {
      if (promo.id == id) return promo;
    }
    for (final promo in deals) {
      if (matches(promo, id)) return promo;
    }
    return null;
  }

  Future<Promotion?> resolve(String id) async {
    final cached = _find(PromotionsService.cached, id);
    if (cached != null) return cached;
    final owner = SupabaseService.currentUserId;
    // Resolve against the full catalog, not the feed's quality/dedup filters.
    for (final refresh in [false, true]) {
      final data =
          jsonDecode(await _loadCatalog(refresh)) as Map<String, dynamic>;
      final deals = (data['promotions'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Promotion.fromJson)
          .where((p) => p.title.isNotEmpty);
      final found = _find(deals, id);
      if (found != null) return found;
    }
    if (owner == null || owner != SupabaseService.currentUserId) return null;
    final emails = await _loadEmailDeals();
    if (owner != SupabaseService.currentUserId) return null;
    return _find(emails, id);
  }
}
