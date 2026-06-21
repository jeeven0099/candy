import '../models/promotion.dart';
import '../services/interaction_service.dart';
import '../services/saved_deals_service.dart';

const _kHide = 999.0;

/// Fatigue penalty based on how many times the user saw a deal with no interaction.
/// Returns _kHide when the deal should be suppressed from the default feed.
double fatiguePenalty(String id, InteractionService svc) {
  final seen = svc.seenCount(id);
  if (seen == 0) return 0;
  // Positive interactions cancel fatigue
  if (svc.clickCount(id) > 0 || svc.hasFastRedeemed(id)) return 0;
  switch (seen) {
    case 1:  return 5;
    case 2:  return 12;
    case 3:  return 22;
    default:
      // 4+ no-interaction views: hide for 7 days from last seen
      final last = svc.lastSeenAt(id);
      if (last != null && DateTime.now().difference(last).inDays < 7) return _kHide;
      return 22; // after cooldown: moderate penalty, back in rotation
  }
}

/// Affinity boost from positive signals: saved, fast-redeemed, clicked, brand searched.
double affinityBoost(Promotion p, InteractionService svc) {
  double boost = 0;
  if (SavedDealsService().get(p.id) != null) boost += 30;
  if (svc.hasFastRedeemed(p.id)) boost += 20;
  if (svc.clickCount(p.id) > 0) boost += 8;
  if (svc.isBrandRecentlySearched(p.brand)) boost += 15;
  return boost;
}

/// Full personalized score: base rank + affinity boost - fatigue penalty.
double personalizedScore(
  Promotion p,
  InteractionService svc, {
  double? distanceKm,
  bool isMember = false,
}) {
  final penalty = fatiguePenalty(p.id, svc);
  if (penalty >= _kHide) return -_kHide;
  return p.rankScore(distanceKm: distanceKm, isMember: isMember)
      + affinityBoost(p, svc)
      - penalty;
}

/// Selects the best [limit] deals from [candidates] using personalized scoring
/// and brand diversity (no more than [maxPerBrand] deals from the same brand).
///
/// Deals suppressed by fatigue (score == -_kHide) are excluded.
/// If brand diversity leaves slots unfilled, remaining top-scored deals fill them.
List<Promotion> selectTopDeals(
  List<Promotion> candidates,
  InteractionService svc, {
  double? Function(Promotion)? getDistance,
  bool Function(Promotion)? getIsMember,
  int limit = 10,
  int maxPerBrand = 2,
}) {
  final scored = <(Promotion, double)>[];
  for (final p in candidates) {
    final score = personalizedScore(
      p, svc,
      distanceKm: getDistance?.call(p),
      isMember: getIsMember?.call(p) ?? false,
    );
    if (score > -_kHide / 2) scored.add((p, score));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));

  final result = <Promotion>[];
  final brandCount = <String, int>{};

  // Pass 1: enforce brand cap
  for (final (promo, _) in scored) {
    if (result.length >= limit) break;
    final n = brandCount[promo.brand] ?? 0;
    if (n < maxPerBrand) {
      result.add(promo);
      brandCount[promo.brand] = n + 1;
    }
  }

  // Pass 2: fill any remaining slots with next-best (brand cap relaxed)
  if (result.length < limit) {
    for (final (promo, _) in scored) {
      if (result.length >= limit) break;
      if (!result.contains(promo)) result.add(promo);
    }
  }

  return result;
}
