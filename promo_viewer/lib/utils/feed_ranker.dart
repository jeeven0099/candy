import '../models/promotion.dart';
import '../models/user_prefs.dart';
import '../services/interaction_service.dart';
import '../services/saved_deals_service.dart';

const _kHide = 999.0;

// Personalization reorders the top of the feed; it cannot rescue weak deals.
const double kPersonalizationBoostCap = 35.0;

// ── Category quality floors ───────────────────────────────────────────────────
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

// Pet brands are often tagged as 'food' by the scraper (pet food/treats).
// They should not appear in the general feed unless the user has explicitly
// added them as a favorite brand.
const _kPetBrands = {
  'barkbox', 'the farmers dog', "the farmer's dog", 'farmers dog',
  "farmer's dog", 'chewy', 'petco', 'petsmart', 'ollie', 'nom nom',
  '1800petmeds', 'hill\'s pet nutrition', 'hills pet nutrition', 'petsafe',
  'blue buffalo', 'purina', 'royal canin', 'iams', 'science diet',
};

bool _isFreeOrBogo(Promotion p) {
  final d = p.discountType.toLowerCase();
  return d == 'free_item' || d.contains('bogo');
}

bool isRewardProgram(Promotion p) =>
    p.promotionType == 'reward' || p.promotionType == 'membership_benefit';

bool _hasImmediateValue(Promotion p) {
  if (p.discountType == 'free_item') return true;
  return RegExp(r'\$\d').hasMatch(p.title);
}

bool _rewardPassesForYou(
  Promotion p,
  InteractionService svc,
  Set<String> favBrands,
  UserPrefs? prefs,
  List<Promotion> allBrandDeals,
) {
  if (_hasImmediateValue(p)) return true;
  if (favBrands.contains(p.brand.toLowerCase())) return true;
  if (svc.isBrandRecentlySearched(p.brand)) return true;
  for (final d in allBrandDeals) {
    if (svc.clickCount(d.id) > 0 ||
        svc.hasFastRedeemed(d.id) ||
        SavedDealsService().get(d.id) != null) return true;
  }
  if (p.birthdayRelated && _isBirthdayMonth(prefs)) { return true; }
  if (p.globalQualityScore >= 80) { return true; }
  return false;
}

bool _isStrongDiscount(Promotion p) {
  if (p.discountType.toLowerCase() != 'percentage_off') return false;
  final match = RegExp(r'(\d+)').firstMatch(p.discountValue ?? '');
  return match != null && (int.tryParse(match.group(1)!) ?? 0) >= 30;
}

/// Gate applied before any personalization boost. Category preference reorders
/// good deals — it does not rescue weak ones.
bool isFeedWorthy(Promotion p, {Set<String> favBrands = const {}}) {
  // Pet brands are scraped as 'food' but are irrelevant to most users.
  // Exclude unless the user has explicitly favorited the brand.
  if (_kPetBrands.contains(p.brand.toLowerCase()) &&
      !favBrands.contains(p.brand.toLowerCase())) {
    return false;
  }
  if (_isFreeOrBogo(p) && p.globalQualityScore >= 45) return true;
  if (_isStrongDiscount(p) && p.globalQualityScore >= 55) return true;
  if (favBrands.contains(p.brand.toLowerCase()) && p.globalQualityScore >= 50) return true;
  final floor = _kCategoryFloors[p.category.toLowerCase()] ?? 65.0;
  if (p.globalQualityScore < floor) return false;
  if (p.discountType.toLowerCase() == 'points' &&
      p.globalQualityScore < 75 &&
      !favBrands.contains(p.brand.toLowerCase())) {
    return false;
  }
  return true;
}

/// Feed-position penalty for deal types that are low-intent or require friction
/// beyond what the pipeline already captured. The pipeline now correctly scores
/// free_shipping and points by economic value, so those no longer need a blanket
/// penalty here — their low pipeline scores naturally gate them out.
double _weakDealPenalty(Promotion p) {
  double penalty = 0;
  final ptype = p.promotionType.toLowerCase();
  final dtype = p.discountType.toLowerCase();
  final title = p.title.toLowerCase();
  if (ptype == 'app_offer' && dtype == 'unknown')                 penalty += 22;
  if (title.contains('select style'))                             penalty += 15;
  if (title.contains('newsletter') || title.contains('sign up')) penalty += 25;
  if (title.contains('limited time') && dtype == 'unknown')      penalty += 15;
  return penalty;
}

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
    if (seen < 5) return;
    final ctr = (catClicked[cat] ?? 0) / seen;
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
  double distBonus = 0;
  if (distanceKm != null) {
    final miles = distanceKm * 0.621371;
    if (miles <= 0.5)      { distBonus = 30; }
    else if (miles <= 1.0) { distBonus = 25; }
    else if (miles <= 2.0) { distBonus = 18; }
    else if (miles <= 5.0) { distBonus =  8; }
    else                   { distBonus =  2; }
  }

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

/// Fatigue penalty based purely on seenCount.
/// recordClick() bumps seenCount directly, so opening a deal detail
/// page contributes to fatigue without needing a separate clicks branch here.
double fatiguePenalty(String id, InteractionService svc) {
  if (svc.isDealSkipped(id)) return _kHide;
  if (svc.hasFastRedeemed(id)) return 8.0;

  final seen = svc.seenCount(id);
  switch (seen) {
    case 0:
    case 1:  return 0;
    case 2:  return 3;
    case 3:  return 8;
    case 4:  return 15;
    default:
      final last = svc.lastSeenAt(id);
      if (last != null && DateTime.now().difference(last).inDays < 7) {
        return _kHide;
      }
      return 8;
  }
}

bool _isBirthdayMonth(UserPrefs? prefs) {
  final bm = prefs?.birthdayMonth;
  return bm != null && bm == DateTime.now().month;
}

/// Preference boost from onboarding choices. Birthday deals get a small
/// contextual bonus (+10) — the feed gate already ensures they only appear
/// during the user's birthday month, so the boost just lifts them slightly
/// within that window rather than overriding all other ranking signals.
double preferenceBoost(Promotion p, UserPrefs? prefs) {
  if (prefs == null) return 0;
  double boost = 0;

  if (p.birthdayRelated && _isBirthdayMonth(prefs)) boost += 10;

  final brand = p.brand.toLowerCase();
  if (prefs.favoriteBrands.any((b) => b.toLowerCase() == brand)) boost += 35;

  final cat = p.category.toLowerCase();
  if (cat.isNotEmpty && prefs.favoriteCategories.any((c) => c.toLowerCase() == cat)) boost += 22;

  final ptype  = p.promotionType.toLowerCase();
  final dtype  = p.discountType.toLowerCase();
  final dscope = p.dealScope.toLowerCase();
  final dp     = prefs.dealPriorities;

  if (dp.contains('free') && (ptype.contains('free') || p.globalQualityScore >= 60)) boost += 12;
  if (dp.contains('bogo') && (ptype.contains('bogo') || dtype.contains('bogo'))) boost += 12;
  if (dp.contains('nearby') && p.distanceKm != null) boost += 4;
  if (dp.contains('online') && (dscope.contains('online') || p.distanceKm == null)) boost += 8;
  if (dp.contains('rewards') && p.requiresMembership) boost += 8;
  if (dp.contains('discount')) {
    final val = p.discountValue ?? '';
    final pct = RegExp(r'(\d+)').firstMatch(val);
    if (pct != null && (int.tryParse(pct.group(1)!) ?? 0) >= 30) boost += 4;
  }

  return boost;
}

/// Affinity boost from interaction history. Fast-redeemed deals no longer get
/// a deal-level boost since you've already used them — brand-level affinity
/// from brandLevelScore already captures the "I liked this brand" signal.
double affinityBoost(Promotion p, InteractionService svc) {
  double boost = 0;
  if (SavedDealsService().get(p.id) != null) boost += 30;
  if (svc.clickCount(p.id) > 0)              boost += 8;
  if (svc.isBrandRecentlySearched(p.brand))  boost += 18;
  return boost;
}

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

Map<String, double> inferCategoryWeights(
  List<String> favoriteBrands,
  List<Promotion> allPromos,
) {
  if (favoriteBrands.isEmpty) return {};
  final brandCategory = <String, String>{};
  for (final p in allPromos) {
    if (p.category.isNotEmpty) brandCategory.putIfAbsent(p.brand, () => p.category);
  }
  final counts = <String, int>{};
  for (final brand in favoriteBrands) {
    final cat = brandCategory[brand];
    if (cat != null && cat.isNotEmpty) counts[cat] = (counts[cat] ?? 0) + 1;
  }
  if (counts.isEmpty) return {};
  final total = favoriteBrands.length;
  return {for (final e in counts.entries) e.key: e.value / total};
}

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

  if (prefs != null) {
    final bl = brand.toLowerCase();
    if (prefs.favoriteBrands.any((b) => b.toLowerCase() == bl)) score += 30;

    final cl = category.toLowerCase();
    if (cl.isNotEmpty) {
      final engagement = categoryEngagement?[cl] ?? 1.0;
      if (prefs.favoriteCategories.any((c) => c.toLowerCase() == cl)) {
        score += 20 * engagement;
      }
      final inferredWeight = inferredCategoryWeights?[cl] ?? 0.0;
      if (inferredWeight > 0) score += inferredWeight * 10.0 * engagement;
    }
  }

  if (svc.isBrandRecentlySearched(brand)) score += 22;
  score += deals.length.clamp(0, 3) * 2.0;

  final bestQ = deals
      .map((d) => d.globalQualityScore)
      .reduce((a, b) => a > b ? a : b);
  score += bestQ * 0.3;

  return score;
}

/// Level 2 — deal score within a brand card.
/// Excludes the brand/category preference boost (applied at Level 1).
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
  score -= _weakDealPenalty(p);

  if (distanceKm != null) {
    final miles = distanceKm * 0.621371;
    score += miles <= 0.5 ? 30
           : miles <= 1.0 ? 25
           : miles <= 2.0 ? 18
           : miles <= 5.0 ? 8 : 2;
  }

  if (p.validDays.isNotEmpty) {
    const dayNames = ['monday','tuesday','wednesday','thursday','friday','saturday','sunday'];
    const dayShort = ['mon','tue','wed','thu','fri','sat','sun'];
    final todayIdx = DateTime.now().weekday - 1;
    final norm = p.validDays.map((d) => d.toLowerCase()).toList();
    score += norm.any((d) => d == dayNames[todayIdx] || d == dayShort[todayIdx]) ? 5 : -20;
  }

  if (isMember) {
    score += 25;
  } else if (!p.requiresMembership) {
    score += 8;
  } else {
    final cost = (p.membershipCost ?? '').toLowerCase();
    score += cost.contains('free') ? -2 : cost.contains('paid') ? -15 : -5;
  }

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

  // Birthday: small contextual lift (deal passes gate only during birthday month)
  if (p.birthdayRelated && _isBirthdayMonth(prefs)) score += 10;

  // Saved = clear intent to use (not yet redeemed)
  if (SavedDealsService().get(p.id) != null) score += 15;
  // Clicked = interest signal; fast-redeemed is captured at brand level only
  if (svc.clickCount(p.id) > 0) score += 5;

  score -= penalty;
  return score;
}

// ── Surface-specific ranking ──────────────────────────────────────────────────

/// The surface the user is viewing. Each surface applies different ranking
/// emphasis. Brand-first grouping applies only to [forYou].
enum RankingMode {
  forYou,       // Two-level brand-aware + personalized
  search,       // Global quality, max 2 deals per brand for diversity
  nearby,       // Distance-first, quality floor 40
  expiringSoon, // Urgency × quality — weak deals expiring soon don't dominate
  bestValue,    // Economic value first (from pipeline economic_value_score)
}

bool _isFatigued(String id, InteractionService svc) =>
    fatiguePenalty(id, svc) >= _kHide;

/// Rank [candidates] for the given surface. For [RankingMode.forYou] this
/// delegates to [selectTopDeals]. All other surfaces bypass brand grouping
/// and [isFeedWorthy] in favour of surface-specific quality floors.
List<Promotion> rankForSurface(
  List<Promotion> candidates,
  RankingMode mode,
  InteractionService svc, {
  double? Function(Promotion)? getDistance,
  bool Function(Promotion)? getIsMember,
  UserPrefs? prefs,
  int limit = 20,
}) {
  switch (mode) {
    case RankingMode.forYou:
      return selectTopDeals(candidates, svc,
          getDistance: getDistance,
          getIsMember: getIsMember,
          prefs: prefs,
          limit: limit);

    case RankingMode.search:
      // Rank globally by deal quality; enforce max 2 deals per brand.
      final scored = candidates
          .where((p) => !_isFatigued(p.id, svc))
          .map((p) => (
                p: p,
                score: dealQualityScore(p, svc,
                    distanceKm: getDistance?.call(p),
                    isMember: getIsMember?.call(p) ?? false,
                    prefs: prefs),
              ))
          .where((e) => e.score > -_kHide / 2)
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));
      final perBrand = <String, int>{};
      final searchResult = <Promotion>[];
      for (final e in scored) {
        if (searchResult.length >= limit) break;
        final count = perBrand[e.p.brand] ?? 0;
        if (count >= 2) continue;
        perBrand[e.p.brand] = count + 1;
        searchResult.add(e.p);
      }
      return searchResult;

    case RankingMode.nearby:
      // Distance-first within a reasonable radius; quality floor 40.
      const qualityFloor = 40.0;
      const radiusKm     = 8.0;
      final nearby = candidates
          .where((p) => p.globalQualityScore >= qualityFloor)
          .where((p) => !_isFatigued(p.id, svc))
          .where((p) {
            final d = getDistance?.call(p);
            return d != null && d <= radiusKm;
          })
          .toList()
        ..sort((a, b) {
            final da = getDistance?.call(a) ?? 999.0;
            final db = getDistance?.call(b) ?? 999.0;
            return da.compareTo(db);
          });
      return nearby.take(limit).toList();

    case RankingMode.expiringSoon:
      // Urgency × quality: a bad deal expiring today remains bad.
      // Uses pipeline-computed expiration_urgency_score so the interaction
      // matches the pipeline's own urgency definition (0–5 pts, expires ≤3 days).
      const qualityFloor = 45.0;
      final urgent = candidates
          .where((p) => p.globalQualityScore >= qualityFloor)
          .where((p) => p.expirationUrgencyScore > 0)
          .where((p) => !_isFatigued(p.id, svc))
          .toList()
        ..sort((a, b) {
            // Primary: urgency score desc; secondary: quality desc.
            final cmp = b.expirationUrgencyScore.compareTo(a.expirationUrgencyScore);
            if (cmp != 0) return cmp;
            return b.globalQualityScore.compareTo(a.globalQualityScore);
          });
      return urgent.take(limit).toList();

    case RankingMode.bestValue:
      // Pure economic value from the pipeline — removes framing/urgency/freshness bias.
      return (candidates.where((p) => !_isFatigued(p.id, svc)).toList()
            ..sort((a, b) => b.economicValueScore.compareTo(a.economicValueScore)))
          .take(limit)
          .toList();
  }
}

/// Two-level For You feed (flat list, no brand grouping visible to caller).
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

  final favBrands = {
    for (final b in prefs?.favoriteBrands ?? <String>[]) b.toLowerCase()
  };

  final brandMap = <String, List<Promotion>>{};
  for (final p in candidates) {
    if (p.birthdayRelated && hasBday && !isBday) continue;
    if (!isFeedWorthy(p, favBrands: favBrands)) continue;
    final dScore = dealQualityScore(p, svc,
        distanceKm: getDistance?.call(p),
        isMember: getIsMember?.call(p) ?? false,
        prefs: prefs);
    if (dScore <= -_kHide / 2) continue;
    brandMap.putIfAbsent(p.brand, () => []).add(p);
  }

  final inferredWeights = inferCategoryWeights(prefs?.favoriteBrands ?? [], candidates);
  final catEngagement   = _categoryEngagement(candidates, svc);
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
