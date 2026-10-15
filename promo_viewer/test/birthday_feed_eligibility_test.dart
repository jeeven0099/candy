import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/models/promotion.dart';
import 'package:promo_viewer/models/user_prefs.dart';
import 'package:promo_viewer/services/interaction_service.dart';
import 'package:promo_viewer/utils/deal_feed_queue.dart';
import 'package:promo_viewer/utils/feed_ranker.dart';
import 'package:promo_viewer/utils/ranking_contract.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/reliable_offer.dart';

Promotion offer(
  String brand, {
  bool birthdayRelated = false,
  String promotionType = 'sale',
  String source = 'web',
  double quality = 85,
  double confidence = 0.95,
}) {
  final p = Promotion.fromJson(
    reliableOfferJson({
      'brand': brand,
      'promotion_title': '$brand offer',
      'category': 'food',
      'birthday_related': birthdayRelated,
      'promotion_type': promotionType,
      'discount_type': 'free_item',
      'discount_value': 'Free item',
      'status': 'active',
      'confidence_score': confidence,
      'global_quality_score': quality,
      'economic_value_score': 60,
      'redemption_method': 'in_store',
      'deal_scope': 'in_store_only',
      'source': source,
      'personal_rank_score': source == 'email' ? 100 : null,
    }),
  );
  p.distanceKm = 0.5;
  return p;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await InteractionService.init();
  });

  UserPrefs birthdayPrefs({bool matches = true}) {
    final month = DateTime.now().month;
    return UserPrefs(
      birthdayMonth: matches ? month : month % 12 + 1,
      birthdayDay: 31,
      favoriteBrands: const ['Birthday Brand'],
      favoriteCategories: const ['food'],
      dealPriorities: const ['free', 'rewards', 'nearby'],
    );
  }

  test('feed eligibility requires birthday month, not birthday day', () {
    final p = offer('Birthday Brand', birthdayRelated: true);
    expect(isFeedWorthy(p, prefs: birthdayPrefs()), isTrue);
    expect(isFeedWorthy(p, prefs: birthdayPrefs(matches: false)), isFalse);
    expect(isFeedWorthy(p), isFalse);
    expect(isFeedWorthy(p, prefs: const UserPrefs()), isFalse);
    expect(isFeedWorthy(p, prefs: const UserPrefs(birthdayMonth: 0)), isFalse);
    expect(isFeedWorthy(p, prefs: const UserPrefs(birthdayMonth: 13)), isFalse);
  });

  test('birthday reward type is gated even if birthday flag is absent', () {
    final p = offer('Birthday Brand', promotionType: 'birthday_reward');
    expect(p.birthdayRelated, isFalse);
    expect(isFeedWorthy(p, prefs: birthdayPrefs()), isTrue);
    expect(isFeedWorthy(p, prefs: birthdayPrefs(matches: false)), isFalse);
    expect(
      preferenceBoost(p, birthdayPrefs()) -
          preferenceBoost(p, birthdayPrefs(matches: false)),
      RankingContract.birthdayBoost,
    );
  });

  test('ordinary offers remain eligible without a birthday', () {
    final p = offer('Regular Brand');
    expect(isFeedWorthy(p), isTrue);
    expect(isFeedWorthy(p, prefs: const UserPrefs()), isTrue);
    expect(isFeedWorthy(p, prefs: birthdayPrefs(matches: false)), isTrue);
  });

  for (final nearby in [false, true]) {
    final surface = nearby ? 'Near Me' : 'For You';
    List<Promotion> ranked(List<Promotion> all, UserPrefs? prefs) => nearby
        ? selectNearbyDeals(
            all,
            InteractionService(),
            prefs: prefs,
            getIsMember: (_) => true,
            limit: RankingContract.feedCandidateLimit,
          )
        : selectTopDeals(
            all,
            InteractionService(),
            prefs: prefs,
            getIsMember: (_) => true,
            limit: RankingContract.feedCandidateLimit,
          );

    test('$surface hides birthday deals from top 10 and replacements', () {
      final birthday = offer(
        'Birthday Brand',
        birthdayRelated: true,
        source: 'email',
        quality: 100,
      );
      final typed = offer(
        'Typed Birthday Brand',
        promotionType: 'birthday_reward',
        quality: 100,
      );
      final all = [
        birthday,
        typed,
        for (var i = 0; i < 45; i++) offer('Regular Brand $i'),
      ];
      for (final prefs in [
        birthdayPrefs(matches: false),
        const UserPrefs(),
        null,
      ]) {
        final candidates = ranked(all, prefs);
        expect(candidates, hasLength(40));
        expect(candidates, isNot(contains(birthday)));
        expect(candidates, isNot(contains(typed)));
        final queue = DealFeedQueue()..reset(candidates);
        expect(queue.visible, hasLength(10));
        expect(queue.reserve, hasLength(30));
        for (var i = 0; i < 30; i++) {
          queue.dismiss(queue.visible.first.id);
          expect(queue.visible, isNot(contains(birthday)));
          expect(queue.visible, isNot(contains(typed)));
        }
      }
    });

    test('$surface admits birthday rewards only in the matching month', () {
      final birthday = offer('Birthday Brand', birthdayRelated: true);
      final typed = offer('Typed Brand', promotionType: 'birthday_reward');
      final all = [birthday, typed, offer('Regular Brand')];
      final matching = ranked(all, birthdayPrefs());
      expect(matching, contains(birthday));
      expect(matching, contains(typed));

      final queue = DealFeedQueue()..reset(matching);
      queue.reconcile(ranked(all, birthdayPrefs(matches: false)));
      expect(queue.visible, hasLength(1));
      expect(queue.visible.single.brand, 'Regular Brand');
      expect(queue.reserve, isEmpty);
    });

    test('$surface birthday month does not override quality checks', () {
      final lowQuality = offer(
        'Birthday Brand',
        birthdayRelated: true,
        quality: 20,
      );
      final lowConfidence = offer(
        'Typed Brand',
        promotionType: 'birthday_reward',
        confidence: 0.2,
      );
      expect(ranked([lowQuality, lowConfidence], birthdayPrefs()), isEmpty);
    });
  }
}
