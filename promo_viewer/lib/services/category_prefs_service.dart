import 'package:shared_preferences/shared_preferences.dart';

const _kPromoteThreshold = 2; // interactions before a category floats to front

/// Tracks local category affinity from searches and deal clicks.
/// Reorders the category chip bar once a category hits the threshold.
class CategoryPrefsService {
  static final CategoryPrefsService _i = CategoryPrefsService._();
  factory CategoryPrefsService() => _i;
  CategoryPrefsService._();

  SharedPreferences? _prefs;

  static const _prefix = 'cat_affinity_';

  static const baseCategories = [
    'All', 'Food', 'Coffee', 'Retail', 'Fashion', 'Beauty',
    'Tech', 'Home', 'Travel', 'Automotive', 'Grocery',
  ];

  // Maps search keywords → chip label
  static const Map<String, List<String>> _keywords = {
    'Beauty':     ['beauty', 'makeup', 'lipstick', 'foundation', 'skincare', 'serum', 'mascara', 'blush', 'perfume', 'fragrance', 'nail', 'eyeshadow', 'concealer'],
    'Coffee':     ['coffee', 'latte', 'espresso', 'cappuccino', 'cold brew', 'brew'],
    'Fashion':    ['fashion', 'clothes', 'clothing', 'dress', 'shirt', 'pants', 'shoes', 'sneakers', 'jeans', 'jacket', 'hoodie', 'apparel', 'outfit', 'skirt', 'boots'],
    'Food':       ['food', 'burger', 'pizza', 'sandwich', 'meal', 'restaurant', 'lunch', 'dinner', 'sushi', 'taco', 'wings', 'fries'],
    'Tech':       ['tech', 'phone', 'laptop', 'computer', 'tablet', 'headphones', 'earbuds', 'gaming', 'electronics', 'camera', 'monitor', 'keyboard'],
    'Home':       ['home', 'furniture', 'decor', 'kitchen', 'bedding', 'appliance', 'candle', 'rug', 'curtain', 'towel'],
    'Grocery':    ['grocery', 'groceries', 'supermarket', 'produce', 'organic', 'fruit', 'vegetables'],
    'Travel':     ['travel', 'hotel', 'flight', 'airline', 'vacation', 'booking', 'resort'],
    'Automotive': ['car', 'auto', 'automotive', 'gas', 'oil', 'tire', 'vehicle', 'truck'],
    'Retail':     ['retail', 'outlet', 'clearance', 'department store'],
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

  // ── Category resolution ───────────────────────────────────────────────────

  String? resolveQueryToCategory(String query) {
    final q = query.toLowerCase();
    for (final entry in _keywords.entries) {
      if (entry.value.any((kw) => q.contains(kw))) return entry.key;
    }
    return null;
  }

  String? rawCategoryToLabel(String raw) => _rawToLabel[raw.toLowerCase()];

  // ── Recording interest ────────────────────────────────────────────────────

  Future<void> recordCategoryInterest(String chipLabel, {int weight = 1}) async {
    _prefs ??= await SharedPreferences.getInstance();
    final key = '$_prefix${chipLabel.toLowerCase()}';
    await _prefs!.setInt(key, (_prefs!.getInt(key) ?? 0) + weight);
  }

  // ── Reading counts ────────────────────────────────────────────────────────

  int getCategoryCount(String chipLabel) =>
      _prefs?.getInt('$_prefix${chipLabel.toLowerCase()}') ?? 0;

  // ── Chip ordering ─────────────────────────────────────────────────────────

  /// Returns base categories reordered by affinity count.
  /// Only reorders once at least one category has hit the threshold.
  List<String> getOrderedCategories() {
    final cats = List<String>.from(
        baseCategories.where((c) => c != 'All'));
    final hasPromoted = cats.any((c) => getCategoryCount(c) >= _kPromoteThreshold);
    if (!hasPromoted) return List.from(baseCategories);
    cats.sort((a, b) => getCategoryCount(b).compareTo(getCategoryCount(a)));
    return ['All', ...cats];
  }

  // ── Ranking boost ─────────────────────────────────────────────────────────

  bool isPromoted(String chipLabel) =>
      getCategoryCount(chipLabel) >= _kPromoteThreshold;

  /// Extra score points to add to deals in frequently-searched categories.
  /// Returns 0 until the threshold is hit; caps at 25.
  double affinityBoost(String rawCategory) {
    final label = rawCategoryToLabel(rawCategory);
    if (label == null) return 0.0;
    final count = getCategoryCount(label);
    if (count < _kPromoteThreshold) return 0.0;
    return (count * 3.0).clamp(0.0, 25.0);
  }
}
