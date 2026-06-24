class HiddenBrand {
  final String brand;
  final DateTime hiddenAt;
  final String source; // 'user_menu' | 'model_inferred'

  const HiddenBrand({
    required this.brand,
    required this.hiddenAt,
    this.source = 'user_menu',
  });

  factory HiddenBrand.fromJson(dynamic j) {
    // Backward compat: old format was plain strings.
    if (j is String) return HiddenBrand(brand: j, hiddenAt: DateTime.now());
    final m = j as Map<String, dynamic>;
    return HiddenBrand(
      brand:    m['brand']    as String,
      hiddenAt: DateTime.tryParse(m['hidden_at'] as String? ?? '') ?? DateTime.now(),
      source:   m['source']   as String? ?? 'user_menu',
    );
  }

  Map<String, dynamic> toJson() => {
    'brand':     brand,
    'hidden_at': hiddenAt.toIso8601String(),
    'source':    source,
  };
}

class UserPrefs {
  final List<String>       favoriteCategories;
  final List<String>       favoriteBrands;
  final List<String>       dealPriorities; // slugs: free, bogo, discount, nearby, online, rewards
  final List<HiddenBrand>  hiddenBrands;

  const UserPrefs({
    this.favoriteCategories = const [],
    this.favoriteBrands     = const [],
    this.dealPriorities     = const [],
    this.hiddenBrands       = const [],
  });

  bool get isEmpty =>
      favoriteCategories.isEmpty && favoriteBrands.isEmpty && dealPriorities.isEmpty;

  bool isHiddenBrand(String brand) {
    final b = brand.toLowerCase();
    return hiddenBrands.any((h) => h.brand.toLowerCase() == b);
  }

  factory UserPrefs.fromJson(Map<String, dynamic> j) => UserPrefs(
    favoriteCategories: List<String>.from(j['favorite_categories'] as List? ?? []),
    favoriteBrands:     List<String>.from(j['favorite_brands']     as List? ?? []),
    dealPriorities:     List<String>.from(j['preferred_contexts']  as List? ?? []),
    hiddenBrands: (j['hidden_brands'] as List? ?? [])
        .map((e) => HiddenBrand.fromJson(e))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'favorite_categories': favoriteCategories,
    'favorite_brands':     favoriteBrands,
    'preferred_contexts':  dealPriorities,
    'hidden_brands':       hiddenBrands.map((h) => h.toJson()).toList(),
    'updated_at':          DateTime.now().toIso8601String(),
  };

  UserPrefs withHiddenBrand(String brand) => UserPrefs(
    favoriteCategories: favoriteCategories,
    favoriteBrands:     favoriteBrands,
    dealPriorities:     dealPriorities,
    hiddenBrands: [
      ...hiddenBrands,
      HiddenBrand(brand: brand, hiddenAt: DateTime.now()),
    ],
  );

  UserPrefs withoutHiddenBrand(String brand) {
    final b = brand.toLowerCase();
    return UserPrefs(
      favoriteCategories: favoriteCategories,
      favoriteBrands:     favoriteBrands,
      dealPriorities:     dealPriorities,
      hiddenBrands: hiddenBrands.where((h) => h.brand.toLowerCase() != b).toList(),
    );
  }
}
