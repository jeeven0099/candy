import '../models/promotion.dart';

// ── Brand aliases ─────────────────────────────────────────────────────────────
const Map<String, List<String>> kBrandAliases = {
  "McDonald's":          ['mcdonalds', 'mcd', 'mickey d'],
  "Chick-fil-A":         ['chick fil a', 'chickfila', 'chick fil'],
  "Dunkin":              ['dunkin donuts'],
  "T.J.Maxx":           ['tj maxx', 'tjmaxx'],
  "L.L.Bean":           ['ll bean', 'llbean'],
  "Popeyes":            ['popeyes louisiana', 'popeye'],
  "Taco Bell":          ['tacobell'],
  "Burger King":        ['bk'],
  "Pizza Hut":          ['pizzahut'],
  "Domino's":           ['dominos'],
  "Panda Express":      ['panda'],
  "Panera Bread":       ['panera'],
  "Chipotle":           ['chipotle mexican'],
  "Five Guys":          ['five guys burgers'],
  "Jack in the Box":    ['jack in box', 'jitb'],
  "Shake Shack":        ['shakeshack'],
  "Whataburger":        ['whata'],
  "Krispy Kreme":       ['krispy'],
  "Dairy Queen":        ['dq', 'dairy queen'],
  "Cold Stone Creamery":['cold stone'],
  "Smoothie King":      ['smoothie king'],
  "Jamba":              ['jamba juice'],
  "Wingstop":           ['wing stop'],
  "Buffalo Wild Wings": ['bdubs', 'bww', 'buffalo wild'],
  "Red Lobster":        ['red lobster'],
  "Outback Steakhouse": ['outback'],
  "Texas Roadhouse":    ['texas road'],
  "Cracker Barrel":     ['cracker barrel'],
  "The North Face":     ['north face', 'tnf'],
  "Bath & Body Works":  ['bath body', 'bath and body', 'bath and body works'],
  "Sephora":            ['sephora'],
  "Ulta Beauty":        ['ulta'],
  "Sally Beauty":       ['sally'],
  "Dick's Sporting Goods": ['dicks', 'dsg'],
  "Sam's Club":         ['sams club', 'samsclub'],
  "Whole Foods Market": ['whole foods'],
  "Trader Joe's":       ['trader joes'],
  "H-E-B":              ['heb'],
  "Starbucks":          ['sbux', 'starbucks coffee'],
  "Dutch Bros":         ['dutch brothers'],
  "Peet's Coffee":      ['peets'],
  "Ann Taylor":         ['ann taylor loft'],
  "White House Black Market": ['whbm'],
  "Banana Republic":    ['br'],
  "Abercrombie & Fitch":['abercrombie', 'a&f', 'anf'],
};

// ── Brand product tags ────────────────────────────────────────────────────────
const Map<String, List<String>> kBrandProductTags = {
  'Coach':              ['handbags', 'bags', 'wallets', 'purses', 'leather goods', 'accessories', 'totes'],
  'Kate Spade':         ['handbags', 'bags', 'wallets', 'purses', 'accessories', 'totes'],
  'Michael Kors':       ['handbags', 'bags', 'wallets', 'purses', 'watches', 'accessories', 'totes'],
  'Tory Burch':         ['handbags', 'bags', 'wallets', 'purses', 'shoes', 'sandals', 'accessories'],
  'Rebecca Minkoff':    ['handbags', 'bags', 'wallets', 'purses', 'backpacks', 'accessories'],
  'Vera Bradley':       ['bags', 'totes', 'backpacks', 'purses', 'luggage', 'accessories'],
  'BCBG':               ['handbags', 'bags', 'dresses', 'clothing', 'formal wear', 'work clothes', 'accessories'],
  'Fossil':             ['watches', 'wallets', 'bags', 'jewelry', 'accessories', 'smartwatches'],
  'Kendra Scott':       ['jewelry', 'necklaces', 'earrings', 'rings', 'bracelets', 'accessories', 'pendants'],
  'Tumi':               ['luggage', 'bags', 'backpacks', 'travel bags', 'suitcases', 'carry-on', 'briefcases'],
  'Stuart Weitzman':    ['shoes', 'boots', 'heels', 'sandals', 'pumps', 'footwear'],
  'Sam Edelman':        ['shoes', 'boots', 'sandals', 'flats', 'heels', 'footwear'],
  'Cole Haan':          ['shoes', 'boots', 'loafers', 'sneakers', 'oxfords', 'footwear', 'dress shoes'],
  'DSW':                ['shoes', 'boots', 'sandals', 'sneakers', 'heels', 'flats', 'footwear'],
  'Famous Footwear':    ['shoes', 'sneakers', 'boots', 'sandals', 'footwear'],
  'Foot Locker':        ['sneakers', 'shoes', 'athletic shoes', 'footwear'],
  'Finish Line':        ['sneakers', 'athletic shoes', 'shoes', 'footwear'],
  'Champs Sports':      ['sneakers', 'athletic shoes', 'shoes', 'footwear'],
  'Journeys':           ['shoes', 'sneakers', 'boots', 'footwear'],
  'Shoe Carnival':      ['shoes', 'boots', 'sandals', 'sneakers', 'footwear'],
  'Rack Room Shoes':    ['shoes', 'boots', 'sandals', 'sneakers', 'footwear'],
  'Naturalizer':        ['shoes', 'boots', 'flats', 'heels', 'footwear', 'comfort shoes'],
  'Nine West':          ['shoes', 'heels', 'boots', 'flats', 'sandals', 'footwear'],
  'Skechers':           ['shoes', 'sneakers', 'walking shoes', 'boots', 'footwear'],
  'Converse':           ['sneakers', 'shoes', 'footwear', 'chucks'],
  'Vans':               ['sneakers', 'shoes', 'skate shoes', 'footwear'],
  'Dr. Martens':        ['boots', 'shoes', 'footwear'],
  'Crocs':              ['shoes', 'sandals', 'clogs', 'footwear'],
  'Kizik':              ['shoes', 'sneakers', 'slip-on shoes', 'footwear'],
  'Johnston & Murphy':  ['shoes', 'dress shoes', 'boots', 'loafers', 'footwear'],
  'Merrell':            ['shoes', 'hiking shoes', 'boots', 'outdoor footwear', 'footwear'],
  'Nike':               ['sneakers', 'shoes', 'athletic shoes', 'footwear', 'activewear', 'sportswear', 'workout clothes'],
  'Adidas':             ['sneakers', 'shoes', 'athletic shoes', 'footwear', 'activewear', 'sportswear'],
  'Puma':               ['sneakers', 'shoes', 'athletic shoes', 'footwear', 'activewear'],
  'Under Armour':       ['sneakers', 'shoes', 'activewear', 'workout clothes', 'athletic wear', 'leggings'],
  'Reebok':             ['sneakers', 'shoes', 'athletic shoes', 'footwear', 'activewear'],
  'Lululemon':          ['activewear', 'yoga pants', 'leggings', 'workout clothes', 'athletic wear', 'sports bras', 'shorts'],
  'Fabletics':          ['activewear', 'leggings', 'workout clothes', 'athletic wear', 'sports bras', 'shorts'],
  'Gymshark':           ['activewear', 'gym wear', 'workout clothes', 'leggings', 'shorts'],
  'Alo Yoga':           ['activewear', 'yoga pants', 'leggings', 'workout clothes', 'athletic wear'],
  'Vuori':              ['activewear', 'workout clothes', 'athletic wear', 'shorts', 'leggings'],
  'Columbia':           ['outdoor clothing', 'jackets', 'activewear', 'hiking gear', 'outdoor gear'],
  'The North Face':     ['outdoor clothing', 'jackets', 'activewear', 'hiking gear', 'outdoor gear', 'coats'],
  'Patagonia':          ['outdoor clothing', 'jackets', 'activewear', 'outdoor gear', 'fleece'],
  'Eddie Bauer':        ['outdoor clothing', 'jackets', 'coats', 'outdoor gear', 'activewear'],
  'L.L.Bean':           ['outdoor clothing', 'boots', 'backpacks', 'bags', 'outdoor gear', 'coats'],
  'Lilly Pulitzer':     ['dresses', 'resort wear', 'clothing', 'shift dresses'],
  'AllSaints':          ['jackets', 'leather jackets', 'dresses', 'clothing'],
  'Rag & Bone':         ['jeans', 'dresses', 'jackets', 'clothing', 'work clothes', 'knitwear'],
  'Vince':              ['clothing', 'knitwear', 'dresses', 'work clothes', 'cashmere'],
  'Theory':             ['work clothes', 'office wear', 'blazers', 'dresses', 'suiting', 'business casual'],
  'Club Monaco':        ['work clothes', 'office wear', 'clothing', 'dresses', 'blazers'],
  'Vineyard Vines':     ['clothing', 'polos', 'shirts', 'dresses', 'preppy'],
  'Ralph Lauren':       ['polo shirts', 'clothing', 'dresses', 'work clothes', 'knitwear', 'suiting'],
  'Tommy Hilfiger':     ['polo shirts', 'clothing', 'jeans', 'shirts', 'dresses'],
  'Calvin Klein':       ['jeans', 'underwear', 'clothing', 'dresses', 'basics'],
  'Guess':              ['jeans', 'dresses', 'clothing', 'handbags', 'accessories'],
  'Ted Baker':          ['dresses', 'suits', 'work clothes', 'clothing', 'blazers'],
  'Brooks Brothers':    ['suits', 'dress shirts', 'work clothes', 'office wear', 'ties', 'blazers'],
  'Ann Taylor':         ['work clothes', 'dresses', 'office wear', 'business casual', 'blazers'],
  'LOFT':               ['work clothes', 'dresses', 'office wear', 'business casual', 'clothing'],
  'Talbots':            ['work clothes', 'dresses', 'classic clothing', 'blazers', 'office wear'],
  "Chico's":            ['clothing', 'work clothes', 'dresses', 'blazers'],
  'White House Black Market': ['dresses', 'work clothes', 'office wear', 'clothing'],
  'Banana Republic':    ['work clothes', 'suits', 'blazers', 'dresses', 'office wear'],
  'J.Crew':             ['clothing', 'work clothes', 'dresses', 'jeans', 'knitwear', 'blazers'],
  'Madewell':           ['jeans', 'denim', 'clothing', 'dresses', 'basics'],
  'Lee':                ['jeans', 'denim', 'work clothes', 'pants'],
  'Wrangler':           ['jeans', 'denim', 'western wear', 'pants'],
  'Lucky Brand':        ['jeans', 'denim', 'clothing'],
  'American Eagle':     ['jeans', 'denim', 'clothing', 'basics', 'activewear'],
  'Aerie':              ['underwear', 'bras', 'activewear', 'swimwear', 'loungewear', 'leggings'],
  'Gap':                ['jeans', 'denim', 'basics', 'clothing', 'activewear'],
  'Old Navy':           ['jeans', 'clothing', 'basics', 'activewear', 'kids clothes'],
  'Eloquii':            ['plus size', 'dresses', 'work clothes', 'clothing', 'office wear'],
  'Torrid':             ['plus size', 'clothing', 'dresses', 'activewear', 'jeans'],
  'Lane Bryant':        ['plus size', 'clothing', 'bras', 'jeans', 'dresses'],
  'Hot Topic':          ['graphic tees', 'clothing', 'accessories', 'pop culture'],
  'BoxLunch':           ['graphic tees', 'clothing', 'accessories', 'pop culture'],
};

// ── Search taxonomy: item queries → brand names ───────────────────────────────
// Enables "burgers" → show McDonald's, Wendy's etc. even if their title says "40% off"
const Map<String, Map<String, List<String>>> kSearchTaxonomy = {
  // ── Food ──────────────────────────────────────────────────────────────────
  'burgers': {
    'aliases': ['burger', 'cheeseburger', 'hamburger', 'whopper', 'big mac'],
    'brands': ["Burger King", "McDonald's", "Wendy's", "Five Guys", "Shake Shack", "Whataburger", "Sonic Drive-In"],
  },
  'pizza': {
    'aliases': ['pizzas', 'slice', 'pepperoni', 'calzone'],
    'brands': ["Domino's", "Pizza Hut", "Papa Johns", "Little Caesars"],
  },
  'coffee': {
    'aliases': ['latte', 'espresso', 'cold brew', 'cappuccino', 'americano', 'iced coffee'],
    'brands': ["Starbucks", "Dunkin", "Dutch Bros", "Peet's Coffee", "Caribou Coffee", "Black Rock Coffee Bar"],
  },
  'tacos': {
    'aliases': ['taco', 'burrito', 'quesadilla', 'mexican food', 'tex mex'],
    'brands': ["Taco Bell", "Chipotle", "Del Taco", "Moe's Southwest Grill"],
  },
  'chicken': {
    'aliases': ['fried chicken', 'chicken sandwich', 'nuggets', 'wings', 'tenders'],
    'brands': ["Chick-fil-A", "Popeyes", "KFC", "Wingstop", "Buffalo Wild Wings", "Raising Cane's"],
  },
  'sandwiches': {
    'aliases': ['sandwich', 'sub', 'hoagie', 'wrap', 'grinder'],
    'brands': ["Subway", "Jimmy John's", "Jersey Mike's", "Firehouse Subs", "Potbelly"],
  },
  'breakfast': {
    'aliases': ['pancakes', 'waffles', 'eggs', 'brunch', 'omelette'],
    'brands': ["IHOP", "Denny's", "Cracker Barrel", "McDonald's", "Dunkin", "Einstein Bros Bagels"],
  },
  'ice cream': {
    'aliases': ['icecream', 'gelato', 'frozen yogurt', 'blizzard', 'sundae', 'milkshake'],
    'brands': ["Dairy Queen", "Baskin-Robbins", "Cold Stone Creamery", "Carvel"],
  },
  'donuts': {
    'aliases': ['donut', 'doughnut', 'pastry'],
    'brands': ["Dunkin", "Krispy Kreme"],
  },
  'smoothies': {
    'aliases': ['smoothie', 'juice', 'acai'],
    'brands': ["Jamba", "Smoothie King"],
  },
  'wings': {
    'aliases': ['wing', 'boneless wings', 'buffalo wings'],
    'brands': ["Wingstop", "Buffalo Wild Wings", "Hooters"],
  },
  'steak': {
    'aliases': ['steakhouse', 'ribeye', 'sirloin', 'bbq', 'grill'],
    'brands': ["Outback Steakhouse", "Texas Roadhouse", "LongHorn Steakhouse", "Applebee's", "TGI Fridays"],
  },
  'salads': {
    'aliases': ['salad', 'healthy food', 'greens', 'bowl'],
    'brands': ["Sweetgreen", "Panera Bread", "Chick-fil-A"],
  },
  'sushi': {
    'aliases': ['sushi', 'ramen', 'japanese food', 'poke', 'hibachi'],
    'brands': [],
  },
  'grocery': {
    'aliases': ['groceries', 'supermarket', 'food shopping', 'produce', 'fresh food'],
    'brands': ["Walmart", "Target", "Kroger", "Whole Foods Market", "Trader Joe's", "Sprouts", "Aldi", "H-E-B"],
  },
  'gas': {
    'aliases': ['gasoline', 'fuel', 'petrol', 'fill up', 'gas station'],
    'brands': ["Shell", "Exxon Mobil"],
  },
  // ── Fashion ───────────────────────────────────────────────────────────────
  'jeans': {
    'aliases': ['jean', 'denim', 'pants', 'trousers'],
    'brands': ["Old Navy", "Gap", "American Eagle", "Abercrombie & Fitch", "Hollister", "Lee", "Wrangler", "Lucky Brand", "Madewell", "Calvin Klein", "Tommy Hilfiger"],
  },
  'shoes': {
    'aliases': ['shoe', 'footwear', 'boots', 'sandals', 'flats', 'heels', 'loafers'],
    'brands': ["Nike", "Adidas", "DSW", "Famous Footwear", "Foot Locker", "Skechers", "Crocs", "Vans", "Converse", "Dr. Martens", "Naturalizer", "Nine West"],
  },
  'sneakers': {
    'aliases': ['sneaker', 'athletic shoes', 'running shoes', 'trainers', 'kicks'],
    'brands': ["Nike", "Adidas", "Foot Locker", "Finish Line", "Champs Sports", "Reebok", "Puma", "New Balance"],
  },
  'handbags': {
    'aliases': ['handbag', 'bag', 'purse', 'wallet', 'tote', 'crossbody', 'clutch', 'shoulder bag'],
    'brands': ["Coach", "Kate Spade", "Michael Kors", "Tory Burch", "Rebecca Minkoff", "Vera Bradley", "Guess"],
  },
  'activewear': {
    'aliases': ['gym clothes', 'workout clothes', 'yoga pants', 'leggings', 'sports bra', 'athletic wear'],
    'brands': ["Nike", "Adidas", "Lululemon", "Under Armour", "Fabletics", "Gymshark", "Alo Yoga", "Vuori"],
  },
  'dresses': {
    'aliases': ['dress', 'gown', 'sundress', 'midi', 'maxi', 'formal wear'],
    'brands': ["BCBG", "Ann Taylor", "LOFT", "White House Black Market", "Ted Baker", "Lilly Pulitzer"],
  },
  'suits': {
    'aliases': ['suit', 'blazer', 'business wear', 'office wear', 'work clothes', 'formal'],
    'brands': ["Brooks Brothers", "Banana Republic", "Theory", "Club Monaco"],
  },
  'outdoor': {
    'aliases': ['hiking', 'camping', 'outdoor gear', 'trail', 'adventure'],
    'brands': ["Patagonia", "The North Face", "Columbia", "Eddie Bauer", "L.L.Bean", "Merrell"],
  },
  'luggage': {
    'aliases': ['suitcase', 'carry on', 'travel bag', 'backpack', 'duffel'],
    'brands': ["Tumi", "Vera Bradley"],
  },
  'jewelry': {
    'aliases': ['necklace', 'earrings', 'ring', 'bracelet', 'pendant', 'chain'],
    'brands': ["Kendra Scott", "Pandora"],
  },
  'watches': {
    'aliases': ['watch', 'timepiece', 'smartwatch'],
    'brands': ["Fossil", "Michael Kors"],
  },
  // ── Beauty ────────────────────────────────────────────────────────────────
  'makeup': {
    'aliases': ['cosmetics', 'foundation', 'lipstick', 'mascara', 'eyeshadow', 'blush', 'beauty'],
    'brands': ["Sephora", "Ulta Beauty", "NYX"],
  },
  'skincare': {
    'aliases': ['moisturizer', 'serum', 'sunscreen', 'cleanser', 'face wash', 'skin care'],
    'brands': ["Sephora", "Ulta Beauty", "The Body Shop"],
  },
  'fragrance': {
    'aliases': ['perfume', 'cologne', 'scent', 'body spray'],
    'brands': ["Sephora", "Ulta Beauty", "Bath & Body Works"],
  },
  'hair': {
    'aliases': ['shampoo', 'conditioner', 'hair color', 'hair care', 'salon'],
    'brands': ["Ulta Beauty", "Sally Beauty"],
  },
  // ── Retail ────────────────────────────────────────────────────────────────
  'electronics': {
    'aliases': ['laptop', 'computer', 'phone', 'tv', 'headphones', 'tablet', 'tech'],
    'brands': ["Best Buy", "Dell", "Newegg"],
  },
  'home': {
    'aliases': ['furniture', 'decor', 'sofa', 'couch', 'bed', 'table', 'home goods'],
    'brands': ["IKEA", "West Elm"],
  },
};

// ── Query type classification ─────────────────────────────────────────────────
enum SearchType { brand, item, deal, location, general }

final _locationRe = RegExp(
    r'\bnear\s*me\b|\bnearby\b|\baround\s*me\b|\bclose\s*by\b|\bwithin\b|\blocal\b',
    caseSensitive: false);
final _dealRe = RegExp(
    r'\bfree\b|\boff\b|\bbogo\b|\bdiscount\b|\bsale\b|\bcoupon\b|\b\d+%\b|\bpromo\b',
    caseSensitive: false);

SearchType classifyQuery(String query) {
  if (_locationRe.hasMatch(query)) return SearchType.location;
  if (_dealRe.hasMatch(query)) return SearchType.deal;
  final q = _norm(query);
  for (final brand in kBrandAliases.keys) {
    if (_norm(brand) == q) return SearchType.brand;
    for (final alias in kBrandAliases[brand]!) {
      if (_norm(alias) == q) return SearchType.brand;
    }
  }
  for (final key in kSearchTaxonomy.keys) {
    if (q == key) return SearchType.item;
    final aliases = kSearchTaxonomy[key]!['aliases']!;
    if (aliases.any((a) => _norm(a) == q)) return SearchType.item;
  }
  return SearchType.general;
}

// ── Search score (replaces tier system as primary sort) ───────────────────────
// Higher = better match.
// Tier is still tracked for backward-compat (affinity recording).
({double score, int tier}) searchMatch(Promotion p, String query, {double? distanceKm}) {
  if (query.isEmpty) return (score: 0, tier: 0);
  final q = _norm(query);
  if (q.isEmpty) return (score: 0, tier: 0);
  final brand = _norm(p.brand);

  double score = 0;
  int tier = 0;

  // ── Brand matching ────────────────────────────────────────────────────────
  if (brand == q) {
    score += 100; tier = 1;
  } else if (brand.startsWith(q)) {
    score += 80; tier = 2;
  } else {
    bool aliasHit = false;
    for (final entry in kBrandAliases.entries) {
      if (_norm(entry.key) == brand) {
        for (final alias in entry.value) {
          final na = _norm(alias);
          if (na == q || na.startsWith(q)) {
            score += 70; tier = 3; aliasHit = true; break;
          }
        }
        break;
      }
    }
    if (!aliasHit && brand.contains(q)) {
      score += 60; tier = 4;
    }
  }

  // ── Taxonomy match ────────────────────────────────────────────────────────
  if (score == 0) {
    for (final entry in kSearchTaxonomy.entries) {
      final key = entry.key;
      final aliases = entry.value['aliases']!;
      final brands  = entry.value['brands']!;
      final isMatch = _norm(key) == q || aliases.any((a) => _norm(a) == q);
      if (isMatch && brands.any((b) => _norm(b) == brand)) {
        score += 60; tier = 5; break;
      }
    }
  }

  // ── Title match ───────────────────────────────────────────────────────────
  if (_norm(p.title).contains(q)) {
    score += 50;
    if (tier == 0) tier = 5;
  }

  // ── Summary match ─────────────────────────────────────────────────────────
  if (p.summary != null && _norm(p.summary!).contains(q)) {
    score += 35;
    if (tier == 0) tier = 6;
  }

  // ── Brand tag match ───────────────────────────────────────────────────────
  if (score == 0) {
    for (final entry in kBrandProductTags.entries) {
      if (_norm(entry.key) == brand) {
        for (final tag in entry.value) {
          if (_norm(tag).contains(q) || q.contains(_norm(tag))) {
            score += 35; tier = 6; break;
          }
        }
        break;
      }
    }
  }

  // ── Category match ────────────────────────────────────────────────────────
  if (_norm(p.category).contains(q)) {
    score += 20;
    if (tier == 0) tier = 7;
  }

  // ── Promo code match ──────────────────────────────────────────────────────
  if (p.promoCode != null && _norm(p.promoCode!).contains(q)) {
    score += 15;
    if (tier == 0) tier = 8;
  }

  if (tier == 0) return (score: 0, tier: 0);

  // ── Secondary boosts (don't change tier order, just break ties) ───────────
  // Rank base: 0–25
  score += (p.rankBaseScore.clamp(0, 100) / 100) * 25;

  // Distance: 0–15
  if (distanceKm != null) {
    final miles = distanceKm * 0.621371;
    if (miles <= 0.5)      { score += 15; }
    else if (miles <= 1.0) { score += 12; }
    else if (miles <= 2.0) { score += 8; }
    else if (miles <= 5.0) { score += 4; }
    else                   { score += 1; }
  }

  return (score: score, tier: tier);
}

// ── BrandGroup ────────────────────────────────────────────────────────────────
class BrandGroup {
  final String brand;
  final List<Promotion> deals;
  final int bestTier;       // kept for affinity recording (tier ≤ 4 = brand match)
  final double bestScore;
  final List<String> contexts;

  const BrandGroup({
    required this.brand,
    required this.deals,
    required this.bestTier,
    required this.bestScore,
    required this.contexts,
  });

  int get regularCount => deals.where((p) =>
      p.promotionType != 'reward' && p.promotionType != 'membership_benefit').length;
  int get rewardCount => deals.where((p) =>
      p.promotionType == 'reward' || p.promotionType == 'membership_benefit').length;
}

// ── runSearch ─────────────────────────────────────────────────────────────────
List<BrandGroup> runSearch(List<Promotion> all, String query) {
  if (query.trim().isEmpty) return [];

  final scored = <Promotion, ({double score, int tier})>{};
  for (final p in all) {
    if (!p.isActive) continue;
    if (p.source == 'email') continue;
    final m = searchMatch(p, query, distanceKm: p.distanceKm);
    if (m.tier <= 0) continue;
    // Tier 1-4 (brand matches): always include regardless of base score
    // Tier 5+ (title/tag/taxonomy): require minimum quality
    if (m.tier <= 4 || p.rankBaseScore >= 40) scored[p] = m;
  }
  if (scored.isEmpty) return [];

  // Group by brand
  final brandMap = <String, List<MapEntry<Promotion, ({double score, int tier})>>>{};
  for (final e in scored.entries) {
    brandMap.putIfAbsent(e.key.brand, () => []).add(e);
  }

  final groups = brandMap.entries.map((e) {
    final entries = List.of(e.value)
      ..sort((a, b) => b.value.score.compareTo(a.value.score));
    final best = entries.first.value;
    final contexts = <String>{};
    for (final p in entries.map((x) => x.key)) {
      contexts.addAll(dealContextLabels(p));
    }
    return BrandGroup(
      brand: e.key,
      deals: entries.map((x) => x.key).toList(),
      bestTier: best.tier,
      bestScore: best.score,
      contexts: contexts.toList(),
    );
  }).toList()
    ..sort((a, b) => b.bestScore.compareTo(a.bestScore));

  return groups;
}

// ── Context labels ────────────────────────────────────────────────────────────
List<String> dealContextLabels(Promotion p) {
  if (p.promotionType == 'reward' || p.promotionType == 'membership_benefit') {
    return ['Rewards'];
  }
  final labels = <String>[];
  final isOnline = p.redemptionMethod == 'online' ||
      (p.redemptionMethod == 'show_code' && p.dealScope == 'online_only');
  if (isOnline) labels.add('Online');
  const nearMeRedemption = {'in_store', 'in_app', 'app_reward', 'show_code', 'open_maps'};
  if (nearMeRedemption.contains(p.redemptionMethod) && p.dealScope != 'online_only') {
    labels.add('Near Me');
  }
  if (labels.isEmpty) labels.add('Online');
  return labels;
}

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9 ]"), '').trim();
