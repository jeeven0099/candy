import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/models/promotion.dart';
import 'package:promo_viewer/screens/deal_detail_screen.dart';

import 'fixtures/reliable_offer.dart';

void main() {
  testWidgets(
    'source capture date is historical, not today or a verified claim',
    (tester) async {
      final json = reliableOfferJson({'confidence_score': 1.0});
      json['source_evidence']['checked_at'] = '2026-09-01T12:00:00Z';
      await tester.pumpWidget(
        MaterialApp(home: DealDetailScreen(promo: Promotion.fromJson(json))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Offer details need verification'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Source: example.com'), 250);
      expect(find.text('Source captured Sep 1, 2026'), findsOneWidget);
      expect(find.textContaining('Verified from'), findsNothing);
      expect(find.textContaining('Official source:'), findsNothing);
      expect(find.textContaining('Last checked'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('details show new-customer restrictions and supplied terms', (
    tester,
  ) async {
    final json = reliableOfferJson({
      'new_user_only': true,
      'terms_text': 'One redemption per new customer. Excludes clearance.',
    });
    await tester.pumpWidget(
      MaterialApp(home: DealDetailScreen(promo: Promotion.fromJson(json))),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('New customers only'), 300);
    expect(find.text('New customers only'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('One redemption per new customer. Excludes clearance.'),
      250,
    );
    expect(find.text('Offer terms'), findsOneWidget);
    expect(
      find.text('One redemption per new customer. Excludes clearance.'),
      findsOneWidget,
    );
    expect(find.textContaining('open to everyone'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
