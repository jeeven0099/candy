import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/models/promotion.dart';
import 'package:promo_viewer/services/interaction_service.dart';
import 'package:promo_viewer/utils/deal_feed_queue.dart';
import 'package:promo_viewer/utils/deal_feedback_metadata.dart';
import 'package:promo_viewer/utils/deal_reliability.dart';
import 'package:promo_viewer/utils/feed_ranker.dart';
import 'package:promo_viewer/utils/source_link.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'fixtures/reliable_offer.dart';

void main() {
  final now = DateTime.utc(2026, 10, 9, 12);
  Map<String, dynamic> sample([Map<String, dynamic> fields = const {}]) {
    final json = reliableOfferJson(fields);
    json['source_evidence']['checked_at'] = now.toIso8601String();
    return json;
  }

  DealReliability assess(Map<String, dynamic> json, {DateTime? at}) =>
      assessDealReliability(Promotion.fromJson(json), now: at ?? now);

  setUp(() async {
    tz_data.initializeTimeZones();
    SharedPreferences.setMockInitialValues({});
    await InteractionService.init();
  });

  test('a recently captured, grounded offer qualifies without an expiry', () {
    expect(assess(sample()).eligible, isTrue);
  });

  test('confidence and score cannot substitute for source evidence', () {
    final json = sample()..remove('source_evidence');
    expect(assess(json).eligible, isFalse);
    expect(assess(json).reasons, contains('source_evidence_missing'));
    json['source_evidence'] = {
      'status': 'supported',
      'checked_at': now.toIso8601String(),
    };
    expect(assess(json).eligible, isFalse);
  });

  test('evidence is bound to the actual offer and source', () {
    for (final field in {
      'promotion_title': '50% off everything',
      'discount_value': '50%',
      'promo_code': 'PRIVATE50',
      'minimum_spend': r'$100',
      'end_date': '2027-10-09',
      'new_user_only': true,
      'redemption_steps': ['Different conditions'],
      'terms_text': 'Members only; selected items.',
      'valid_days': ['monday'],
      'time_start': '12:00',
      'time_end': '13:00',
      'timezone': 'America/Chicago',
    }.entries) {
      final json = sample()..[field.key] = field.value;
      expect(assess(json).reasons, contains('source_evidence_mismatch'));
    }
    final json = sample();
    json['source_evidence']['source_url'] = 'https://example.com/other';
    expect(assess(json).reasons, contains('source_evidence_mismatch'));
  });

  test('stale, unknown, or future capture dates are excluded', () {
    for (final date in [
      null,
      '',
      'today',
      '2026-02-30T12:00:00Z',
      '2026-10-09T12:00:00',
    ]) {
      final json = sample();
      json['source_evidence']['checked_at'] = date;
      expect(assess(json).reasons, contains('source_capture_date_missing'));
    }
    final old = sample();
    old['source_evidence']['checked_at'] = now
        .subtract(const Duration(days: 15))
        .toIso8601String();
    expect(assess(old).reasons, contains('source_evidence_stale'));
    final future = sample();
    future['source_evidence']['checked_at'] = now
        .add(const Duration(hours: 1))
        .toIso8601String();
    expect(assess(future).reasons, contains('source_capture_date_in_future'));
  });

  test(
    'date-only expiry lasts through the final day in the offer timezone',
    () {
      final json = sample({
        'end_date': '2026-10-09',
        'timezone': 'America/Chicago',
      });
      expect(
        assess(json, at: DateTime.utc(2026, 10, 10, 4, 59)).eligible,
        isTrue,
      );
      expect(
        assess(json, at: DateTime.utc(2026, 10, 10, 5)).reasons,
        contains('offer_expired'),
      );
      final instant = sample({'end_date': '2026-10-09T16:00:00Z'});
      expect(
        assess(instant, at: DateTime.utc(2026, 10, 9, 16)).reasons,
        contains('offer_expired'),
      );
    },
  );

  test(
    'future starts, malformed dates, and inverted date ranges are excluded',
    () {
      expect(
        assess(sample({'start_date': '2026-10-10'})).reasons,
        contains('offer_not_started'),
      );
      for (final date in ['2026-02-30', '2026-13-01', 'unknown']) {
        expect(
          assess(sample({'end_date': date})).reasons,
          contains('invalid_end_date'),
        );
      }
      expect(
        assess(
          sample({'start_date': '2026-10-12', 'end_date': '2026-10-10'}),
        ).reasons,
        contains('invalid_date_range'),
      );
      expect(
        assess(
          sample({'end_date': '2026-10-10', 'timezone': 'Invalid/Zone'}),
        ).reasons,
        contains('invalid_end_date'),
      );
    },
  );

  test(
    'missing critical redemption fields and nonfinite scores are excluded',
    () {
      for (final fields in [
        {'redemption_steps': <String>[]},
        {'redemption_method': 'unknown'},
        {'requires_membership': true, 'membership_name': null},
        {'promotion_type': 'coupon', 'promo_code': null},
        {'discount_type': 'percentage_off', 'discount_value': null},
        {'confidence_score': double.nan},
        {'global_quality_score': double.infinity},
        {'extraction_status': 'no_offer_found'},
      ]) {
        expect(assess(sample(fields)).eligible, isFalse);
      }
    },
  );

  test(
    'source URLs reject lookalikes, credentials, unsafe schemes, and local hosts',
    () {
      for (final link in [
        'javascript:alert(1)',
        'file:///tmp/source',
        'https://localhost/offers',
        'https://127.0.0.1/offers',
        'https://example.com@evil.test/offers',
        'https://example.com.evil.test/offers',
        'https://example.com:444/offers',
        'https://example.com\\@evil.test/offers',
        'https://example.com/\n',
      ]) {
        expect(sourceMatchesDomain(link, 'example.com'), isFalse);
        final json = sample()..['source_url'] = link;
        expect(assess(json).eligible, isFalse);
        expect(Promotion.fromJson(json).verifyUrl, isNull);
      }
      expect(
        sourceMatchesDomain('https://shop.example.com/offers', 'example.com'),
        isTrue,
      );
      expect(publicSourceUri('https://example.com/offers'), isNotNull);
      expect(
        sourceMatchesDomain('https://example.com/', 'example.com/path'),
        isFalse,
      );
      final json = sample()..['deal_url'] = 'https://evil.test/';
      expect(Promotion.fromJson(json).verifyUrl, 'https://example.com/offers');
    },
  );

  for (final nearby in [false, true]) {
    test(
      '${nearby ? 'Near Me' : 'For You'} filters unreliable offers before top 10 and replacements',
      () {
        final all = [
          for (var i = 0; i < 45; i++)
            Promotion.fromJson(reliableOfferJson({'brand': 'Store $i'}))
              ..distanceKm = 0.5,
          Promotion.fromJson({
            'brand': 'Unreliable',
            'promotion_title': 'Free everything',
            'status': 'active',
            'confidence_score': 1.0,
            'global_quality_score': 100.0,
            'discount_type': 'free_item',
            'redemption_method': 'in_store',
          })..distanceKm = 0.1,
        ];
        final bad = all.last;
        final selected = nearby
            ? selectNearbyDeals(all, InteractionService(), limit: 40)
            : selectTopDeals(all, InteractionService(), limit: 40);
        expect(selected, hasLength(40));
        expect(selected, isNot(contains(bad)));
        final queue = DealFeedQueue()..reset(selected);
        for (var i = 0; i < 30; i++) {
          queue.dismiss(queue.visible.first.id);
          expect(queue.visible, isNot(contains(bad)));
        }
      },
    );
  }

  test(
    'feedback stores reliability reasons without source excerpts or private links',
    () {
      final json = sample();
      json['source_evidence']['excerpt'] = 'private-email-body';
      json['source_evidence']['source_url'] =
          'https://example.com/?token=private-token';
      final meta = dealFeedbackMetadata(Promotion.fromJson(json));
      expect(meta['reliability_version'], reliabilityVersion);
      expect(meta['reliability_eligible'], isFalse);
      expect(jsonEncode(meta), isNot(contains('private-email-body')));
      expect(jsonEncode(meta), isNot(contains('private-token')));
    },
  );
}
