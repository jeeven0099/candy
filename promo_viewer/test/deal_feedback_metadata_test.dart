import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/models/promotion.dart';
import 'package:promo_viewer/utils/deal_feedback_metadata.dart';
import 'package:promo_viewer/utils/ranking_contract.dart';

void main() {
  test('source, feed position, and ranking version are explicit', () {
    final p = Promotion.fromJson({
      'brand': 'Example Store',
      'source': 'email',
      'global_quality_score': 75,
      'personal_rank_score': 85,
      'personal_rank_model': 'heuristic',
      'confidence_score': 0.8,
    });
    final meta = dealFeedbackMetadata(
      p,
      rankingMode: 'for_you',
      feedPosition: 3,
      runtimeScore: 92,
    );
    expect(meta['deal_source'], 'email');
    expect(meta['source_group'], 'email');
    expect(meta['ranking_mode'], 'for_you');
    expect(meta['feed_position'], 3);
    expect(meta['ranking_version'], RankingContract.version);
    expect(meta['runtime_score'], 92);
    expect(meta['personal_rank_score'], 85);
    expect(meta['personal_rank_model'], 'heuristic');
  });

  test('legacy combined deals keep raw source and email grouping', () {
    final meta = dealFeedbackMetadata(Promotion.fromJson({'source': 'both'}));
    expect(meta['deal_source'], 'both');
    expect(meta['source_group'], 'email');
  });

  test('public deals are not treated as emails or assigned a fake rank', () {
    final meta = dealFeedbackMetadata(Promotion.fromJson({'source': 'web'}));
    expect(meta['source_group'], 'public');
    expect(meta.containsKey('personal_rank_score'), isFalse);
    expect(meta.containsKey('feed_position'), isFalse);
  });

  test('feedback metadata excludes mailbox and private redemption data', () {
    final p = Promotion.fromJson({
      'source': 'email',
      'email_subject': 'secret-subject',
      'sender_email': 'private@example.com',
      'promo_code': 'unique-private-code',
      'source_url': 'https://example.com/?token=private-token',
      'terms_text': 'private-email-body',
    });
    final encoded = jsonEncode(dealFeedbackMetadata(p));
    for (final secret in [
      'secret-subject',
      'private@example.com',
      'unique-private-code',
      'private-token',
      'private-email-body',
    ]) {
      expect(encoded, isNot(contains(secret)));
    }
  });
}
