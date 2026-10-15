import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/models/promotion.dart';
import 'package:promo_viewer/models/user_prefs.dart';
import 'package:promo_viewer/services/interaction_service.dart';
import 'package:promo_viewer/services/location_service.dart';
import 'package:promo_viewer/utils/deal_reliability.dart';
import 'package:promo_viewer/utils/feed_ranker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled beta catalog supports a cold-start feed and reserves',
    () async {
      tz.initializeTimeZones();
      SharedPreferences.setMockInitialValues({});
      await InteractionService.init();
      final data = jsonDecode(
        File('assets/all_promotions.json').readAsStringSync(),
      );
      final all = (data['promotions'] as List)
          .map((row) => Promotion.fromJson(row as Map<String, dynamic>))
          .toList();
      expect(all, isNotEmpty);
      for (final offer in all) {
        expect(
          assessDealReliability(offer).reasons,
          isNot(contains('source_evidence_mismatch')),
          reason:
              'Pipeline output must preserve captured source and offer fields.',
        );
      }
      final queue = selectTopDeals(
        all,
        InteractionService(),
        prefs: const UserPrefs(),
        limit: 40,
      );
      expect(queue, hasLength(40));
      expect(
        queue.every((offer) => assessDealReliability(offer).eligible),
        isTrue,
      );
      expect(
        queue.any(
          (offer) =>
              offer.birthdayRelated || offer.promotionType == 'birthday_reward',
        ),
        isFalse,
      );
    },
  );

  test('bundled store locations support a real Chicago nearby feed', () async {
    tz.initializeTimeZones();
    SharedPreferences.setMockInitialValues({});
    await InteractionService.init();
    final data = jsonDecode(
      File('assets/all_promotions.json').readAsStringSync(),
    );
    final all = (data['promotions'] as List)
        .map((row) => Promotion.fromJson(row as Map<String, dynamic>))
        .toList();
    final stores = jsonDecode(
      File('assets/brand_locations.json').readAsStringSync(),
    );
    final locations = (stores['brands'] as Map<String, dynamic>).map(
      (brand, coordinates) => MapEntry(
        brand,
        (coordinates as List)
            .map(
              (point) => [
                (point[0] as num).toDouble(),
                (point[1] as num).toDouble(),
              ],
            )
            .toList(),
      ),
    );
    for (final offer in all) {
      offer.distanceKm = LocationService.nearestKm(
        offer.brand,
        41.8781,
        -87.6298,
        locations,
      );
    }
    final nearby = selectNearbyDeals(
      all,
      InteractionService(),
      prefs: const UserPrefs(),
    );
    expect(nearby, isNotEmpty);
    expect(nearby.length, lessThanOrEqualTo(10));
    expect(nearby.every((offer) => offer.distanceKm! <= 8.05), isTrue);
    expect(
      nearby.every((offer) => assessDealReliability(offer).eligible),
      isTrue,
    );
  });
}
