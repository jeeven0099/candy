import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/models/promotion.dart';
import 'package:promo_viewer/screens/deal_detail_screen.dart';
import 'package:promo_viewer/screens/saved_screen.dart';
import 'package:promo_viewer/services/interaction_service.dart';
import 'package:promo_viewer/services/saved_deals_service.dart';
import 'package:promo_viewer/widgets/deal_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/reliable_offer.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SavedDealsService.init();
    await InteractionService.init();
  });

  Widget screen(List<Promotion> all) => MaterialApp(
    home: SavedScreen(all: all, onRefresh: () async {}),
  );

  testWidgets('empty Saved tab is refreshable and has no extra sections', (
    tester,
  ) async {
    await tester.pumpWidget(screen([]));
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('No saved deals'), findsOneWidget);
    expect(find.text('Expiring Soon'), findsNothing);
    expect(find.byType(RefreshIndicator), findsOneWidget);
  });

  for (final width in [320.0, 1024.0]) {
    testWidgets(
      'Saved opens details and removes a saved deal at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final offer = Promotion.fromJson(reliableOfferJson({}));
        await SavedDealsService().save(offer);
        await tester.pumpWidget(screen([offer]));
        await tester.pumpAndSettle();
        expect(find.byType(DealCard), findsOneWidget);
        await tester.tap(find.byType(DealCard));
        await tester.pumpAndSettle();
        expect(find.byType(DealDetailScreen), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Remove from Saved'));
        await tester.pumpAndSettle();
        expect(SavedDealsService().all, isEmpty);
        expect(find.text('No saved deals'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a deal missing from the catalog keeps a removable saved snapshot',
    (tester) async {
      final offer = Promotion.fromJson(reliableOfferJson({}));
      await SavedDealsService().save(offer);
      await tester.pumpWidget(screen([]));
      await tester.pumpAndSettle();
      expect(find.text(offer.title), findsOneWidget);
      expect(find.text('Deal unavailable'), findsOneWidget);
      expect(find.byType(DealCard), findsNothing);
      await tester.tap(find.byTooltip('Remove from Saved'));
      await tester.pumpAndSettle();
      expect(find.text('No saved deals'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
