import '../models/promotion.dart';
import '../models/user_prefs.dart';
import '../services/interaction_service.dart';
import '../services/saved_deals_service.dart';

const _kHide = 999.0;

// ---------------------------------------------------------------------------
// Score breakdown (for debug overlay)
// ---------------------------------------------------------------------------

class ScoreBreakdown {
  final double rankBase;
  final double distanceBonus;
  final double dayBonus;
  final double membershipBonus;
  final double affinityBoost;
  final double preferenceBoost;
  final double fatiguePenalty;
  final bool isHidden;

  const ScoreBreakdown({
    required this.rankBase,
    required this.distanceBonus,
    required this.dayBonus,
    required this.membershipBonus,
    required this.affinityBoost,
    required this.preferenceBoost,
    required this.fatiguePenalty,
    required this.isHidden,
  });

  double get total => isHidden
      ? double.negativeInfinity
      : rankBase + distanceBonus + dayBonus + membershipBonus + affinityBoost + preferenceBoost - fatiguePenalty;
}

ScoreBreakdown computeBreakdown(
  Promotion p,
  InteractionService svc, {
  double? distanceKm,
  bool isMember = false,
  UserPrefs? prefs,
}) {
  // Distance bonus
  double distBonus = 0;
  if (distanceKm != null) {
    final miles = distanceKm * 0.621371;
    if (miles <= 0.5)      { distBonus = 30; }
    else if (miles <= 1.0) { distBonus = 25; }
    else if (miles <= 2.0) { distBonus = 18; }
    else if (miles <= 5.0) { distBonus = 8; }
    else                   { distBonus = 2; }
  }

  // Day-of-week bonus
  double dayBonus = 0;
  if (p.validDays.isNotEmpty) {
    const dayNames = ['monday','tuesday','wednesday','thursday','friday','saturday','sunday'];
    const dayShort = ['mon','tue','wed','thu','fri','sat','sun'];
    final todayIdx = DateTime.now().weekday - 1;
    final normalized = p.validDays.map((d) => d.toLowerCase()).toList();
    final validToday = normalized.any(
      (d) => d == dayNames[todayIdx] || d == dayShort[todayIdx],
    );
    dayBonus = validToday ? 5 : -20;
  }

  // Membership bonus
  double memberBonus;
  if (isMember) {
    memberBonus = 25;
  } else if (!p.requiresMembership) {
    memberBonus = 8;
  } else {
    final cost = (p.membershipCost ?? '').toLowerCase();
    if (cost.contains('free'))       { memberBonus = -2; }
    else if (cost.contains('paid'))  { memberBonus = -15; }
    else                             { memberBonus = -5; }
  }

  // Device-side signals
  final rawFatigue = fatiguePenalty(p.id, svc);
  final hidden = rawFatigue >= _kHide;
  final aBoost = affinityBoost(p, svc);
  final pBoost = preferenceBoost(p, prefs);

  return ScoreBreakdown(
    rankBase: p.rankBaseScore,
    distanceBonus: distBonus,
    dayBonus: dayBonus,
    membershipBonus: memberBonus,
    affinityBoost: aBoost,
    preferenceBoost: pBoost,
    fatiguePenalty: hidden ? 999 : rawFatigue,
    isHidden: hidden,
  );
}

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

/// Preference boost from favorite brands (+15), categories (+10), and deal priorities (+8–12).
double preferenceBoost(Promotion p, UserPrefs? prefs) {
  if (prefs == null) return 0;
  double boost = 0;

  final brand = p.brand.toLowerCase();
  if (prefs.favoriteBrands.any((b) => b.toLowerCase() == brand)) boost += 15;
  final cat = p.category.toLowerCase();
  if (cat.isNotEmpty && prefs.favoriteCategories.any((c) => c.toLowerCase() == cat)) boost += 10;

  final ptype  = p.promotionType.toLowerCase();
  final dtype  = p.discountType.toLowerCase();
  final dscope = p.dealScope.toLowerCase();
  final dp     = prefs.dealPriorities;

  if (dp.contains('free') && (ptype.contains('free') || p.rankBaseScore >= 60)) boost += 12;
  if (dp.contains('bogo') && (ptype.contains('bogo') || dtype.contains('bogo'))) boost += 12;
  if (dp.contains('nearby') && p.distanceKm != null) boost += 10;
  if (dp.contains('online') && (dscope.contains('online') || p.distanceKm == null)) boost += 8;
  if (dp.contains('rewards') && p.requiresMembership) boost += 8;
  if (dp.contains('discount')) {
    final val = p.discountValue ?? '';
    final pct = RegExp(r'(\d+)').firstMatch(val);
    if (pct != null && (int.tryParse(pct.group(1)!) ?? 0) >= 30) boost += 10;
  }

  return boost;
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

/// Full personalized score: base rank + affinity + preference boost - fatigue penalty.
double personalizedScore(
  Promotion p,
  InteractionService svc, {
  double? distanceKm,
  bool isMember = false,
  UserPrefs? prefs,
}) {
  final penalty = fatiguePenalty(p.id, svc);
  if (penalty >= _kHide) return -_kHide;
  return p.rankScore(distanceKm: distanceKm, isMember: isMember)
      + affinityBoost(p, svc)
      + preferenceBoost(p, prefs)
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
  UserPrefs? prefs,
  int limit = 10,
  int maxPerBrand = 2,
}) {
  final scored = <(Promotion, double)>[];
  for (final p in candidates) {
    final score = personalizedScore(
      p, svc,
      distanceKm: getDistance?.call(p),
      isMember: getIsMember?.call(p) ?? false,
      prefs: prefs,
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
