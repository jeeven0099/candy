class UserPrefs {
  final List<String> favoriteCategories;
  final List<String> favoriteBrands;
  final List<String> dealPriorities; // slugs: free, bogo, discount, nearby, online, rewards

  const UserPrefs({
    this.favoriteCategories = const [],
    this.favoriteBrands     = const [],
    this.dealPriorities     = const [],
  });

  bool get isEmpty =>
      favoriteCategories.isEmpty && favoriteBrands.isEmpty && dealPriorities.isEmpty;

  factory UserPrefs.fromJson(Map<String, dynamic> j) => UserPrefs(
    favoriteCategories: List<String>.from(j['favorite_categories'] as List? ?? []),
    favoriteBrands:     List<String>.from(j['favorite_brands']     as List? ?? []),
    dealPriorities:     List<String>.from(j['preferred_contexts']  as List? ?? []),
  );

  Map<String, dynamic> toJson() => {
    'favorite_categories': favoriteCategories,
    'favorite_brands':     favoriteBrands,
    'preferred_contexts':  dealPriorities,
    'updated_at':          DateTime.now().toIso8601String(),
  };
}
