import 'dart:convert';
import '../models/promotion.dart';
import 'remote_data_service.dart';

class PromotionsService {
  static List<Promotion> cached = [];

  static Future<List<Promotion>> load() async {
    final raw = await RemoteDataService.load('all_promotions.json');
    final data = json.decode(raw) as Map<String, dynamic>;
    final list = data['promotions'] as List<dynamic>? ?? [];
    final all = list
        .cast<Map<String, dynamic>>()
        .map(Promotion.fromJson)
        .where((p) => p.title.isNotEmpty && p.globalQualityScore >= 35)
        .toList();

    // Deduplicate by (brand, title) — keep the highest-quality copy.
    final dedupMap = <String, Promotion>{};
    for (final p in all) {
      final key = '${p.brand.toLowerCase()}||${p.title.toLowerCase()}';
      final existing = dedupMap[key];
      if (existing == null || p.globalQualityScore > existing.globalQualityScore) {
        dedupMap[key] = p;
      }
    }
    cached = dedupMap.values.toList();
    return cached;
  }
}
