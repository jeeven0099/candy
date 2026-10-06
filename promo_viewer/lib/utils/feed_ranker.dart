import '../models/promotion.dart';
import '../models/user_prefs.dart';
import '../services/interaction_service.dart';
import '../services/saved_deals_service.dart';
import 'ranking_contract.dart';

const _kHide = 999.0;

const kPetBrandNames = {
  'barkbox',
  'the farmers dog',
  "the farmer's dog",
  'farmers dog',
  "farmer's dog",
  'chewy',
  'petco',
  'petsmart',
  'ollie',
  'nom nom',
  '1800petmeds',
  'hill\'s pet nutrition',
  'hills pet nutrition',
  'petsafe',
  'blue buffalo',
  'purina',
  'royal canin',
  'iams',
  'science diet',
};

const _nearMeRedemptionMethods = {
  'in_store',
  'in_app',
  'app_reward',
  'show_code',
  'scan_barcode',
  'open_maps',
};

const _blockedNearMeCategories = {
  'finance',
  'travel',
  'streaming',
  'subscription',
  'meal_kit',
  'delivery_only',
};

String _norm(String value) => value.trim().toLowerCase();

bool _isBirthdayMonth(UserPrefs? prefs) {
  final month = prefs?.birthdayMonth;
  return month != null && month == DateTime.now().month;
}

bool _isRewardProgram(Promotion p) =>
    p.promotionType == 'reward' || p.promotionType == 'membership_benefit';

bool _hasImmediateValue(Promotion p) {
  if (p.discountType == 'free_item') return true;
  if (p.economicValueScore >= 35) return true;
  return RegExp(
    r'\$\d|\d+%|\bbogo\b',
    caseSensitive: false,
  ).hasMatch('${p.title} ${p.discountValue ?? ''}');
}

bool _isHiddenByPrefs(Promotion p, UserPrefs? prefs) =>
    prefs?.isHiddenBrand(p.brand) ?? false;

bool _isEmailDerived(Promotion p) =>
    p.source == 'email' || p.visibility == 'private_user_offer';

bool isFeedWorthy(Promotion p, {Set<String> favBrands = const {}}) {
  if (!p.isActive || !p.isValidToday) return false;
  if (p.confidenceScore < RankingContract.minConfidence) return false;

  final brand = _norm(p.brand);
  if (kPetBrandNames.contains(brand) && !favBrands.contains(brand)) {
    return false;
  }

  final emailQualityPass =
      _isEmailDerived(p) &&
      (p.personalRankScore ?? 0) >= RankingContract.emailPersonalRankFloor &&
      p.globalQualityScore >= RankingContract.emailQualityFloor;

  if (p.globalQualityScore < RankingContract.forYouQualityFloor &&
      !emailQualityPass) {
    return false;
  }

  final dtype = _norm(p.discountType);
  if (dtype == 'unknown' &&
      p.globalQualityScore < RankingContract.strongUnknownDiscountFloor) {
    return false;
  }
  if (dtype == 'points' &&
      p.globalQualityScore < RankingContract.exceptionalPointsFloor) {
    return false;
  }
  if (_isRewardProgram(p) &&
      !_hasImmediateValue(p) &&
      !favBrands.contains(brand)) {
    return false;
  }
  return true;
}

double fatiguePenalty(String id, InteractionService svc) {
  if (svc.isDealSkipped(id)) return _kHide;
  if (svc.hasFastRedeemed(id)) return 8.0;
  if (svc.clickCount(id) > 0) return 0.0;

  final seen = svc.seenCount(id);
  if (seen <= 3) return 0.0;
  switch (seen) {
    case 4:
      return 5.0;
    case 5:
      return 15.0;
    case 6:
      return 40.0;
    case 7:
      return 80.0;
    default:
      return _kHide;
  }
}

double _distanceBonus(double? distanceKm) {
  if (distanceKm == null) return 0.0;
  final miles = distanceKm * 0.621371;
  if (miles <= 0.5) return RankingContract.veryNearBonus;
  if (miles <= 1.0) return RankingContract.nearBonus;
  if (miles <= 3.0) return RankingContract.localBonus;
  if (miles <= 5.0) return RankingContract.nearbyBonus;
  return 0.0;
}

double _membershipBonus(Promotion p, bool isMember) {
  if (isMember) return RankingContract.memberBoost;
  if (!p.requiresMembership) return RankingContract.noMembershipBoost;

  final cost = _norm(p.membershipCost ?? '');
  if (cost.contains('free')) return -RankingContract.freeMembershipPenalty;
  if (cost.contains('paid')) return -RankingContract.paidMembershipPenalty;
  return -RankingContract.unknownMembershipPenalty;
}

double preferenceBoost(Promotion p, UserPrefs? prefs) {
  if (prefs == null) return 0.0;
  double boost = 0.0;

  final brand = _norm(p.brand);
  if (prefs.favoriteBrands.any((b) => _norm(b) == brand)) {
    boost += RankingContract.favoriteBrandBoost;
  }

  final category = _norm(p.category);
  if (category.isNotEmpty &&
      prefs.favoriteCategories.any((c) => _norm(c) == category)) {
    boost += RankingContract.favoriteCategoryBoost;
  }

  if (p.birthdayRelated && _isBirthdayMonth(prefs)) {
    boost += RankingContract.birthdayBoost;
  }

  final priorities = prefs.dealPriorities.map(_norm).toSet();
  final ptype = _norm(p.promotionType);
  final dtype = _norm(p.discountType);
  final scope = _norm(p.dealScope);
  final value = _norm(p.discountValue ?? '');

  if (priorities.contains('free') && dtype == 'free_item') {
    boost += RankingContract.priorityBoost;
  }
  if (priorities.contains('bogo') &&
      RegExp(
        r'\bbogo\b|buy.one.get.one',
        caseSensitive: false,
      ).hasMatch(p.title)) {
    boost += RankingContract.priorityBoost;
  }
  if (priorities.contains('discount') &&
      (dtype == 'percentage_off' ||
          dtype == 'amount_off' ||
          value.isNotEmpty)) {
    boost += RankingContract.priorityBoost;
  }
  if (priorities.contains('nearby') && p.distanceKm != null) {
    boost += RankingContract.priorityBoost;
  }
  if (priorities.contains('online') &&
      (scope == 'online_only' || p.distanceKm == null)) {
    boost += RankingContract.priorityBoost;
  }
  if (priorities.contains('rewards') &&
      (p.requiresMembership || ptype.contains('reward'))) {
    boost += RankingContract.priorityBoost;
  }

  return boost;
}

double affinityBoost(Promotion p, InteractionService svc) {
  double boost = 0.0;
  if (SavedDealsService().get(p.id) != null) {
    boost += RankingContract.savedDealBoost;
  }
  if (svc.clickCount(p.id) > 0) {
    boost += RankingContract.clickedDealBoost;
  }
  if (svc.isBrandRecentlySearched(p.brand)) {
    boost += RankingContract.recentBrandSearchBoost;
  }
  return boost;
}

double _personalModelBoost(Promotion p) {
  final score = p.personalRankScore;
  if (score == null) {
    return _isEmailDerived(p) ? RankingContract.emailSourceBoost : 0.0;
  }
  final modelBoost = ((score - 60.0) * RankingContract.personalModelMultiplier)
      .clamp(
        -RankingContract.personalModelPenaltyCap,
        RankingContract.personalModelBoostCap,
      )
      .toDouble();
  if (_isEmailDerived(p) && score >= RankingContract.emailPersonalRankFloor) {
    return modelBoost + RankingContract.emailSourceBoost;
  }
  return modelBoost;
}

double _contextBonus(Promotion p) {
  double bonus = 0.0;
  if (p.validDays.isNotEmpty && p.isValidToday) {
    bonus += RankingContract.validTodayBonus;
  }
  final valueGate = (p.economicValueScore / 35.0).clamp(0.0, 1.0).toDouble();
  final urgency =
      p.expirationUrgencyScore * valueGate * RankingContract.urgencyMultiplier;
  bonus += urgency;
  return bonus;
}

double _weakDealPenalty(Promotion p) {
  double penalty = 0.0;
  final ptype = _norm(p.promotionType);
  final dtype = _norm(p.discountType);
  final title = _norm(p.title);

  if (ptype == 'app_offer' && dtype == 'unknown') penalty += 18.0;
  if (title.contains('select style')) penalty += 10.0;
  if (title.contains('newsletter') || title.contains('sign up')) {
    penalty += 18.0;
  }
  if (title.contains('limited time') && dtype == 'unknown') penalty += 10.0;
  return penalty;
}

class ScoreBreakdown {
  final double rankBase;
  final double distanceBonus;
  final double dayBonus;
  final double membershipBonus;
  final double affinityBoost;
  final double preferenceBoost;
  final double personalModelBoost;
  final double fatiguePenalty;
  final bool isHidden;

  const ScoreBreakdown({
    required this.rankBase,
    required this.distanceBonus,
    required this.dayBonus,
    required this.membershipBonus,
    required this.affinityBoost,
    required this.preferenceBoost,
    required this.personalModelBoost,
    required this.fatiguePenalty,
    required this.isHidden,
  });

  double get total => isHidden
      ? double.negativeInfinity
      : rankBase +
            distanceBonus +
            dayBonus +
            membershipBonus +
            affinityBoost +
            preferenceBoost +
            personalModelBoost -
            fatiguePenalty;
}

ScoreBreakdown computeBreakdown(
  Promotion p,
  InteractionService svc, {
  double? distanceKm,
  bool isMember = false,
  UserPrefs? prefs,
}) {
  final rawFatigue = fatiguePenalty(p.id, svc);
  final hidden = rawFatigue >= _kHide || _isHiddenByPrefs(p, prefs);

  return ScoreBreakdown(
    rankBase: p.globalQualityScore - _weakDealPenalty(p),
    distanceBonus: _distanceBonus(distanceKm),
    dayBonus: _contextBonus(p),
    membershipBonus: _membershipBonus(p, isMember),
    affinityBoost: affinityBoost(p, svc),
    preferenceBoost: preferenceBoost(p, prefs),
    personalModelBoost: _personalModelBoost(p),
    fatiguePenalty: hidden ? _kHide : rawFatigue,
    isHidden: hidden,
  );
}

double dealQualityScore(
  Promotion p,
  InteractionService svc, {
  double? distanceKm,
  bool isMember = false,
  UserPrefs? prefs,
}) {
  final bd = computeBreakdown(
    p,
    svc,
    distanceKm: distanceKm,
    isMember: isMember,
    prefs: prefs,
  );
  return bd.total;
}

double personalizedScore(
  Promotion p,
  InteractionService svc, {
  double? distanceKm,
  bool isMember = false,
  UserPrefs? prefs,
}) => dealQualityScore(
  p,
  svc,
  distanceKm: distanceKm,
  isMember: isMember,
  prefs: prefs,
);

class _ScoredPromo {
  final Promotion promo;
  final double score;
  const _ScoredPromo(this.promo, this.score);
}

List<Promotion> _takeDiverse(
  List<_ScoredPromo> scored, {
  required int limit,
  int maxPerBrand = RankingContract.maxPrimaryDealsPerBrand,
}) {
  final selected = <Promotion>[];
  final perBrand = <String, int>{};

  void pass(int brandCap) {
    for (final item in scored) {
      if (selected.length >= limit) return;
      if (selected.any((p) => p.id == item.promo.id)) continue;
      final brand = _norm(item.promo.brand);
      final count = perBrand[brand] ?? 0;
      if (count >= brandCap) continue;
      perBrand[brand] = count + 1;
      selected.add(item.promo);
    }
  }

  pass(maxPerBrand);
  if (selected.length < limit) {
    pass(RankingContract.maxFallbackDealsPerBrand);
  }
  return selected.take(limit).toList();
}

List<Promotion> selectTopDeals(
  List<Promotion> candidates,
  InteractionService svc, {
  double? Function(Promotion)? getDistance,
  bool Function(Promotion)? getIsMember,
  UserPrefs? prefs,
  int limit = RankingContract.forYouLimit,
  int maxPerBrand = RankingContract.maxPrimaryDealsPerBrand,
  Set<String> extraFavBrands = const {},
}) {
  final favBrands = {
    for (final b in prefs?.favoriteBrands ?? const <String>[]) _norm(b),
    ...extraFavBrands.map(_norm),
  };

  final scored = <_ScoredPromo>[];
  for (final p in candidates) {
    if (_isHiddenByPrefs(p, prefs)) continue;
    if (!isFeedWorthy(p, favBrands: favBrands)) continue;

    final score = dealQualityScore(
      p,
      svc,
      distanceKm: getDistance?.call(p),
      isMember: getIsMember?.call(p) ?? false,
      prefs: prefs,
    );
    if (score.isFinite) scored.add(_ScoredPromo(p, score));
  }

  scored.sort((a, b) => b.score.compareTo(a.score));
  return _takeDiverse(scored, limit: limit, maxPerBrand: maxPerBrand);
}

bool _isNearMeEligible(Promotion p, double radiusKm, UserPrefs? prefs) {
  if (_isHiddenByPrefs(p, prefs)) return false;
  if (!p.isActive || !p.isValidToday) return false;
  if (p.confidenceScore < RankingContract.minConfidence) return false;
  if (p.globalQualityScore < RankingContract.nearMeQualityFloor) return false;
  if (p.distanceKm == null || p.distanceKm! > radiusKm) return false;
  if (p.dealScope == 'online_only') return false;
  if (_blockedNearMeCategories.contains(_norm(p.category))) return false;
  if (!_nearMeRedemptionMethods.contains(_norm(p.redemptionMethod))) {
    return false;
  }
  if (_isRewardProgram(p) && !_hasImmediateValue(p)) return false;
  return true;
}

List<Promotion> selectNearbyDeals(
  List<Promotion> candidates,
  InteractionService svc, {
  bool Function(Promotion)? getIsMember,
  UserPrefs? prefs,
  int limit = RankingContract.nearMeLimit,
  double radiusKm = RankingContract.nearMeMaxDistanceKm,
}) {
  final scored = <_ScoredPromo>[];
  for (final p in candidates) {
    if (!_isNearMeEligible(p, radiusKm, prefs)) continue;
    final score = dealQualityScore(
      p,
      svc,
      distanceKm: p.distanceKm,
      isMember: getIsMember?.call(p) ?? false,
      prefs: prefs,
    );
    if (score.isFinite) scored.add(_ScoredPromo(p, score));
  }

  scored.sort((a, b) {
    final scoreCompare = b.score.compareTo(a.score);
    if (scoreCompare != 0) return scoreCompare;
    return (a.promo.distanceKm ?? double.infinity).compareTo(
      b.promo.distanceKm ?? double.infinity,
    );
  });
  return _takeDiverse(scored, limit: limit);
}

Map<String, double> inferCategoryWeights(
  List<String> favoriteBrands,
  List<Promotion> allPromos,
) {
  if (favoriteBrands.isEmpty) return {};
  final favorites = favoriteBrands.map(_norm).toSet();
  final counts = <String, int>{};
  for (final p in allPromos) {
    if (!favorites.contains(_norm(p.brand))) continue;
    final category = p.category;
    if (category.isEmpty) continue;
    counts[category] = (counts[category] ?? 0) + 1;
  }
  if (counts.isEmpty) return {};
  final total = counts.values.fold<int>(0, (sum, n) => sum + n);
  return {for (final entry in counts.entries) entry.key: entry.value / total};
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
  if (deals.isEmpty) return 0.0;
  final bestDeal = deals
      .map((p) => dealQualityScore(p, svc, prefs: prefs))
      .reduce((a, b) => a > b ? a : b);

  double score = bestDeal;
  if (prefs?.favoriteBrands.any((b) => _norm(b) == _norm(brand)) ?? false) {
    score += RankingContract.favoriteBrandBoost;
  }
  if (prefs?.favoriteCategories.any((c) => _norm(c) == _norm(category)) ??
      false) {
    score += RankingContract.favoriteCategoryBoost;
  }
  if (svc.isBrandRecentlySearched(brand)) {
    score += RankingContract.recentBrandSearchBoost;
  }
  score += deals.length.clamp(0, 3).toDouble() * 2.0;
  score += (inferredCategoryWeights?[category] ?? 0.0) * 10.0;
  score += (categoryEngagement?[_norm(category)] ?? 0.0) * 5.0;
  return score;
}

enum RankingMode { forYou, search, nearby, expiringSoon, bestValue }

List<Promotion> rankForSurface(
  List<Promotion> candidates,
  RankingMode mode,
  InteractionService svc, {
  double? Function(Promotion)? getDistance,
  bool Function(Promotion)? getIsMember,
  UserPrefs? prefs,
  int limit = RankingContract.forYouLimit,
}) {
  switch (mode) {
    case RankingMode.forYou:
      return selectTopDeals(
        candidates,
        svc,
        getDistance: getDistance,
        getIsMember: getIsMember,
        prefs: prefs,
        limit: limit,
      );

    case RankingMode.nearby:
      return selectNearbyDeals(
        candidates,
        svc,
        getIsMember: getIsMember,
        prefs: prefs,
        limit: limit,
      );

    case RankingMode.search:
      final scored =
          candidates
              .where((p) => p.isActive && !_isHiddenByPrefs(p, prefs))
              .map(
                (p) => _ScoredPromo(
                  p,
                  dealQualityScore(
                    p,
                    svc,
                    distanceKm: getDistance?.call(p),
                    isMember: getIsMember?.call(p) ?? false,
                    prefs: prefs,
                  ),
                ),
              )
              .where((item) => item.score.isFinite)
              .toList()
            ..sort((a, b) => b.score.compareTo(a.score));
      return _takeDiverse(scored, limit: limit, maxPerBrand: 2);

    case RankingMode.expiringSoon:
      final urgent =
          candidates
              .where(
                (p) =>
                    p.isActive &&
                    !_isHiddenByPrefs(p, prefs) &&
                    p.expirationUrgencyScore > 0 &&
                    p.globalQualityScore >= RankingContract.nearMeQualityFloor,
              )
              .toList()
            ..sort((a, b) {
              final urgency = b.expirationUrgencyScore.compareTo(
                a.expirationUrgencyScore,
              );
              if (urgency != 0) return urgency;
              return b.globalQualityScore.compareTo(a.globalQualityScore);
            });
      return urgent.take(limit).toList();

    case RankingMode.bestValue:
      final valueDeals =
          candidates
              .where((p) => p.isActive && !_isHiddenByPrefs(p, prefs))
              .toList()
            ..sort(
              (a, b) => b.economicValueScore.compareTo(a.economicValueScore),
            );
      return valueDeals.take(limit).toList();
  }
}
