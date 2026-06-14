import '../models/promotion.dart';

class GroceryGroup {
  final String brand;
  final List<Promotion> items;
  GroceryGroup(this.brand, this.items);
}

// Minimum number of same-brand sale deals needed to collapse into a group card.
// Grocery/food: 2+ (weekly specials are always item-level lists).
// Fashion: 4+ (avoids grouping brands with a few distinct promotions).
int _groupThreshold(String category) {
  if (category == 'grocery' || category == 'food') return 2;
  if (category == 'fashion') return 4;
  return 999; // other categories: never group
}

/// Collapses per-item sale floods from the same brand into [GroceryGroup]s.
/// Everything else passes through as a plain [Promotion].
List<Object> groupGroceryDeals(List<Promotion> promos) {
  final groups = <String, List<Promotion>>{};
  final singles = <Promotion>[];

  for (final p in promos) {
    final threshold = _groupThreshold(p.category);
    if (p.promotionType == 'sale' && threshold < 999) {
      groups.putIfAbsent(p.brand, () => []).add(p);
    } else {
      singles.add(p);
    }
  }

  final result = <Object>[];
  for (final entry in groups.entries) {
    final items = entry.value;
    final threshold = _groupThreshold(items.first.category);
    if (items.length >= threshold) {
      result.add(GroceryGroup(entry.key, items));
    } else {
      singles.addAll(items);
    }
  }
  result.addAll(singles);
  return result;
}
