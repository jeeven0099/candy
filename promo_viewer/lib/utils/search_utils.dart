import '../models/promotion.dart';
import '../models/user_prefs.dart';
import '../services/interaction_service.dart';
import 'feed_ranker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Context chips & options
// ─────────────────────────────────────────────────────────────────────────────

enum SearchContext { forYou, nearMe, online, rewards, freeBogo, saved }

class SearchOptions {
  final Set<String> memberships;
  final Set<String> savedIds;
  final SearchContext context;
  final double minConfidence;

  const SearchOptions({
    this.memberships  = const {},
    this.savedIds     = const {},
    this.context      = SearchContext.forYou,
    this.minConfidence = 0.65,
  });

  SearchOptions copyWith({SearchContext? context, double? minConfidence, Set<String>? savedIds}) =>
      SearchOptions(
        memberships:   memberships,
        savedIds:      savedIds      ?? this.savedIds,
        context:       context       ?? this.context,
        minConfidence: minConfidence ?? this.minConfidence,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Exclusion & context predicates
// ─────────────────────────────────────────────────────────────────────────────

// Membership + active check — no confidence gate (callers apply separately).
bool _passesBasicExclusion(Promotion p, SearchOptions opts) {
  if (!p.isActive) return false;
  if (p.requiresMembership) {
    final cost = (p.membershipCost ?? '').toLowerCase();
    final isPaid = cost.contains('paid') ||
        cost.contains('annual') ||
        cost.contains('subscription');
    if (isPaid) {
      final brand = p.brand.toLowerCase();
      final name  = (p.membershipName ?? '').toLowerCase();
      final ok = opts.memberships.any((m) {
        final ml = m.toLowerCase();
        return ml.contains(brand) || brand.contains(ml) ||
            (name.isNotEmpty && (ml.contains(name) || name.contains(ml)));
      });
      if (!ok) return false;
    }
  }
  return true;
}

// Full exclusion including confidence gate — used by getContextDeals and external callers.
bool passesExclusion(Promotion p, SearchOptions opts) {
  if (!_passesBasicExclusion(p, opts)) return false;
  return p.confidenceScore >= opts.minConfidence;
}

bool passesContext(Promotion p, SearchContext ctx, Set<String> savedIds) {
  switch (ctx) {
    case SearchContext.forYou:
      return true;
    case SearchContext.nearMe:
      if (p.dealScope == 'online_only') return false;
      const nearMeTypes = {'in_store', 'in_app', 'app_reward', 'show_code', 'open_maps'};
      return nearMeTypes.contains(p.redemptionMethod);
    case SearchContext.online:
      return p.redemptionMethod == 'online' ||
          p.dealScope == 'online_only' ||
          p.redemptionMethod == 'show_code';
    case SearchContext.rewards:
      return p.promotionType == 'reward' ||
          p.promotionType == 'membership_benefit';
    case SearchContext.freeBogo:
      return p.discountType == 'free_item' || p.promotionType == 'bogo';
    case SearchContext.saved:
      return savedIds.contains(p.id);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Brand aliases
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, List<String>> kBrandAliases = {
  "McDonald's":             ['mcdonalds', 'mcd', 'mickey d'],
  "Chick-fil-A":            ['chick fil a', 'chickfila', 'chick fil', 'cfa'],
  "Bath & Body Works":      ['bath body', 'bbw', 'bath and body', 'bath and body works'],
  "Dunkin":                 ['dunkin donuts'],
  "T.J.Maxx":               ['tj maxx', 'tjmaxx'],
  "L.L.Bean":               ['ll bean', 'llbean'],
  "Popeyes":                ['popeyes louisiana', 'popeye'],
  "Taco Bell":              ['tacobell'],
  "Burger King":            ['bk'],
  "Pizza Hut":              ['pizzahut'],
  "Domino's":               ['dominos'],
  "Papa Johns":             ['papa johns', "papa john's", 'papajohns'],
  "Panda Express":          ['panda'],
  "Panera Bread":           ['panera'],
  "Chipotle":               ['chipotle mexican'],
  "Five Guys":              ['five guys burgers'],
  "Jack in the Box":        ['jack in box', 'jitb'],
  "Shake Shack":            ['shakeshack'],
  "Whataburger":            ['whata'],
  "Krispy Kreme":           ['krispy'],
  "Dairy Queen":            ['dq'],
  "Cold Stone Creamery":    ['cold stone'],
  "Smoothie King":          ['smoothie king'],
  "Jamba":                  ['jamba juice'],
  "Wingstop":               ['wing stop'],
  "Buffalo Wild Wings":     ['bdubs', 'bww', 'buffalo wild'],
  "Red Lobster":            ['red lobster'],
  "Outback Steakhouse":     ['outback'],
  "Texas Roadhouse":        ['texas road'],
  "Cracker Barrel":         ['cracker barrel'],
  "The North Face":         ['north face', 'tnf'],
  "Sephora":                ['sephora'],
  "Ulta Beauty":            ['ulta'],
  "e.l.f. Cosmetics":       ['elf', 'elf cosmetics', 'elf beauty'],
  "IL MAKIAGE":             ['ilmakiage', 'il makiage'],
  "ColourPop":              ['colorpop', 'colour pop'],
  "Sally Beauty":           ['sally'],
  "Dick's Sporting Goods":  ['dicks', 'dsg'],
  "Sam's Club":             ['sams club', 'samsclub'],
  "BJ's Wholesale Club":    ['bjs', "bj's", 'bj wholesale'],
  "Costco":                 ['costco wholesale'],
  "Whole Foods Market":     ['whole foods'],
  "Trader Joe's":           ['trader joes'],
  "H-E-B":                  ['heb'],
  "Kroger":                 ['kroger'],
  "Publix":                 ['publix'],
  "Safeway":                ['safeway'],
  "Albertsons":             ['albertsons'],
  "Wegmans":                ['wegmans'],
  "Starbucks":              ['sbux', 'starbucks coffee'],
  "Dutch Bros":             ['dutch brothers'],
  "Peet's Coffee":          ['peets'],
  "Ann Taylor":             ['ann taylor loft'],
  "White House Black Market":['whbm'],
  "Banana Republic":        ['br'],
  "Abercrombie & Fitch":    ['abercrombie', 'a&f', 'anf'],
  "Bloomingdale's":         ['bloomingdales'],
  "Macy's":                 ['macys'],
  "Kate Spade":             ['katespade', 'kate spade new york'],
  "Michael Kors":           ['mk'],
  "Tory Burch":             ['tory'],
  "Coach":                  ['coach outlet'],
  "AMC Theatres":           ['amc', 'amc theater'],
  "Cinemark":               ['cinemark theaters'],
  "Regal":                  ['regal cinemas'],
  "Fandango":               ['fandango'],
  "Delta Air Lines":        ['delta'],
  "Southwest Airlines":     ['southwest'],
  "JetBlue":                ['jet blue'],
  "Spirit Airlines":        ['spirit'],
  "Frontier Airlines":      ['frontier'],
  "Enterprise":             ['enterprise rent a car'],
  "Avis":                   ['avis car rental'],
  "Marriott":               ['marriott hotels', 'marriott bonvoy'],
  "Hilton":                 ['hilton hotels'],
  "Wyndham Hotels":         ['wyndham'],
  "Raising Cane's":         ['canes', "cane's", 'raising canes'],
  "Little Caesars":         ['little caesars pizza'],
  "Tropical Smoothie Cafe": ['tropical smoothie', 'tsc'],
  "Baskin-Robbins":         ['baskin robbins', 'baskin'],
  "Qdoba":                  ['qdoba mexican eats'],
  "Moe's Southwest Grill":  ['moes', "moe's"],
  "El Pollo Loco":          ['el pollo', 'epl'],
  "Church's Chicken":       ['churches chicken', 'church chicken'],
  "Hardee's":               ['hardees'],
  "LongHorn Steakhouse":    ['longhorn'],
  "P.F. Chang's":           ['pf changs', 'pfchangs'],
  "MAC Cosmetics":          ['mac makeup', 'mac beauty'],
  "NYX Professional Makeup":['nyx cosmetics', 'nyx makeup', 'nyx'],
  "Too Faced":              ['too faced cosmetics'],
  "Charlotte Tilbury":      ['ct beauty'],
  "Fenty Beauty":           ['fenty'],
  "The Ordinary":           ['theordinary', 'ordinary deciem'],
  "Kiehl's":                ['kiehls'],
  "NARS":                   ['nars cosmetics'],
  "Benefit Cosmetics":      ['benefit'],
  "UGG":                    ['ugg boots'],
  "Timberland":             ['timberlands'],
  "New Balance":            ['nb', 'newbalance'],
  "Reebok":                 ['reebok shoes'],
  "Hoka":                   ['hoka one one', 'hoka shoes'],
  "Asics":                  ['asics running'],
  "Aldo":                   ['aldo shoes'],
  "Clarks":                 ['clarks shoes', 'clarks originals'],
  "Sperry":                 ['sperry topsider'],
  "Hey Dude":               ['heydude'],
  "Brooks Running":         ['brooks shoes', 'brooks'],
  "Saucony":                ['saucony shoes'],
  "Allbirds":               ['all birds'],
  "Home Depot":             ['the home depot', 'homedepot'],
  "Lowe's":                 ['lowes'],
  "Ace Hardware":           ['ace'],
  "GameStop":               ['game stop', 'gs'],
  "B&H Photo":              ['b&h', 'bandh', 'b and h'],
  "Micro Center":           ['microcenter'],
  "Adorama":                ['adorama camera'],
};

// ─────────────────────────────────────────────────────────────────────────────
// Brand product tags
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, List<String>> kBrandProductTags = {
  'Coach':              ['handbags', 'bags', 'wallets', 'purses', 'leather goods', 'accessories', 'totes'],
  'Kate Spade':         ['handbags', 'bags', 'wallets', 'purses', 'accessories', 'totes'],
  'Michael Kors':       ['handbags', 'bags', 'wallets', 'purses', 'watches', 'accessories', 'totes'],
  'Tory Burch':         ['handbags', 'bags', 'wallets', 'purses', 'shoes', 'sandals', 'accessories'],
  'Rebecca Minkoff':    ['handbags', 'bags', 'wallets', 'purses', 'backpacks', 'accessories'],
  'Vera Bradley':       ['bags', 'totes', 'backpacks', 'purses', 'luggage', 'accessories'],
  'BCBG':               ['handbags', 'bags', 'dresses', 'clothing', 'formal wear', 'accessories'],
  'Fossil':             ['watches', 'wallets', 'bags', 'jewelry', 'accessories', 'smartwatches'],
  'Kendra Scott':       ['jewelry', 'necklaces', 'earrings', 'rings', 'bracelets', 'accessories'],
  'Tumi':               ['luggage', 'bags', 'backpacks', 'travel bags', 'suitcases', 'carry-on'],
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
  'Merrell':            ['shoes', 'hiking shoes', 'boots', 'outdoor footwear', 'footwear'],
  'Nike':               ['sneakers', 'shoes', 'athletic shoes', 'footwear', 'activewear', 'sportswear'],
  'Adidas':             ['sneakers', 'shoes', 'athletic shoes', 'footwear', 'activewear', 'sportswear'],
  'Puma':               ['sneakers', 'shoes', 'athletic shoes', 'footwear', 'activewear'],
  'Under Armour':       ['sneakers', 'shoes', 'activewear', 'workout clothes', 'athletic wear'],
  'Reebok':             ['sneakers', 'shoes', 'athletic shoes', 'footwear', 'activewear'],
  'Lululemon':          ['activewear', 'yoga pants', 'leggings', 'workout clothes', 'sports bras'],
  'Fabletics':          ['activewear', 'leggings', 'workout clothes', 'athletic wear', 'sports bras'],
  'Gymshark':           ['activewear', 'gym wear', 'workout clothes', 'leggings'],
  'Alo Yoga':           ['activewear', 'yoga pants', 'leggings', 'workout clothes'],
  'Vuori':              ['activewear', 'workout clothes', 'athletic wear', 'shorts'],
  'Columbia':           ['outdoor clothing', 'jackets', 'activewear', 'hiking gear'],
  'The North Face':     ['outdoor clothing', 'jackets', 'activewear', 'hiking gear', 'coats'],
  'Patagonia':          ['outdoor clothing', 'jackets', 'activewear', 'outdoor gear'],
  'Eddie Bauer':        ['outdoor clothing', 'jackets', 'coats', 'outdoor gear'],
  'L.L.Bean':           ['outdoor clothing', 'boots', 'backpacks', 'bags', 'outdoor gear'],
  'Madewell':           ['jeans', 'denim', 'clothing', 'dresses', 'basics'],
  'Lee':                ['jeans', 'denim', 'work clothes', 'pants'],
  'Wrangler':           ['jeans', 'denim', 'western wear', 'pants'],
  'Lucky Brand':        ['jeans', 'denim', 'clothing'],
  'American Eagle':     ['jeans', 'denim', 'clothing', 'basics', 'activewear'],
  'Aerie':              ['underwear', 'bras', 'activewear', 'swimwear', 'loungewear'],
  'Gap':                ['jeans', 'denim', 'basics', 'clothing', 'activewear'],
  'Old Navy':           ['jeans', 'clothing', 'basics', 'activewear', 'kids clothes'],
  'Ann Taylor':         ['work clothes', 'dresses', 'office wear', 'business casual'],
  'LOFT':               ['work clothes', 'dresses', 'office wear', 'business casual'],
  'Banana Republic':    ['work clothes', 'suits', 'blazers', 'dresses', 'office wear'],
  'Brooks Brothers':    ['suits', 'dress shirts', 'work clothes', 'office wear'],
  'White House Black Market': ['dresses', 'work clothes', 'office wear', 'clothing'],
  'J.Crew':             ['clothing', 'work clothes', 'dresses', 'jeans', 'knitwear'],
  'Ulta Beauty':        ['makeup', 'cosmetics', 'skincare', 'haircare', 'beauty'],
  'Sephora':            ['makeup', 'cosmetics', 'skincare', 'fragrance', 'beauty'],
  'e.l.f. Cosmetics':   ['makeup', 'cosmetics', 'skincare', 'beauty', 'affordable beauty'],
  'ColourPop':          ['makeup', 'cosmetics', 'lipstick', 'eyeshadow', 'beauty'],
  'IL MAKIAGE':         ['makeup', 'foundation', 'cosmetics', 'beauty'],
  'Prose':              ['hair', 'haircare', 'shampoo', 'conditioner', 'skincare'],
  'Function of Beauty': ['hair', 'haircare', 'shampoo', 'conditioner'],
  'The Body Shop':      ['skincare', 'body care', 'beauty', 'cruelty free'],
  'Bath & Body Works':  ['body care', 'candles', 'fragrance', 'lotion', 'beauty'],
  'Sally Beauty':       ['hair color', 'haircare', 'professional hair', 'beauty'],
  'AMC Theatres':       ['movies', 'cinema', 'film', 'entertainment', 'tickets'],
  'Cinemark':           ['movies', 'cinema', 'film', 'entertainment', 'tickets'],
  'Regal':              ['movies', 'cinema', 'film', 'entertainment', 'tickets'],
  'Fandango':           ['movies', 'cinema', 'tickets', 'entertainment'],
  'Delta Air Lines':    ['flights', 'airlines', 'travel', 'airfare'],
  'Southwest Airlines': ['flights', 'airlines', 'travel', 'airfare'],
  'JetBlue':            ['flights', 'airlines', 'travel', 'airfare'],
  'Spirit Airlines':    ['flights', 'airlines', 'travel', 'airfare', 'budget flights'],
  'Frontier Airlines':  ['flights', 'airlines', 'travel', 'airfare', 'budget flights'],
  'Marriott':           ['hotel', 'hotels', 'travel', 'accommodation', 'vacation'],
  'Hilton':             ['hotel', 'hotels', 'travel', 'accommodation', 'vacation'],
  'Wyndham Hotels':     ['hotel', 'hotels', 'travel', 'accommodation', 'vacation'],
  'Choice Hotels':      ['hotel', 'hotels', 'travel', 'accommodation', 'vacation'],
  'Enterprise':         ['car rental', 'rental car', 'travel', 'transportation'],
  'Avis':               ['car rental', 'rental car', 'travel', 'transportation'],
  'Dick\'s Sporting Goods': ['sports', 'sporting goods', 'outdoor', 'fitness', 'exercise'],
  'REI':                ['outdoor', 'hiking', 'camping', 'sporting goods', 'adventure gear'],
  'Best Buy':           ['electronics', 'tech', 'computers', 'laptops', 'tvs', 'gadgets'],
  'Newegg':             ['electronics', 'tech', 'computers', 'components', 'pc parts'],
  'MAC Cosmetics':      ['makeup', 'cosmetics', 'foundation', 'lipstick', 'beauty'],
  'Urban Decay':        ['makeup', 'cosmetics', 'eyeshadow', 'beauty', 'eyeshadow palette'],
  'Tarte Cosmetics':    ['makeup', 'cosmetics', 'beauty', 'skincare', 'foundation'],
  'NYX Professional Makeup': ['makeup', 'cosmetics', 'beauty', 'lipstick', 'affordable beauty'],
  'Too Faced':          ['makeup', 'cosmetics', 'beauty', 'mascara', 'eyeshadow'],
  'Charlotte Tilbury':  ['makeup', 'cosmetics', 'skincare', 'beauty', 'luxury beauty'],
  'Fenty Beauty':       ['makeup', 'cosmetics', 'beauty', 'foundation', 'skincare'],
  'The Ordinary':       ['skincare', 'serums', 'beauty', 'retinol', 'vitamin c'],
  'Kiehl\'s':           ['skincare', 'beauty', 'moisturizer', 'cleanser', 'body care'],
  'NARS':               ['makeup', 'cosmetics', 'beauty', 'blush', 'foundation'],
  'Benefit Cosmetics':  ['makeup', 'cosmetics', 'beauty', 'brows', 'mascara'],
  'Clinique':           ['skincare', 'beauty', 'makeup', 'moisturizer', 'cosmetics'],
  'Steve Madden':       ['shoes', 'boots', 'sandals', 'heels', 'sneakers', 'footwear'],
  'UGG':                ['boots', 'shoes', 'slippers', 'sandals', 'footwear'],
  'Timberland':         ['boots', 'shoes', 'outdoor footwear', 'work boots', 'footwear'],
  'New Balance':        ['sneakers', 'running shoes', 'athletic shoes', 'shoes', 'footwear'],
  'Hoka':               ['running shoes', 'sneakers', 'athletic shoes', 'trail shoes', 'footwear'],
  'Asics':              ['running shoes', 'sneakers', 'athletic shoes', 'shoes', 'footwear'],
  'Aldo':               ['shoes', 'heels', 'boots', 'sandals', 'accessories', 'footwear'],
  'Clarks':             ['shoes', 'boots', 'sandals', 'comfort shoes', 'footwear'],
  'Sperry':             ['shoes', 'boat shoes', 'boots', 'sandals', 'footwear'],
  'Hey Dude':           ['shoes', 'casual shoes', 'loafers', 'slip-on', 'footwear'],
  'Brooks Running':     ['running shoes', 'sneakers', 'athletic shoes', 'footwear'],
  'Saucony':            ['running shoes', 'sneakers', 'athletic shoes', 'footwear'],
  'Allbirds':           ['shoes', 'sneakers', 'sustainable shoes', 'footwear'],
  'Home Depot':         ['tools', 'hardware', 'home improvement', 'appliances', 'garden'],
  'Lowe\'s':            ['tools', 'hardware', 'home improvement', 'appliances', 'garden'],
  'Ace Hardware':       ['tools', 'hardware', 'home improvement', 'paint'],
  'Menards':            ['tools', 'hardware', 'home improvement', 'building materials'],
  'GameStop':           ['video games', 'gaming', 'consoles', 'ps5', 'xbox', 'nintendo'],
  'Micro Center':       ['computers', 'pc parts', 'electronics', 'tech', 'components'],
  'B&H Photo':          ['cameras', 'photography', 'electronics', 'tech', 'lenses'],
  'Adorama':            ['cameras', 'photography', 'electronics', 'tech', 'lenses'],
};

// ─────────────────────────────────────────────────────────────────────────────
// Search taxonomy  (item query → brands)
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, Map<String, List<String>>> kSearchTaxonomy = {
  // ── Food ──────────────────────────────────────────────────────────────────
  'burgers': {
    'aliases': ['burger', 'cheeseburger', 'hamburger', 'whopper', 'big mac'],
    'brands':  ["Burger King", "McDonald's", "Wendy's", "Five Guys", "Shake Shack", "Whataburger", "Sonic Drive-In"],
  },
  'pizza': {
    'aliases': ['pizzas', 'slice', 'pie', 'pepperoni', 'calzone'],
    'brands':  ["Domino's", "Pizza Hut", "Papa Johns", "Little Caesars"],
  },
  'coffee': {
    'aliases': ['latte', 'espresso', 'cold brew', 'cappuccino', 'americano', 'iced coffee', 'drink'],
    'brands':  ["Starbucks", "Dunkin", "Dutch Bros", "Peet's Coffee", "Caribou Coffee", "Black Rock Coffee Bar", "Einstein Bros Bagels"],
  },
  'tacos': {
    'aliases': ['taco', 'burrito', 'quesadilla', 'mexican food', 'tex mex'],
    'brands':  ["Taco Bell", "Chipotle", "Del Taco", "Moe's Southwest Grill"],
  },
  'chicken': {
    'aliases': ['fried chicken', 'chicken sandwich', 'nuggets', 'tenders'],
    'brands':  ["Chick-fil-A", "Popeyes", "KFC", "Raising Cane's", "Church's Chicken", "El Pollo Loco", "Hardee's"],
  },
  'wings': {
    'aliases': ['wing', 'boneless wings', 'buffalo wings'],
    'brands':  ["Wingstop", "Buffalo Wild Wings", "Hooters"],
  },
  'sandwiches': {
    'aliases': ['sandwich', 'sub', 'hoagie', 'wrap', 'grinder'],
    'brands':  ["Subway", "Jimmy John's", "Jersey Mike's", "Firehouse Subs", "Potbelly"],
  },
  'breakfast': {
    'aliases': ['pancakes', 'waffles', 'eggs', 'brunch', 'omelette'],
    'brands':  ["IHOP", "Denny's", "Cracker Barrel", "McDonald's", "Dunkin", "Einstein Bros Bagels"],
  },
  'ice cream': {
    'aliases': ['icecream', 'gelato', 'frozen yogurt', 'blizzard', 'sundae', 'milkshake'],
    'brands':  ["Dairy Queen", "Baskin-Robbins", "Cold Stone Creamery", "Carvel"],
  },
  'donuts': {
    'aliases': ['donut', 'doughnut', 'pastry'],
    'brands':  ["Dunkin", "Krispy Kreme"],
  },
  'smoothies': {
    'aliases': ['smoothie', 'juice', 'acai', 'blend'],
    'brands':  ["Jamba", "Smoothie King", "Tropical Smoothie Cafe"],
  },
  'steak': {
    'aliases': ['steakhouse', 'ribeye', 'sirloin', 'bbq', 'grill'],
    'brands':  ["Outback Steakhouse", "Texas Roadhouse", "LongHorn Steakhouse", "Applebee's", "TGI Fridays"],
  },
  'groceries': {
    'aliases': ['grocery', 'supermarket', 'food shopping', 'produce', 'fresh food', 'weekly ad'],
    'brands':  ["H-E-B", "Kroger", "Whole Foods Market", "Trader Joe's", "Costco", "Sam's Club", "Aldi", "Sprouts", "Publix", "Safeway", "Albertsons", "Food Lion", "Giant Food", "Stop & Shop", "Wegmans", "BJ's Wholesale Club", "Walmart", "Target"],
  },
  'gas': {
    'aliases': ['gasoline', 'fuel', 'petrol', 'fill up', 'gas station'],
    'brands':  ["Shell", "Exxon Mobil", "BP", "Chevron"],
  },
  // ── Movies & Entertainment ─────────────────────────────────────────────────
  'movies': {
    'aliases': ['movie', 'cinema', 'theater', 'theatre', 'film', 'tickets', 'screening'],
    'brands':  ["AMC Theatres", "Cinemark", "Regal", "Fandango"],
  },
  // ── Travel ────────────────────────────────────────────────────────────────
  'travel': {
    'aliases': ['flight', 'flights', 'hotel', 'hotels', 'rental car', 'airline', 'airlines', 'vacation', 'trip'],
    'brands':  ["Delta Air Lines", "Southwest Airlines", "JetBlue", "Spirit Airlines", "Frontier Airlines", "Marriott", "Hilton", "Wyndham Hotels", "Choice Hotels", "Enterprise", "Avis"],
  },
  'flights': {
    'aliases': ['flight', 'airfare', 'airline', 'fly', 'plane'],
    'brands':  ["Delta Air Lines", "Southwest Airlines", "JetBlue", "Spirit Airlines", "Frontier Airlines"],
  },
  'hotels': {
    'aliases': ['hotel', 'motel', 'stay', 'lodging', 'accommodation', 'resort'],
    'brands':  ["Marriott", "Hilton", "Wyndham Hotels", "Choice Hotels"],
  },
  // ── Fashion ───────────────────────────────────────────────────────────────
  'jeans': {
    'aliases': ['jean', 'denim', 'pants', 'trousers'],
    'brands':  ["Old Navy", "Gap", "American Eagle", "Abercrombie & Fitch", "Hollister", "Lee", "Wrangler", "Lucky Brand", "Madewell", "Calvin Klein", "Tommy Hilfiger"],
  },
  'shoes': {
    'aliases': ['shoe', 'footwear', 'boots', 'sandals', 'flats', 'heels', 'loafers'],
    'brands':  ["Nike", "Skechers", "Puma", "Under Armour", "Dr. Martens", "Merrell", "Cole Haan", "Nine West", "Sam Edelman", "Stuart Weitzman", "DSW", "Famous Footwear", "Steve Madden", "UGG", "Aldo", "Clarks", "Sperry", "Hey Dude", "Hoka", "Asics", "Allbirds"],
  },
  'sneakers': {
    'aliases': ['sneaker', 'athletic shoes', 'running shoes', 'trainers', 'kicks'],
    'brands':  ["Nike", "Adidas", "Foot Locker", "Finish Line", "Champs Sports", "Reebok", "Puma", "New Balance", "Hoka", "Asics", "Brooks Running", "Saucony", "Allbirds"],
  },
  'handbags': {
    'aliases': ['handbag', 'bag', 'purse', 'wallet', 'tote', 'crossbody', 'clutch', 'shoulder bag'],
    'brands':  ["Coach", "Kate Spade", "Michael Kors", "Tory Burch", "Rebecca Minkoff", "Vera Bradley", "Guess"],
  },
  'activewear': {
    'aliases': ['gym clothes', 'workout clothes', 'yoga pants', 'leggings', 'athletic wear'],
    'brands':  ["Nike", "Adidas", "Lululemon", "Under Armour", "Fabletics", "Gymshark", "Alo Yoga"],
  },
  'dresses': {
    'aliases': ['dress', 'gown', 'sundress', 'midi', 'maxi', 'formal wear'],
    'brands':  ["BCBG", "Ann Taylor", "LOFT", "White House Black Market", "Ted Baker", "Lilly Pulitzer"],
  },
  'suits': {
    'aliases': ['suit', 'blazer', 'business wear', 'office wear', 'work clothes'],
    'brands':  ["Brooks Brothers", "Banana Republic", "Theory"],
  },
  'outdoor': {
    'aliases': ['hiking', 'camping', 'outdoor gear', 'trail', 'adventure'],
    'brands':  ["Patagonia", "The North Face", "Columbia", "Eddie Bauer", "L.L.Bean", "Merrell"],
  },
  // ── Beauty ────────────────────────────────────────────────────────────────
  'makeup': {
    'aliases': ['cosmetics', 'foundation', 'lipstick', 'mascara', 'eyeshadow', 'blush', 'beauty'],
    'brands':  ["Ulta Beauty", "Sephora", "ColourPop", "e.l.f. Cosmetics", "IL MAKIAGE", "MAC Cosmetics", "Urban Decay", "Tarte Cosmetics", "NYX Professional Makeup", "Too Faced", "NARS", "Benefit Cosmetics", "Fenty Beauty"],
  },
  'skincare': {
    'aliases': ['moisturizer', 'serum', 'sunscreen', 'cleanser', 'face wash', 'skin care'],
    'brands':  ["Ulta Beauty", "Sephora", "e.l.f. Cosmetics", "Prose", "Function of Beauty", "The Body Shop", "The Ordinary", "Kiehl's", "Charlotte Tilbury", "Clinique", "Tarte Cosmetics"],
  },
  'fragrance': {
    'aliases': ['perfume', 'cologne', 'scent', 'body spray'],
    'brands':  ["Sephora", "Ulta Beauty", "Bath & Body Works"],
  },
  'hair': {
    'aliases': ['shampoo', 'conditioner', 'hair color', 'hair care', 'salon', 'haircare'],
    'brands':  ["Ulta Beauty", "Sally Beauty", "Prose", "Function of Beauty"],
  },
  // ── Tech & Home ───────────────────────────────────────────────────────────
  'electronics': {
    'aliases': ['laptop', 'computer', 'phone', 'tv', 'headphones', 'tablet', 'tech'],
    'brands':  ["Best Buy", "Dell", "Newegg", "Micro Center", "B&H Photo", "Adorama"],
  },
  'cameras': {
    'aliases': ['camera', 'photography', 'lens', 'dslr', 'mirrorless', 'photo gear'],
    'brands':  ["B&H Photo", "Adorama"],
  },
  'home': {
    'aliases': ['furniture', 'decor', 'sofa', 'couch', 'home goods', 'kitchen'],
    'brands':  ["IKEA", "West Elm"],
  },
  'home improvement': {
    'aliases': ['hardware', 'tools', 'power tools', 'paint', 'garden', 'building', 'renovation', 'diy'],
    'brands':  ["Home Depot", "Lowe's", "Ace Hardware", "Menards"],
  },
  'gaming': {
    'aliases': ['video games', 'game', 'ps5', 'playstation', 'xbox', 'nintendo', 'console', 'switch'],
    'brands':  ["GameStop"],
  },
};

// ─────────────────────────────────────────────────────────────────────────────
// Search scoring
// ─────────────────────────────────────────────────────────────────────────────

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9 ]"), '').trim();

/// Returns (score, tier) for a promotion against a query.
/// tier=0 means no match — exclude from results.
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
    // Alias exact match (+90) or starts-with (+70)
    for (final entry in kBrandAliases.entries) {
      if (_norm(entry.key) == brand) {
        for (final alias in entry.value) {
          final na = _norm(alias);
          if (na == q) {
            score += 90; tier = 3; break;
          } else if (na.startsWith(q)) {
            score += 70; tier = 3; break;
          }
        }
        break;
      }
    }
    if (tier == 0 && brand.contains(q)) {
      score += 60; tier = 4;
    }
  }

  // ── Taxonomy match ────────────────────────────────────────────────────────
  if (tier == 0) {
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

  // ── Title / summary / tag / category matching ─────────────────────────────
  final titleNorm = _norm(p.title);
  if (titleNorm.contains(q)) {
    score += 50;
    if (tier == 0) tier = 5;
  }
  if (p.summary != null && _norm(p.summary!).contains(q)) {
    score += 35;
    if (tier == 0) tier = 6;
  }
  // Promo code exact
  if (p.promoCode != null && _norm(p.promoCode!) == q) {
    score += 70;
    if (tier == 0) tier = 3;
  }
  if (tier == 0) {
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
  if (_norm(p.category).contains(q)) {
    score += 20;
    if (tier == 0) tier = 7;
  }

  if (tier == 0) return (score: 0, tier: 0);

  // ── Secondary boosts (tiebreakers only) ───────────────────────────────────
  score += (p.globalQualityScore.clamp(0.0, 100.0) / 100.0) * 25;

  if (distanceKm != null) {
    final miles = distanceKm * 0.621371;
    if (miles <= 0.5)       { score += 15; }
    else if (miles <= 1.0)  { score += 12; }
    else if (miles <= 2.0)  { score += 8; }
    else if (miles <= 5.0)  { score += 4; }
    else                    { score += 1; }
  }

  return (score: score, tier: tier);
}

// ─────────────────────────────────────────────────────────────────────────────
// BrandGroup
// ─────────────────────────────────────────────────────────────────────────────

class BrandGroup {
  final String brand;
  final List<Promotion> deals;
  final int bestTier;       // tier ≤ 4 = brand match; used for brand-affinity recording
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

// ─────────────────────────────────────────────────────────────────────────────
// runSearch  — query-driven, grouped by brand
// ─────────────────────────────────────────────────────────────────────────────

List<BrandGroup> runSearch(
  List<Promotion> all,
  String query, [
  SearchOptions opts = const SearchOptions(),
]) {
  if (query.trim().isEmpty) return [];

  final scored = <Promotion, ({double score, int tier})>{};
  for (final p in all) {
    if (!_passesBasicExclusion(p, opts)) continue;
    final m = searchMatch(p, query, distanceKm: p.distanceKm);
    if (m.tier <= 0) continue;
    // Tier-aware confidence: exact brand/alias matches (tier ≤3) use 0.5 so the
    // user who types "Coach" always sees Coach deals even if confidence is 0.55.
    // Semantic/tag matches use opts.minConfidence (default 0.65).
    final confMin = m.tier <= 3 ? 0.5 : opts.minConfidence;
    if (p.confidenceScore < confMin) continue;
    if (!passesContext(p, opts.context, opts.savedIds)) continue;
    // Tier 1-4 (brand matches): always include. Tier 5+ (semantic): require quality.
    if (m.tier <= 4 || p.globalQualityScore >= 40) scored[p] = m;
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
      brand:     e.key,
      deals:     entries.map((x) => x.key).toList(),
      bestTier:  best.tier,
      bestScore: best.score,
      contexts:  contexts.toList(),
    );
  }).toList()
    ..sort((a, b) => b.bestScore.compareTo(a.bestScore));

  return groups;
}

// ─────────────────────────────────────────────────────────────────────────────
// getContextDeals  — no-query context chip → top deals grouped by brand
// ─────────────────────────────────────────────────────────────────────────────

List<BrandGroup> getContextDeals(
  List<Promotion> all,
  SearchOptions opts, {
  int maxBrands = 15,
  // Two-level params (preferred path):
  InteractionService? svc,
  UserPrefs? prefs,
  double? radiusMi, // Near Me radius filter in miles
}) {
  final filtered = all.where((p) =>
      passesExclusion(p, opts) && passesContext(p, opts.context, opts.savedIds)).toList();

  // ── Two-level path ──────────────────────────────────────────────────────────
  // Level 1: brandLevelScore determines which brand card appears first.
  // Level 2: dealQualityScore determines deal order within each brand card.
  if (svc != null) {
    // Near Me: pre-filter deals outside the user's radius
    final eligible = (opts.context == SearchContext.nearMe && radiusMi != null)
        ? filtered.where((p) {
            if (p.distanceKm == null) return false;
            return (p.distanceKm! * 0.621371) <= radiusMi;
          }).toList()
        : filtered;

    // Group by brand
    final brandMap = <String, List<Promotion>>{};
    for (final p in eligible) {
      brandMap.putIfAbsent(p.brand, () => []).add(p);
    }

    final groups = <BrandGroup>[];
    for (final entry in brandMap.entries) {
      final brand = entry.key;
      final deals = entry.value;

      // Level 2: sort deals within brand by deal quality (no brand/cat boost here)
      final scored = deals
          .map((p) => (p, dealQualityScore(p, svc, distanceKm: p.distanceKm, prefs: prefs)))
          .where((t) => t.$2 > -500)
          .toList()
        ..sort((a, b) => b.$2.compareTo(a.$2));

      if (scored.isEmpty) continue;

      // Level 1: brand card score (fav brand/cat, recent search, deal count)
      final bScore = brandLevelScore(brand, deals.first.category, deals, svc, prefs: prefs);

      final contexts = <String>{};
      for (final p in scored.map((t) => t.$1)) {
        contexts.addAll(dealContextLabels(p));
      }

      groups.add(BrandGroup(
        brand:     brand,
        deals:     scored.map((t) => t.$1).toList(),
        bestTier:  1,
        bestScore: bScore,
        contexts:  contexts.toList(),
      ));
    }

    groups.sort((a, b) => b.bestScore.compareTo(a.bestScore));
    return groups.take(maxBrands).toList();
  }

  // ── Legacy single-level path (no svc provided) ─────────────────────────────
  double defaultScore(Promotion p) {
    double s = p.globalQualityScore;
    if (opts.context == SearchContext.nearMe && p.distanceKm != null) {
      final miles = p.distanceKm! * 0.621371;
      s += miles <= 0.5 ? 30 : miles <= 1.0 ? 25 : miles <= 2.0 ? 18 : miles <= 5.0 ? 8 : 2;
    }
    return s;
  }

  final valid = filtered.where((p) => defaultScore(p) > -900).toList()
    ..sort((a, b) => defaultScore(b).compareTo(defaultScore(a)));

  final brandMap = <String, List<Promotion>>{};
  for (final p in valid) {
    brandMap.putIfAbsent(p.brand, () => []).add(p);
  }

  final groups = brandMap.entries.map((e) {
    final deals = e.value;
    final contexts = <String>{};
    for (final p in deals) { contexts.addAll(dealContextLabels(p)); }
    return BrandGroup(
      brand:     e.key,
      deals:     deals,
      bestTier:  1,
      bestScore: defaultScore(deals.first),
      contexts:  contexts.toList(),
    );
  }).toList()
    ..sort((a, b) => b.bestScore.compareTo(a.bestScore));

  return groups.take(maxBrands).toList();
}

// ─────────────────────────────────────────────────────────────────────────────
// Related searches (for no-result state)
// ─────────────────────────────────────────────────────────────────────────────

List<String> relatedSearches(String query) {
  final q = _norm(query);
  if (q.isEmpty) return [];
  final suggestions = <String>{};
  for (final entry in kSearchTaxonomy.entries) {
    final key = _norm(entry.key);
    final aliases = entry.value['aliases']!;
    if (key.contains(q) || q.contains(key) ||
        aliases.any((a) => _norm(a).contains(q) || q.contains(_norm(a)))) {
      suggestions.add(entry.key);
    }
  }
  for (final brand in kBrandAliases.keys) {
    final bn = _norm(brand);
    if (bn.contains(q)) suggestions.add(brand);
  }
  return suggestions.take(4).toList();
}

// ─────────────────────────────────────────────────────────────────────────────
// Context labels (used by BrandResultCard chips)
// ─────────────────────────────────────────────────────────────────────────────

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
