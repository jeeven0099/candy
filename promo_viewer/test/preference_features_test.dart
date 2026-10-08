import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/models/promotion.dart';
import 'package:promo_viewer/models/user_prefs.dart';
import 'package:promo_viewer/utils/preference_features.dart';

Promotion offer(String title, {bool member = false}) => Promotion.fromJson({
  'brand': 'Example',
  'category': 'retail',
  'promotion_title': title,
  'promotion_type': 'sale',
  'discount_type': 'percentage_off',
  'requires_membership': member,
  'global_quality_score': 75,
  'confidence_score': 0.9,
  'effective_discount_pct': 20,
});

Map<String, dynamic> event(
  Promotion p,
  String kind,
  int sequence,
  DateTime at,
) => {
  'promotion_id': p.id,
  'event_type': kind,
  'created_at': at.toIso8601String(),
  'metadata': {
    'offer_features': preferenceOfferSnapshot(p),
    'event_sequence': sequence,
  },
};

void main() {
  final now = DateTime.utc(2026, 10, 7);
  test('training and app feature schemas have identical ordered names', () {
    final schema = jsonDecode(
      File('../ranking/feature_schema.json').readAsStringSync(),
    );
    expect(schema['version'], preferenceFeatureVersion);
    expect(schema['features'], preferenceFeatureNames);
  });
  test('unknown user starts neutral; inputs are compact numeric values', () {
    final features = PreferenceProfile().features(offer('new'), now: now);
    expect(features.keys.toSet(), preferenceFeatureNames.toSet());
    expect(features['brand_preference'], 0);
    expect(features['total_evidence'], 0);
    expect(features['membership_known'], 0);
    expect(jsonEncode(features).length, lessThan(1500));
  });
  test(
    'dismissal generalizes mildly; duplicate swipes are one piece of evidence',
    () {
      final profile = PreferenceProfile();
      final rejected = offer('old');
      profile.apply(event(rejected, 'not_interested', 1, now));
      profile.apply(event(rejected, 'not_interested', 2, now));
      final features = profile.features(offer('new'), now: now);
      expect(features['brand_preference'], closeTo(-0.2, 1e-9));
      expect(features['type_preference'], closeTo(-0.2, 1e-9));
      expect(features['total_evidence'], closeTo(0.05, 1e-9));
    },
  );
  test('current deal is excluded from its own history features', () {
    final profile = PreferenceProfile();
    final saved = offer('saved');
    profile.apply(event(saved, 'deal_saved', 1, now));
    expect(profile.features(saved, now: now)['total_evidence'], 0);
  });
  test('Undo restores previous save; unsave removes that positive signal', () {
    final profile = PreferenceProfile();
    final p = offer('old');
    profile.apply(event(p, 'deal_saved', 1, now));
    profile.apply(event(p, 'not_interested', 2, now));
    expect(
      profile.features(offer('new'), now: now)['brand_preference'],
      isNegative,
    );
    profile.apply(event(p, 'not_interested_undone', 3, now));
    expect(
      profile.features(offer('new'), now: now)['brand_preference'],
      isPositive,
    );
    profile.apply(event(p, 'deal_unsaved', 4, now));
    expect(profile.features(offer('new'), now: now)['total_evidence'], 0);
  });
  test('late stale dismissal cannot resurrect an undone rejection', () {
    final profile = PreferenceProfile();
    final p = offer('old');
    profile.apply(event(p, 'not_interested_undone', 3, now));
    profile.apply(event(p, 'not_interested', 2, now));
    expect(profile.features(offer('new'), now: now)['total_evidence'], 0);
  });
  test('history decays and expires after 90 days', () {
    final profile = PreferenceProfile();
    profile.apply(
      event(
        offer('old'),
        'deal_saved',
        1,
        now.subtract(const Duration(days: 30)),
      ),
    );
    expect(
      profile.features(offer('new'), now: now)['total_evidence'],
      closeTo(0.025, 1e-9),
    );
    expect(
      profile.features(
        offer('new'),
        now: now.add(const Duration(days: 61)),
      )['total_evidence'],
      0,
    );
  });
  test(
    'explicit preferences and membership context are separate from feedback',
    () {
      final profile = PreferenceProfile();
      final features = profile.features(
        offer('new', member: true),
        prefs: const UserPrefs(
          favoriteBrands: ['Example'],
          favoriteCategories: ['retail'],
        ),
        isMember: false,
        now: now,
      );
      expect(features['favorite_brand'], 1);
      expect(features['favorite_category'], 1);
      expect(features['requires_membership'], 1);
      expect(features['has_membership'], 0);
      expect(features['membership_known'], 1);
      expect(features['total_evidence'], 0);
    },
  );
  test('legacy feedback contributes only known brand/category evidence', () {
    final profile = PreferenceProfile();
    profile.apply({
      'promotion_id': 'legacy',
      'event_type': 'not_interested',
      'brand': 'Example',
      'category': 'retail',
      'created_at': now.toIso8601String(),
    });
    final features = profile.features(offer('new'), now: now);
    expect(features['brand_preference'], isNegative);
    expect(features['type_evidence'], 0);
    expect(features['membership_evidence'], 0);
  });
  test('clear removes all prior account evidence', () {
    final profile = PreferenceProfile();
    profile.apply(event(offer('old'), 'deal_saved', 1, now));
    profile.clear();
    expect(profile.features(offer('new'), now: now)['total_evidence'], 0);
  });
}
