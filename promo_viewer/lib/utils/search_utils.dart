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

/// Product-type tags per brand. Searched as tier 6 (between title and category).
/// Lets users find "shoes", "handbags", "watches", etc. without knowing brand names.
const Map<String, List<String>> kBrandProductTags = {
  // ── Handbags / Wallets / Purses ───────────────────────────────────────────
  'Coach':           ['handbags', 'bags', 'wallets', 'purses', 'leather goods', 'accessories', 'totes'],
  'Kate Spade':      ['handbags', 'bags', 'wallets', 'purses', 'accessories', 'totes'],
  'Michael Kors':    ['handbags', 'bags', 'wallets', 'purses', 'watches', 'accessories', 'totes'],
  'Tory Burch':      ['handbags', 'bags', 'wallets', 'purses', 'shoes', 'sandals', 'accessories'],
  'Rebecca Minkoff': ['handbags', 'bags', 'wallets', 'purses', 'backpacks', 'accessories'],
  'Vera Bradley':    ['bags', 'totes', 'backpacks', 'purses', 'luggage', 'accessories'],
  'BCBG':            ['handbags', 'bags', 'dresses', 'clothing', 'accessories'],
  'Fossil':          ['watches', 'wallets', 'bags', 'jewelry', 'accessories', 'smartwatches'],

  // ── Jewelry ──────────────────────────────────────────────────────────────
  'Kendra Scott':    ['jewelry', 'necklaces', 'earrings', 'rings', 'bracelets', 'accessories', 'pendants'],

  // ── Watches ──────────────────────────────────────────────────────────────
  // (Michael Kors and Fossil above also cover watches)

  // ── Luggage / Travel Bags ────────────────────────────────────────────────
  'Tumi':            ['luggage', 'bags', 'backpacks', 'travel bags', 'suitcases', 'carry-on', 'briefcases', 'accessories'],

  // ── Shoes / Footwear ─────────────────────────────────────────────────────
  'Stuart Weitzman': ['shoes', 'boots', 'heels', 'sandals', 'pumps', 'footwear'],
  'Sam Edelman':     ['shoes', 'boots', 'sandals', 'flats', 'heels', 'footwear'],
  'Cole Haan':       ['shoes', 'boots', 'loafers', 'sneakers', 'oxfords', 'footwear', 'dress shoes'],
  'DSW':             ['shoes', 'boots', 'sandals', 'sneakers', 'heels', 'flats', 'footwear'],
  'Famous Footwear': ['shoes', 'sneakers', 'boots', 'sandals', 'footwear'],
  'Foot Locker':     ['sneakers', 'shoes', 'athletic shoes', 'footwear'],
  'Finish Line':     ['sneakers', 'athletic shoes', 'shoes', 'footwear'],
  'Champs Sports':   ['sneakers', 'athletic shoes', 'shoes', 'footwear'],
  'Journeys':        ['shoes', 'sneakers', 'boots', 'footwear'],
  'Shoe Carnival':   ['shoes', 'boots', 'sandals', 'sneakers', 'footwear'],
  'Rack Room Shoes': ['shoes', 'boots', 'sandals', 'sneakers', 'footwear'],
  'Naturalizer':     ['shoes', 'boots', 'flats', 'heels', 'footwear', 'comfort shoes'],
  'Nine West':       ['shoes', 'heels', 'boots', 'flats', 'sandals', 'footwear'],
  'Skechers':        ['shoes', 'sneakers', 'walking shoes', 'boots', 'footwear'],
  'Converse':        ['sneakers', 'shoes', 'footwear', 'chucks'],
  'Vans':            ['sneakers', 'shoes', 'skate shoes', 'footwear'],
  'Dr. Martens':     ['boots', 'shoes', 'footwear'],
  'Crocs':           ['shoes', 'sandals', 'clogs', 'footwear'],
  'Kizik':           ['shoes', 'sneakers', 'slip-on shoes', 'footwear'],
  'Johnston & Murphy': ['shoes', 'dress shoes', 'boots', 'loafers', 'footwear'],
  'Merrell':         ['shoes', 'hiking shoes', 'boots', 'outdoor footwear', 'footwear'],
  'Nike':            ['sneakers', 'shoes', 'athletic shoes', 'footwear', 'activewear', 'sportswear', 'workout clothes'],
  'Adidas':          ['sneakers', 'shoes', 'athletic shoes', 'footwear', 'activewear', 'sportswear'],
  'Puma':            ['sneakers', 'shoes', 'athletic shoes', 'footwear', 'activewear'],
  'Under Armour':    ['sneakers', 'shoes', 'activewear', 'workout clothes', 'athletic wear', 'leggings'],
  'Reebok':          ['sneakers', 'shoes', 'athletic shoes', 'footwear', 'activewear'],

  // ── Activewear ───────────────────────────────────────────────────────────
  'Lululemon':       ['activewear', 'yoga pants', 'leggings', 'workout clothes', 'athletic wear', 'sports bras', 'shorts'],
  'Fabletics':       ['activewear', 'leggings', 'workout clothes', 'athletic wear', 'sports bras', 'shorts'],
  'Gymshark':        ['activewear', 'gym wear', 'workout clothes', 'leggings', 'shorts'],
  'Alo Yoga':        ['activewear', 'yoga pants', 'leggings', 'workout clothes', 'athletic wear'],
  'Vuori':           ['activewear', 'workout clothes', 'athletic wear', 'shorts', 'leggings'],
  'Outdoor Voices':  ['activewear', 'workout clothes', 'leggings', 'athletic wear'],
  'Sweaty Betty':    ['activewear', 'leggings', 'workout clothes', 'athletic wear'],
  'Rhone':           ['activewear', 'workout clothes', 'athletic wear', 'mens activewear'],
  'Columbia':        ['outdoor clothing', 'jackets', 'activewear', 'hiking gear', 'outdoor gear'],
  'The North Face':  ['outdoor clothing', 'jackets', 'activewear', 'hiking gear', 'outdoor gear', 'coats'],
  'Patagonia':       ['outdoor clothing', 'jackets', 'activewear', 'outdoor gear', 'fleece'],
  'Eddie Bauer':     ['outdoor clothing', 'jackets', 'coats', 'outdoor gear', 'activewear'],
  'L.L.Bean':        ['outdoor clothing', 'boots', 'backpacks', 'bags', 'outdoor gear', 'coats'],

  // ── Dresses / Occasion wear ───────────────────────────────────────────────
  'Lilly Pulitzer':  ['dresses', 'resort wear', 'clothing', 'shift dresses'],
  'AllSaints':       ['jackets', 'leather jackets', 'dresses', 'clothing'],
  'Rag & Bone':      ['jeans', 'dresses', 'jackets', 'clothing', 'work clothes', 'knitwear'],
  'Vince':           ['clothing', 'knitwear', 'dresses', 'work clothes', 'cashmere'],
  'Theory':          ['work clothes', 'office wear', 'blazers', 'dresses', 'suiting', 'business casual'],
  'Club Monaco':     ['work clothes', 'office wear', 'clothing', 'dresses', 'blazers'],
  'Vineyard Vines':  ['clothing', 'polos', 'shirts', 'dresses', 'preppy'],
  'Ralph Lauren':    ['polo shirts', 'clothing', 'dresses', 'work clothes', 'knitwear', 'suiting'],
  'Tommy Hilfiger':  ['polo shirts', 'clothing', 'jeans', 'shirts', 'dresses'],
  'Calvin Klein':    ['jeans', 'underwear', 'clothing', 'dresses', 'basics'],
  'Guess':           ['jeans', 'dresses', 'clothing', 'handbags', 'accessories'],
  'Ted Baker':       ['dresses', 'suits', 'work clothes', 'clothing', 'blazers'],
  'BCBG':            ['dresses', 'clothing', 'formal wear', 'work clothes'],

  // ── Work Clothes / Office wear ────────────────────────────────────────────
  'Brooks Brothers': ['suits', 'dress shirts', 'work clothes', 'office wear', 'ties', 'blazers', 'business wear', 'suiting'],
  'Ann Taylor':      ['work clothes', 'dresses', 'office wear', 'business casual', 'blazers', 'suiting'],
  'LOFT':            ['work clothes', 'dresses', 'office wear', 'business casual', 'clothing'],
  'Talbots':         ['work clothes', 'dresses', 'classic clothing', 'blazers', 'office wear'],
  "Chico's":         ['clothing', 'work clothes', 'dresses', 'blazers'],
  'White House Black Market': ['dresses', 'work clothes', 'office wear', 'clothing', 'business casual'],
  'Banana Republic': ['work clothes', 'suits', 'blazers', 'dresses', 'office wear', 'business casual'],
  'J.Crew':          ['clothing', 'work clothes', 'dresses', 'jeans', 'knitwear', 'blazers'],
  'Madewell':        ['jeans', 'denim', 'clothing', 'dresses', 'basics'],

  // ── Jeans / Denim ─────────────────────────────────────────────────────────
  'Lee':             ['jeans', 'denim', 'work clothes', 'pants'],
  'Wrangler':        ['jeans', 'denim', 'western wear', 'pants'],
  'Lucky Brand':     ['jeans', 'denim', 'clothing'],
  'American Eagle':  ['jeans', 'denim', 'clothing', 'basics', 'activewear'],
  'Aerie':           ['underwear', 'bras', 'activewear', 'swimwear', 'loungewear', 'leggings'],
  'Gap':             ['jeans', 'denim', 'basics', 'clothing', 'activewear'],
  'Old Navy':        ['jeans', 'clothing', 'basics', 'activewear', 'kids clothes'],

  // ── Plus size ─────────────────────────────────────────────────────────────
  'Eloquii':         ['plus size', 'dresses', 'work clothes', 'clothing', 'office wear'],
  'Torrid':          ['plus size', 'clothing', 'dresses', 'activewear', 'jeans'],
  'Lane Bryant':     ['plus size', 'clothing', 'bras', 'jeans', 'dresses'],

  // ── Streetwear / Youth ────────────────────────────────────────────────────
  'Hot Topic':       ['graphic tees', 'clothing', 'accessories', 'pop culture'],
  'BoxLunch':        ['graphic tees', 'clothing', 'accessories', 'pop culture'],
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
/// 5 = title, 6 = product tag, 7 = category, 8 = promo code. 0 = no match.
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

  // Product tag check — lets users search "shoes", "handbags", "watches", etc.
  for (final entry in kBrandProductTags.entries) {
    if (_norm(entry.key) == brand) {
      for (final tag in entry.value) {
        if (_norm(tag).contains(q) || q.contains(_norm(tag))) return 6;
      }
      break;
    }
  }

  if (_norm(p.category).contains(q)) return 7;
  if (p.promoCode != null && _norm(p.promoCode!).contains(q)) return 8;

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
