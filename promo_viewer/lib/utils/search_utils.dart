import '../models/promotion.dart';

const Map<String, List<String>> kBrandAliases = {
  "McDonald's":        ['mcdonalds', 'mcd', 'mickey d'],
  "Chick-fil-A":       ['chick fil a', 'chickfila', 'chick fil'],
  "Bath & Body Works": ['bath body', 'bbw'],
  "Dunkin":            ['dunkin donuts'],
  "T.J.Maxx":         ['tj maxx', 'tjmaxx'],
  "L.L.Bean":         ['ll bean', 'llbean'],
  "Popeyes":          ['popeyes louisiana', 'popeye'],
  "Taco Bell":        ['tacobell'],
  "Burger King":      ['bk', 'burger king'],
  "Pizza Hut":        ['pizzahut'],
  "Domino's":         ['dominos'],
  "Panda Express":    ['panda'],
  "Panera Bread":     ['panera'],
  "Chipotle":         ['chipotle mexican'],
  "Five Guys":        ['five guys burgers'],
  "Jack in the Box":  ['jack in box', 'jitb'],
};

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9 ]"), '').trim();

/// Returns context labels for a promotion (Online, Near Me, Rewards).
List<String> dealContextLabels(Promotion p) {
  if (p.promotionType == 'reward' || p.promotionType == 'membership_benefit') {
    return ['Rewards'];
  }
  final labels = <String>[];
  final isOnline = p.redemptionMethod == 'online' ||
      (p.redemptionMethod == 'show_code' && p.dealScope == 'online_only');
  if (isOnline) labels.add('Online');
  const nearMeRedemption = {
    'in_store', 'in_app', 'app_reward', 'show_code', 'open_maps'
  };
  if (nearMeRedemption.contains(p.redemptionMethod) &&
      p.dealScope != 'online_only') {
    labels.add('Near Me');
  }
  if (labels.isEmpty) labels.add('Online');
  return labels;
}

/// Scores a promotion against [query].
/// 1 = exact brand, 2 = brand starts-with, 3 = alias, 4 = brand contains,
/// 5 = title, 6 = category, 7 = promo code. 0 = no match.
int searchTier(Promotion p, String query) {
  if (query.isEmpty) return 0;
  final q = _norm(query);
  if (q.isEmpty) return 0;
  final brand = _norm(p.brand);

  if (brand == q) return 1;
  if (brand.startsWith(q)) return 2;

  // Alias check
  for (final entry in kBrandAliases.entries) {
    if (_norm(entry.key) == brand || brand.contains(_norm(entry.key))) {
      for (final alias in entry.value) {
        final na = _norm(alias);
        if (na == q || na.startsWith(q)) return 3;
      }
    }
  }

  if (brand.contains(q)) return 4;
  if (_norm(p.title).contains(q)) return 5;
  if (_norm(p.category).contains(q)) return 6;
  if (p.promoCode != null && _norm(p.promoCode!).contains(q)) return 7;

  return 0;
}

/// A brand with its matching deals grouped for display in search results.
class BrandGroup {
  final String brand;
  final List<Promotion> deals;
  final int bestTier;
  final List<String> contexts;

  const BrandGroup({
    required this.brand,
    required this.deals,
    required this.bestTier,
    required this.contexts,
  });

  int get regularCount => deals
      .where((p) =>
          p.promotionType != 'reward' &&
          p.promotionType != 'membership_benefit')
      .length;
  int get rewardCount => deals
      .where((p) =>
          p.promotionType == 'reward' ||
          p.promotionType == 'membership_benefit')
      .length;
}

/// Searches [all] for [query] and returns brand groups sorted by relevance.
/// Excludes email-only (private) deals.
List<BrandGroup> runSearch(List<Promotion> all, String query) {
  if (query.trim().isEmpty) return [];

  final scored = <Promotion, int>{};
  for (final p in all) {
    if (!p.isActive) continue;
    if (p.source == 'email') continue;
    final tier = searchTier(p, query);
    if (tier > 0) scored[p] = tier;
  }
  if (scored.isEmpty) return [];

  // Group by brand
  final brandMap = <String, List<MapEntry<Promotion, int>>>{};
  for (final e in scored.entries) {
    brandMap.putIfAbsent(e.key.brand, () => []).add(e);
  }

  final groups = brandMap.entries.map((e) {
    final entries = List.of(e.value)
      ..sort((a, b) {
        final t = a.value.compareTo(b.value);
        if (t != 0) return t;
        return b.key.rankScore().compareTo(a.key.rankScore());
      });
    final bestTier = entries.map((x) => x.value).reduce((a, b) => a < b ? a : b);
    final contexts = <String>{};
    for (final p in entries.map((x) => x.key)) {
      contexts.addAll(dealContextLabels(p));
    }
    return BrandGroup(
      brand: e.key,
      deals: entries.map((x) => x.key).toList(),
      bestTier: bestTier,
      contexts: contexts.toList(),
    );
  }).toList()
    ..sort((a, b) => a.bestTier.compareTo(b.bestTier));

  return groups;
}
