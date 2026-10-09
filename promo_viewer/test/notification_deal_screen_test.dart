import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/models/promotion.dart';
import 'package:promo_viewer/screens/deal_detail_screen.dart';
import 'package:promo_viewer/screens/notification_deal_screen.dart';

Promotion deal() => Promotion.fromJson({
  'brand': 'Test Brand',
  'promotion_title': 'Save 25%!',
  'status': 'active',
  'discount_type': 'percentage',
  'discount_value': '25%',
});

void main() {
  testWidgets(
    'cold notification initializes services then renders actual details',
    (tester) async {
      final initialized = Completer<void>();
      var lookups = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationDealScreen(
            promoId: 'test_brand_save_25',
            coldStart: true,
            initialize: () => initialized.future,
            resolveDeal: (id) async {
              expect(id, 'test_brand_save_25');
              lookups++;
              return deal();
            },
            homeBuilder: (_) => const Scaffold(body: Text('Feed')),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(lookups, 0);
      initialized.complete();
      await tester.pumpAndSettle();
      expect(find.byType(DealDetailScreen), findsOneWidget);
      expect(find.text('Save 25%!'), findsWidgets);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Feed'), findsOneWidget);
      expect(find.byType(DealDetailScreen), findsNothing);
    },
  );

  testWidgets('cold notification system Back returns home, not splash', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationDealScreen(
          promoId: 'test_brand_save_25',
          coldStart: true,
          initialize: () async {},
          resolveDeal: (_) async => deal(),
          homeBuilder: (_) => const Scaffold(body: Text('Feed')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Feed'), findsOneWidget);
  });

  testWidgets('missing deal has an unavailable state and retries lookup', (
    tester,
  ) async {
    var lookups = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationDealScreen(
          promoId: 'removed',
          coldStart: true,
          initialize: () async {},
          resolveDeal: (_) async {
            lookups++;
            return lookups == 1 ? null : deal();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This deal is no longer available'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(DealDetailScreen), findsOneWidget);
  });

  testWidgets('failed lookup does not silently fall back to the feed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationDealScreen(
          promoId: 'offline',
          initialize: () async {},
          resolveDeal: (_) async => throw StateError('Unavailable'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not open this deal'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
