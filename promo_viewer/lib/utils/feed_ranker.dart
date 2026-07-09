import '../models/promotion.dart';
import '../models/user_prefs.dart';
import '../services/interaction_service.dart';
import '../services/saved_deals_service.dart';

const _kHide = 999.0;

// Beta: quality drives ranking, personalization reorders the top.
// Lowered from 40 → 35 so the feed feels deal-quality-first for new users
// who have little interaction history.
const double kPersonalizationBoostCap = 35.0;

// ── Category quality floors (beta) ────────────────────────────────────────────
// Raised fashion/beauty 60 → 65. Food/coffee/tech/home/travel unchanged.
const _kCategoryFloors = <String, double>{
  'fashion':          65.0,
  'beauty':           65.0,
  'food':             70.0,
  'coffee':           70.0,
  'tech':             75.0,
  'home_goods':       75.0,
  'home_improvement': 75.0,
  'travel':           80.0,
};

bool _isFreeOrBogo(Promotion p) {
  final d = p.discountType.toLowerCase();
  return d == 'free_item' || d.contains('bogo');
}

/// True when a promotion is a loyalty/rewards-program deal rather than an
/// immediate discount, coupon, or sale.
bool isRewardProgram(Promotion p) =>
    p.promotionType == 'reward' || p.promotionType == 'membership_benefit';

/// Clear and concrete value without requiring program knowledge:
/// free items ("Free Drink", "Free Fries") or dollar-denominated rewards
/// ("$5 reward", "Earn $10 back").
bool _hasImmediateValue(Promotion p) {
  if (p.discountType == 'free_item') return true;
  return RegExp(r'\$\d').hasMatch(p.title);
}

/// Returns true when a reward-program deal is allowed in the For You feed.
/// Evaluated inside [selectTopDeals] so all of the brand's deals are available
/// for the "prior interaction" criterion.
bool _rewardPassesForYou(
  Promotion p,
  InteractionService svc,
  Set<String> favBrands,
  UserPrefs? prefs,
  List<Promotion> allBrandDeals,
) {
  // 1. Clear immediate value — free item or specific dollar amount
  if (_hasImmediateValue(p)) return true;
  // 2. Favorite brand — explicit user preference
  if (favBrands.contains(p.brand.toLowerCase())) return true;
  // 3. Prior interaction with this brand or any of its deals
  if (svc.isBrandRecentlySearched(p.brand)) return true;
  for (final d in allBrandDeals) {
    if (svc.clickCount(d.id) > 0 ||
        svc.hasFastRedeemed(d.id) ||
        SavedDealsService().get(d.id) != null) return true;
  }
  // 4. Birthday reward during the user's birthday month
  if (p.birthdayRelated && _isBirthdayMonth(prefs)) {
    return true;
  }
  // 5. Very high quality score — strong standalone offer
  if (p.globalQualityScore >= 80) {
    return true;
  }
  return false;
}

/// True when a deal has an explicit ≥ 30% percentage discount.
/// These always belong in For You at a lower quality bar.
bool _isStrongDiscount(Promotion p) {
  if (p.discountType.toLowerCase() != 'percentage_off') return false;
  final match = RegExp(r'(\d+)').firstMatch(p.discountValue ?? '');
  return match != null && (int.tryParse(match.group(1)!) ?? 0) >= 30;
}

/// Beta gate: a deal must pass before personalization boosts apply.
/// Category preference reorders good deals — it does not rescue weak ones.
bool isFeedWorthy(Promotion p, {Set<String> favBrands = const {}}) {
  // Free items / BOGO — always compelling; very permissive bar
  if (_isFreeOrBogo(p) && p.globalQualityScore >= 45) return true;
  // Explicit ≥ 30% off — strong discount, slightly lower bar than default
  if (_isStrongDiscount(p) && p.globalQualityScore >= 55) return true;
  // Favourite-brand deals — user has stated explicit intent; lower floor
  if (favBrands.contains(p.brand.toLowerCase()) && p.globalQualityScore >= 50) return true;
  // Category-specific floor (default raised 60 → 65 for beta quality bar)
  final floor = _kCategoryFloors[p.category.toLowerCase()] ?? 65.0;
  if (p.globalQualityScore < floor) return false;
  // Points-only deals need a higher score unless from a favourite brand
  if (p.discountType.toLowerCase() == 'points' &&
      p.globalQualityScore < 75 &&
      !favBrands.contains(p.brand.toLowerCase())) {
    return false;
  }
  return true;
}

/// Penalty for uninspiring deal types so they rank low in For You.
/// These deals still appear in Search — this only affects feed position.
/// Beta: values raised to push weak deals further down relative to strong discounts.
double _weakDealPenalty(Promotion p) {
  double penalty = 0;
  final dtype = p.discountType.toLowerCase();
  final ptype = p.promotionType.toLowerCase();
  final title = p.title.toLowerCase();
  if (dtype == 'free_shipping')                                   penalty += 25;
  if (dtype == 'points')                                          penalty += 20;
  if (ptype == 'app_offer' && dtype == 'unknown')                 penalty += 22;
  if (title.contains('select style'))                             penalty += 15;
  if (title.contains('newsletter') || title.contains('sign up')) penalty += 25;
  if (title.contains('limited time') && dtype == 'unknown')      penalty += 15;
  return penalty;
}

/// Fix 5: Per-category click-through rate from seen/click history.
/// Returns category → multiplier (0.5–1.0). Low engagement dampens category boost.
Map<String, double> _categoryEngagement(
    List<Promotion> candidates, InteractionService svc) {
  final catSeen    = <String, int>{};
  final catClicked = <String, int>{};
  for (final p in candidates) {
    final cat  = p.category.toLowerCase();
    if (cat.isEmpty) continue;
    final seen = svc.seenCount(p.id);
    if (seen == 0) continue;
    catSeen[cat]    = (catSeen[cat]    ?? 0) + seen;
    catClicked[cat] = (catClicked[cat] ?? 0) + (svc.clickCount(p.id) > 0 ? 1 : 0);
  }
  final result = <String, double>{};
  catSeen.forEach((cat, seen) {
    if (seen < 5) return; // not enough data to dampen yet
    final ctr = (catClicked[cat] ?? 0) / seen;
    // ctr 0% → 0.5×, ctr ≥ 20% → 1.0× (full boost)
    result[cat] = (ctr * 5.0).clamp(0.5, 1.0);
  });
  return result;
}

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
      : rankBase + distanceBonus + dayBonus + membershipBonus
        + (affinityBoost + preferenceBoost).clamp(0, kPersonalizationBoostCap)
        - fatiguePenalty;
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
    rankBase: p.globalQualityScore,
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
///
/// Penalties are intentionally mild for low seen counts: external datasets
/// (RetailRocket, Taobao) show repeated views without action are still a
/// positive purchase-intent signal. Only suppress after 5+ ignored impressions.
double fatiguePenalty(String id, InteractionService svc) {
  if (svc.isDealSkipped(id)) return _kHide;
  final seen = svc.seenCount(id);
  if (seen == 0) return 0;
  // Positive interactions cancel fatigue
  if (svc.clickCount(id) > 0 || svc.hasFastRedeemed(id)) return 0;
  switch (seen) {
    case 1:  return 0;
    case 2:  return 0;
    case 3:  return 3;
    case 4:  return 8;
    default:
      // 5+ no-interaction views: hide for 7 days from last seen
      final last = svc.lastSeenAt(id);
      if (last != null && DateTime.now().difference(last).inDays < 7) return _kHide;
      return 8; // after cooldown: moderate penalty, back in rotation
  }
}

bool _isBirthdayMonth(UserPrefs? prefs) {
  final bm = prefs?.birthdayMonth;
  return bm != null && bm == DateTime.now().month;
}

/// Preference boost from favorite brands (+25), categories (+22), and deal priorities.
/// Values calibrated from E1 (Ponpare) and E3 (Taobao) experiment coefficients.
/// During the user's birthday month, birthday_related deals get a +60 bonus.
double preferenceBoost(Promotion p, UserPrefs? prefs) {
  if (prefs == null) return 0;
  double boost = 0;

  if (p.birthdayRelated && _isBirthdayMonth(prefs)) boost += 60;

  final brand = p.brand.toLowerCase();
  if (prefs.favoriteBrands.any((b) => b.toLowerCase() == brand)) { boost += 35; }  // E1: explicit pref is strongest signal

  final cat = p.category.toLowerCase();
  if (cat.isNotEmpty && prefs.favoriteCategories.any((c) => c.toLowerCase() == cat)) boost += 22;  // E1+E3: raised from 20

  final ptype  = p.promotionType.toLowerCase();
  final dtype  = p.discountType.toLowerCase();
  final dscope = p.dealScope.toLowerCase();
  final dp     = prefs.dealPriorities;

  if (dp.contains('free') && (ptype.contains('free') || p.globalQualityScore >= 60)) boost += 12;
  if (dp.contains('bogo') && (ptype.contains('bogo') || dtype.contains('bogo'))) boost += 12;
  if (dp.contains('nearby') && p.distanceKm != null) boost += 4;   // E1: area_match was weak (+0.2); reduced from 10
  if (dp.contains('online') && (dscope.contains('online') || p.distanceKm == null)) boost += 8;
  if (dp.contains('rewards') && p.requiresMembership) boost += 8;
  if (dp.contains('discount')) {
    final val = p.discountValue ?? '';
    final pct = RegExp(r'(\d+)').firstMatch(val);
    if (pct != null && (int.tryParse(pct.group(1)!) ?? 0) >= 30) boost += 4;  // E1: PRICE_RATE was weak; reduced from 10
  }

  return boost;
}

/// Affinity boost from positive signals: saved, fast-redeemed, clicked, brand searched.
/// recent_search_boost raised 15→18: E4 (Yoochoose) repeated_click_same_item was the
/// strongest session signal.
double affinityBoost(Promotion p, InteractionService svc) {
  double boost = 0;
  if (SavedDealsService().get(p.id) != null) boost += 30;
  if (svc.hasFastRedeemed(p.id)) boost += 20;
  if (svc.clickCount(p.id) > 0) boost += 8;
  if (svc.isBrandRecentlySearched(p.brand)) boost += 18;  // E4: raised from 15
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
  final personalization = (affinityBoost(p, svc) + preferenceBoost(p, prefs))
      .clamp(0.0, kPersonalizationBoostCap);
  return p.rankScore(distanceKm: distanceKm, isMember: isMember)
      + personalization
      - penalty;
}

// ── Two-level ranker ──────────────────────────────────────────────────────────
//
// Level 1 (brandLevelScore): which brand card appears first.
//   Uses brand-wide signals only — favourite brand/category, recent search,
//   deal count, and best quality as a tiebreaker.
//
// Level 2 (dealQualityScore): which deal appears first inside a brand card.
//   Uses deal-specific signals — pipeline quality, distance, day-of-week,
//   membership, deal-type priorities, birthday, and per-deal interaction
//   history. Brand/category boost is intentionally excluded here; applying
//   it at both levels inflates every deal from a favourite brand equally
//   and prevents the best individual deal from rising to the top.

/// Infers how strongly the user implicitly prefers each category by counting
/// how many of their favorite brands belong to it.
///
/// Example: favBrands = [Coach, Zara, Nike, Kate Spade, Starbucks]
///   fashion → 4/5 = 0.80
///   food    → 1/5 = 0.20
///
/// Returns category → weight (0.0–1.0). Brands not found in [allPromos] are
/// skipped, so the denominator is favBrands.length (not matched count) to
/// preserve the relative intensity of the signal.
Map<String, double> inferCategoryWeights(
  List<String> favoriteBrands,
  List<Promotion> allPromos,
) {
  if (favoriteBrands.isEmpty) return {};

  // Build brand → category from promotions (first occurrence wins)
  final brandCategory = <String, String>{};
  for (final p in allPromos) {
    if (p.category.isNotEmpty) brandCategory.putIfAbsent(p.brand, () => p.category);
  }

  final counts = <String, int>{};
  for (final brand in favoriteBrands) {
    final cat = brandCategory[brand];
    if (cat != null && cat.isNotEmpty) {
      counts[cat] = (counts[cat] ?? 0) + 1;
    }
  }
  if (counts.isEmpty) return {};

  final total = favoriteBrands.length;
  return {for (final e in counts.entries) e.key: e.value / total};
}

/// Level 1 — brand score: determines brand card order.
///
/// Signal hierarchy (highest → lowest):
///   behavioral affinity     (0–35)  — clicks/saves/redeems on this brand's deals
///   favorite brand          (+30)   — onboarding choice; slightly below behavioral max
///   recent search           (+22)   — session-level intent signal
///   explicit category       (+20)   — broad onboarding preference
///   inferred category       (0–+10) — proportional to how many fav brands share category
///   deal count bonus        (0–+6)  — tiebreaker: more live deals = more value
///   best quality            (×0.3)  — final tiebreaker
double brandLevelScore(
  String brand,
  String category,
  List<Promotion> deals,
  InteractionService svc, {
  UserPrefs? prefs,
  Map<String, double>? inferredCategoryWeights,
  Map<String, double>? categoryEngagement,
}) {
  double score = 0;

  // Behavioral brand affinity — derived from per-deal interactions for this brand.
  // Tops out at +35 so demonstrated behavior beats a stated onboarding preference.
  int brandClicks = 0, brandSaves = 0, brandRedeems = 0;
  for (final p in deals) {
    if (svc.clickCount(p.id) > 0)             brandClicks++;
    if (svc.hasFastRedeemed(p.id))            brandRedeems++;
    if (SavedDealsService().get(p.id) != null) brandSaves++;
  }
  score += ((brandSaves.clamp(0, 3) * 10.0)
          + (brandRedeems.clamp(0, 2) * 8.0)
          + (brandClicks.clamp(0, 5) * 3.0))
      .clamp(0.0, 35.0);

  // Onboarding preferences (slightly weaker than max behavioral affinity)
  if (prefs != null) {
    final bl = brand.toLowerCase();
    if (prefs.favoriteBrands.any((b) => b.toLowerCase() == bl)) { score += 30; }

    final cl = category.toLowerCase();
    if (cl.isNotEmpty) {
      // Fix 5: dampen category boost when user consistently ignores this category
      final engagement = categoryEngagement?[cl] ?? 1.0;

      // Flat boost for explicit category selection
      if (prefs.favoriteCategories.any((c) => c.toLowerCase() == cl)) {
        score += 20 * engagement;
      }

      // Inferred boost from brand concentration in this category (max +10).
      final inferredWeight = inferredCategoryWeights?[cl] ?? 0.0;
      if (inferredWeight > 0) score += inferredWeight * 10.0 * engagement;
    }
  }

  // Session recency: user searched for this brand this session
  if (svc.isBrandRecentlySearched(brand)) score += 22;

  // Deal count: more live deals = more browsing value (max +6, pure tiebreaker)
  score += deals.length.clamp(0, 3) * 2.0;

  // Best deal quality as final tiebreaker
  final bestQ = deals
      .map((d) => d.globalQualityScore)
      .reduce((a, b) => a > b ? a : b);
  score += bestQ * 0.3;

  return score;
}

/// Level 2 — deal score: determines deal order within a brand card.
/// Returns -_kHide for fatigue-suppressed deals (caller should exclude them).
double dealQualityScore(
  Promotion p,
  InteractionService svc, {
  double? distanceKm,
  bool isMember = false,
  UserPrefs? prefs,
}) {
  final penalty = fatiguePenalty(p.id, svc);
  if (penalty >= _kHide) return -_kHide;

  double score = p.globalQualityScore;
  score -= _weakDealPenalty(p); // Fix 2: downrank uninspiring deal types

  // Distance bonus
  if (distanceKm != null) {
    final miles = distanceKm * 0.621371;
    score += miles <= 0.5 ? 30
           : miles <= 1.0 ? 25
           : miles <= 2.0 ? 18
           : miles <= 5.0 ? 8 : 2;
  }

  // Day-of-week
  if (p.validDays.isNotEmpty) {
    const dayNames = ['monday','tuesday','wednesday','thursday','friday','saturday','sunday'];
    const dayShort = ['mon','tue','wed','thu','fri','sat','sun'];
    final todayIdx = DateTime.now().weekday - 1;
    final norm = p.validDays.map((d) => d.toLowerCase()).toList();
    score += norm.any((d) => d == dayNames[todayIdx] || d == dayShort[todayIdx]) ? 5 : -20;
  }

  // Membership
  if (isMember) {
    score += 25;
  } else if (!p.requiresMembership) {
    score += 8;
  } else {
    final cost = (p.membershipCost ?? '').toLowerCase();
    score += cost.contains('free') ? -2 : cost.contains('paid') ? -15 : -5;
  }

  // Deal-type priorities
  if (prefs != null) {
    final dp     = prefs.dealPriorities;
    final ptype  = p.promotionType.toLowerCase();
    final dtype  = p.discountType.toLowerCase();
    final dscope = p.dealScope.toLowerCase();
    if (dp.contains('free') && (ptype.contains('free') || p.globalQualityScore >= 60)) score += 12;
    if (dp.contains('bogo') && (ptype.contains('bogo') || dtype.contains('bogo')))     score += 12;
    if (dp.contains('nearby') && p.distanceKm != null)                                 score += 4;
    if (dp.contains('online') && (dscope.contains('online') || p.distanceKm == null))  score += 8;
    if (dp.contains('rewards') && p.requiresMembership)                                score += 8;
    if (dp.contains('discount')) {
      final pct = RegExp(r'(\d+)').firstMatch(p.discountValue ?? '');
      if (pct != null && (int.tryParse(pct.group(1)!) ?? 0) >= 30) score += 4;
    }
  }

  // Birthday boost (deal-specific)
  if (p.birthdayRelated && _isBirthdayMonth(prefs)) score += 60;

  // Per-deal interaction signals (lower weights — brand-level signal is at Level 1)
  if (SavedDealsService().get(p.id) != null) score += 15;
  if (svc.hasFastRedeemed(p.id))             score += 10;
  if (svc.clickCount(p.id) > 0)              score += 5;

  score -= penalty;
  return score;
}

/// Two-level selectTopDeals for the For You feed (flat list, no brand grouping).
///
/// Level 1: brands are sorted by brandLevelScore (fav brand/cat, recent search,
/// deal count). Level 2: up to [maxPerBrand] deals per brand are picked by
/// dealQualityScore (pipeline quality, deal-type priorities, birthday, affinity).
List<Promotion> selectTopDeals(
  List<Promotion> candidates,
  InteractionService svc, {
  double? Function(Promotion)? getDistance,
  bool Function(Promotion)? getIsMember,
  UserPrefs? prefs,
  int limit = 10,
  int maxPerBrand = 2,
}) {
  final isBday  = _isBirthdayMonth(prefs);
  final hasBday = prefs?.birthdayMonth != null;

  // Fix 1+3: build favourite-brand set once for feed-worthy checks
  final favBrands = {
    for (final b in prefs?.favoriteBrands ?? <String>[]) b.toLowerCase()
  };

  // Group active, non-suppressed deals by brand
  final brandMap = <String, List<Promotion>>{};
  for (final p in candidates) {
    if (p.birthdayRelated && hasBday && !isBday) continue;
    // Fix 1+3: gate — personalization boosts reorder good deals, not rescue weak ones
    if (!isFeedWorthy(p, favBrands: favBrands)) continue;
    final dScore = dealQualityScore(p, svc,
        distanceKm: getDistance?.call(p),
        isMember: getIsMember?.call(p) ?? false,
        prefs: prefs);
    if (dScore <= -_kHide / 2) continue;
    brandMap.putIfAbsent(p.brand, () => []).add(p);
  }

  // Level 1: sort brands by brand-level score
  final inferredWeights = inferCategoryWeights(prefs?.favoriteBrands ?? [], candidates);
  final catEngagement   = _categoryEngagement(candidates, svc); // Fix 5
  final brands = brandMap.keys.toList();
  brands.sort((a, b) {
    final sa = brandLevelScore(a, brandMap[a]!.first.category, brandMap[a]!, svc,
        prefs: prefs, inferredCategoryWeights: inferredWeights,
        categoryEngagement: catEngagement);
    final sb = brandLevelScore(b, brandMap[b]!.first.category, brandMap[b]!, svc,
        prefs: prefs, inferredCategoryWeights: inferredWeights,
        categoryEngagement: catEngagement);
    return sb.compareTo(sa);
  });

  // Level 2: from each brand (in order), take best deals by deal quality.
  // Reward-program deals are suppressed in For You unless they meet one of:
  //   1. clear immediate value (free item or $-amount reward)
  //   2. favorite brand
  //   3. prior interaction with this brand/its deals
  //   4. birthday reward during birthday month
  //   5. very high quality score (≥ 80)
  // When both regular and reward deals exist, the reward deal is always hidden.
  final result = <Promotion>[];
  for (final brand in brands) {
    if (result.length >= limit) break;
    final deals = brandMap[brand]!;

    final regularDeals = deals.where((d) => !isRewardProgram(d)).toList();
    final eligible = regularDeals.isNotEmpty
        ? regularDeals
        : deals.where((d) => _rewardPassesForYou(
              d, svc, favBrands, prefs, deals)).toList();
    if (eligible.isEmpty) continue;

    eligible.sort((a, b) {
      final sa = dealQualityScore(a, svc, distanceKm: getDistance?.call(a),
          isMember: getIsMember?.call(a) ?? false, prefs: prefs);
      final sb = dealQualityScore(b, svc, distanceKm: getDistance?.call(b),
          isMember: getIsMember?.call(b) ?? false, prefs: prefs);
      return sb.compareTo(sa);
    });
    int taken = 0;
    for (final p in eligible) {
      if (taken >= maxPerBrand || result.length >= limit) break;
      result.add(p);
      taken++;
    }
  }

  return result;
}
