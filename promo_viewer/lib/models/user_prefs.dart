class UserPrefs {
  final List<String> favoriteCategories;
  final List<String> favoriteBrands;
  final List<String> dealPriorities; // slugs: free, bogo, discount, nearby, online, rewards
  final List<String> hiddenBrands;

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
    return hiddenBrands.any((h) => h.toLowerCase() == b);
  }

  factory UserPrefs.fromJson(Map<String, dynamic> j) => UserPrefs(
    favoriteCategories: List<String>.from(j['favorite_categories'] as List? ?? []),
    favoriteBrands:     List<String>.from(j['favorite_brands']     as List? ?? []),
    dealPriorities:     List<String>.from(j['preferred_contexts']  as List? ?? []),
    hiddenBrands:       List<String>.from(j['hidden_brands']       as List? ?? []),
  );

  Map<String, dynamic> toJson() => {
    'favorite_categories': favoriteCategories,
    'favorite_brands':     favoriteBrands,
    'preferred_contexts':  dealPriorities,
    'hidden_brands':       hiddenBrands,
    'updated_at':          DateTime.now().toIso8601String(),
  };

  UserPrefs withHiddenBrand(String brand) => UserPrefs(
    favoriteCategories: favoriteCategories,
    favoriteBrands:     favoriteBrands,
    dealPriorities:     dealPriorities,
    hiddenBrands:       [...hiddenBrands, brand],
  );

  UserPrefs withoutHiddenBrand(String brand) {
    final b = brand.toLowerCase();
    return UserPrefs(
      favoriteCategories: favoriteCategories,
      favoriteBrands:     favoriteBrands,
      dealPriorities:     dealPriorities,
      hiddenBrands:       hiddenBrands.where((h) => h.toLowerCase() != b).toList(),
    );
  }
}
