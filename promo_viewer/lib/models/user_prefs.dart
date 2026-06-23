class UserPrefs {
  final List<String> favoriteCategories;
  final List<String> favoriteBrands;

  const UserPrefs({
    this.favoriteCategories = const [],
    this.favoriteBrands     = const [],
  });

  bool get isEmpty =>
      favoriteCategories.isEmpty && favoriteBrands.isEmpty;

  factory UserPrefs.fromJson(Map<String, dynamic> j) => UserPrefs(
    favoriteCategories: List<String>.from(j['favorite_categories'] as List? ?? []),
    favoriteBrands:     List<String>.from(j['favorite_brands']     as List? ?? []),
  );

  Map<String, dynamic> toJson() => {
    'favorite_categories': favoriteCategories,
    'favorite_brands':     favoriteBrands,
    'updated_at':          DateTime.now().toIso8601String(),
  };
}
