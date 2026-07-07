import 'package:shared_preferences/shared_preferences.dart';

const _kPromoteThreshold = 2.0; // weighted interactions before chip floats up

/// Tracks local category affinity from searches and deal clicks.
/// Uses time-decayed weighted counts so interest from months ago doesn't
/// permanently distort the chip order.
class CategoryPrefsService {
  static final CategoryPrefsService _i = CategoryPrefsService._();
  factory CategoryPrefsService() => _i;
  CategoryPrefsService._();

  SharedPreferences? _prefs;

  // Storage key: list of "ISO8601|weight" strings per category
  static const _timesPrefix = 'cat_times_';

  static const baseCategories = [
    'All', 'Food', 'Coffee', 'Retail', 'Fashion', 'Beauty',
    'Tech', 'Home', 'Travel', 'Automotive', 'Grocery',
  ];

  // ── Category resolution ───────────────────────────────────────────────────

  // Search keywords → chip label (checked first)
  static const Map<String, List<String>> _keywords = {
    'Beauty':     ['beauty', 'makeup', 'lipstick', 'foundation', 'skincare', 'serum',
                   'mascara', 'blush', 'perfume', 'fragrance', 'nail', 'eyeshadow', 'concealer'],
    'Coffee':     ['coffee', 'latte', 'espresso', 'cappuccino', 'cold brew', 'brew'],
    'Fashion':    ['fashion', 'clothes', 'clothing', 'dress', 'shirt', 'pants', 'shoes',
                   'sneakers', 'jeans', 'jacket', 'hoodie', 'apparel', 'outfit', 'skirt', 'boots'],
    'Food':       ['food', 'burger', 'pizza', 'sandwich', 'meal', 'restaurant',
                   'lunch', 'dinner', 'sushi', 'taco', 'wings', 'fries'],
    'Tech':       ['tech', 'phone', 'laptop', 'computer', 'tablet', 'headphones',
                   'earbuds', 'gaming', 'electronics', 'camera', 'monitor', 'keyboard'],
    'Home':       ['home', 'furniture', 'decor', 'kitchen', 'bedding', 'appliance',
                   'candle', 'rug', 'curtain', 'towel'],
    'Grocery':    ['grocery', 'groceries', 'supermarket', 'produce', 'organic'],
    'Travel':     ['travel', 'hotel', 'flight', 'airline', 'vacation', 'booking', 'resort'],
    'Automotive': ['car', 'auto', 'automotive', 'gas', 'oil', 'tire', 'vehicle', 'truck'],
    'Retail':     ['retail', 'outlet', 'clearance'],
  };

  // Well-known brand names → chip label (checked second, before result dominance)
  static const Map<String, String> _brandToCategory = {
    // Fashion
    'nike': 'Fashion', 'adidas': 'Fashion', 'lululemon': 'Fashion', 'zara': 'Fashion',
    'h&m': 'Fashion', 'gap': 'Fashion', 'old navy': 'Fashion', 'banana republic': 'Fashion',
    'uniqlo': 'Fashion', 'patagonia': 'Fashion', 'north face': 'Fashion',
    'under armour': 'Fashion', 'reebok': 'Fashion', 'puma': 'Fashion',
    'new balance': 'Fashion', 'vans': 'Fashion', 'converse': 'Fashion',
    'j.crew': 'Fashion', 'calvin klein': 'Fashion', 'tommy hilfiger': 'Fashion',
    'ralph lauren': 'Fashion', 'princess polly': 'Fashion', 'nasty gal': 'Fashion',
    'boohoo': 'Fashion', 'asos': 'Fashion', 'revolve': 'Fashion', 'shein': 'Fashion',
    'nordstrom': 'Fashion', 'macy': 'Fashion', 'gymshark': 'Fashion',
    'fabletics': 'Fashion', 'loft': 'Fashion', 'express': 'Fashion',
    'american eagle': 'Fashion', 'hollister': 'Fashion', 'abercrombie': 'Fashion',
    'windsor': 'Fashion', 'pacsun': 'Fashion', 'urban outfitters': 'Fashion',
    'anthropologie': 'Fashion', 'sam edelman': 'Fashion', 'fossil': 'Fashion',
    'tory burch': 'Fashion', 'kate spade': 'Fashion', 'coach': 'Fashion',
    'burlington': 'Fashion', 'tjmaxx': 'Fashion', 't.j.maxx': 'Fashion',
    'marshalls': 'Fashion', 'ross': 'Fashion',
    // Beauty
    'sephora': 'Beauty', 'ulta': 'Beauty', 'fenty': 'Beauty', 'morphe': 'Beauty',
    'nars': 'Beauty', 'charlotte tilbury': 'Beauty', 'benefit': 'Beauty',
    'glossier': 'Beauty', 'kiehl': 'Beauty', 'tatcha': 'Beauty',
    'the ordinary': 'Beauty', 'cerave': 'Beauty', 'neutrogena': 'Beauty', 'olay': 'Beauty',
    // Tech
    'apple': 'Tech', 'samsung': 'Tech', 'microsoft': 'Tech', 'sony': 'Tech',
    'dell': 'Tech', 'hp': 'Tech', 'lenovo': 'Tech', 'best buy': 'Tech',
    'newegg': 'Tech', 'adorama': 'Tech', 'logitech': 'Tech', 'razer': 'Tech',
    'bose': 'Tech',
    // Food
    'mcdonald': 'Food', 'burger king': 'Food', 'wendy': 'Food', 'chick-fil-a': 'Food',
    'taco bell': 'Food', 'subway': 'Food', 'chipotle': 'Food', "domino": 'Food',
    'pizza hut': 'Food', 'panera': 'Food', 'applebee': 'Food', 'olive garden': 'Food',
    'qdoba': 'Food', 'sonic': 'Food', 'popeye': 'Food', 'five guys': 'Food',
    'shake shack': 'Food', 'chili': 'Food', 'petsmart': 'Food',
    // Coffee
    'starbucks': 'Coffee', 'dunkin': 'Coffee', 'biggby': 'Coffee',
    'peet': 'Coffee', 'caribou': 'Coffee', 'dutch bros': 'Coffee', 'tim horton': 'Coffee',
    // Home
    'west elm': 'Home', 'pottery barn': 'Home', 'ikea': 'Home', 'wayfair': 'Home',
    'williams-sonoma': 'Home', 'williams sonoma': 'Home', 'container store': 'Home',
    // Travel
    'marriott': 'Travel', 'hilton': 'Travel', 'hyatt': 'Travel', 'delta': 'Travel',
    'southwest': 'Travel', 'expedia': 'Travel', 'airbnb': 'Travel',
    'fandango': 'Travel', 'regal': 'Travel',
    // Grocery
    'walmart': 'Grocery', 'kroger': 'Grocery', 'whole foods': 'Grocery',
    'trader joe': 'Grocery', 'costco': 'Grocery', 'publix': 'Grocery',
    // Automotive
    'autozone': 'Automotive', 'advance auto': 'Automotive', 'jiffy lube': 'Automotive',
    'firestone': 'Automotive', 'pep boys': 'Automotive',
  };

  // Maps raw promotion category strings → chip labels
  static const Map<String, String> _rawToLabel = {
    'food': 'Food', 'fast_food': 'Food', 'restaurant': 'Food',
    'coffee': 'Coffee',
    'retail': 'Retail',
    'fashion': 'Fashion', 'clothing': 'Fashion', 'apparel': 'Fashion',
    'beauty': 'Beauty', 'personal_care': 'Beauty',
    'tech': 'Tech', 'electronics': 'Tech',
    'home': 'Home', 'home_goods': 'Home', 'furniture': 'Home',
    'travel': 'Travel', 'hotels': 'Travel', 'airlines': 'Travel',
    'automotive': 'Automotive', 'gas': 'Automotive',
    'grocery': 'Grocery', 'supermarket': 'Grocery',
  };

  /// Resolves a free-text search query to a category chip label.
  /// Order of precedence:
  ///   1. Keyword match (generic terms like "makeup", "sneakers")
  ///   2. Known brand match (avoids "apple" → accidentally Tech when user means Applebee's)
  ///   3. Returns null → caller falls back to result-dominance inference
  String? resolveQueryToCategory(String query) {
    final q = query.toLowerCase().trim();

    // 1. Keyword match
    for (final entry in _keywords.entries) {
      if (entry.value.any((kw) => q.contains(kw))) return entry.key;
    }

    // 2. Brand name match
    for (final entry in _brandToCategory.entries) {
      if (q.contains(entry.key)) return entry.value;
    }

    return null;
  }

  String? rawCategoryToLabel(String raw) => _rawToLabel[raw.toLowerCase()];

  // ── Time-decayed recording ────────────────────────────────────────────────

  Future<void> recordCategoryInterest(String chipLabel, {int weight = 1}) async {
    _prefs ??= await SharedPreferences.getInstance();
    final key = '$_timesPrefix${chipLabel.toLowerCase()}';
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 30));

    // Load, prune old entries, append new one
    final existing = List<String>.from(_prefs!.getStringList(key) ?? []);
    final pruned = existing.where((e) {
      final dt = _parseTimestamp(e);
      return dt != null && dt.isAfter(cutoff);
    }).toList();
    pruned.add('${now.toIso8601String()}|$weight');

    await _prefs!.setStringList(key, pruned);
  }

  // ── Time-decayed weighted count ───────────────────────────────────────────

  /// Returns the weighted affinity score for a chip label.
  /// ≤7 days old: full weight · 8–30 days: 60% · >30 days: pruned/ignored
  double _weightedCount(String chipLabel) {
    final key = '$_timesPrefix${chipLabel.toLowerCase()}';
    final entries = _prefs?.getStringList(key) ?? [];
    final now = DateTime.now();
    double total = 0;
    for (final entry in entries) {
      final dt = _parseTimestamp(entry);
      final w = _parseWeight(entry);
      if (dt == null) continue;
      final ageDays = now.difference(dt).inDays;
      if (ageDays > 30) continue;
      final decay = ageDays <= 7 ? 1.0 : 0.6;
      total += w * decay;
    }
    return total;
  }

  static DateTime? _parseTimestamp(String entry) {
    final sep = entry.lastIndexOf('|');
    if (sep < 0) return null;
    return DateTime.tryParse(entry.substring(0, sep));
  }

  static double _parseWeight(String entry) {
    final sep = entry.lastIndexOf('|');
    if (sep < 0) return 1.0;
    return double.tryParse(entry.substring(sep + 1)) ?? 1.0;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  bool isPromoted(String chipLabel) =>
      _weightedCount(chipLabel) >= _kPromoteThreshold;

  /// Returns base categories sorted by decayed affinity score.
  List<String> getOrderedCategories() {
    final cats = List<String>.from(baseCategories.where((c) => c != 'All'));
    final hasPromoted = cats.any(isPromoted);
    if (!hasPromoted) return List.from(baseCategories);
    cats.sort((a, b) => _weightedCount(b).compareTo(_weightedCount(a)));
    return ['All', ...cats];
  }

  /// Rank boost for deals in frequently-searched categories.
  /// Gradual: 2 interactions → +10, 3 → +15, 5 → +25 (cap).
  double affinityBoost(String rawCategory) {
    final label = rawCategoryToLabel(rawCategory);
    if (label == null) return 0.0;
    final count = _weightedCount(label);
    if (count < _kPromoteThreshold) return 0.0;
    return (count * 5.0).clamp(0.0, 25.0);
  }
}
