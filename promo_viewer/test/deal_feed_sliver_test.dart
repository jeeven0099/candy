import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/models/promotion.dart';
import 'package:promo_viewer/widgets/deal_feed_sliver.dart';
import 'package:promo_viewer/widgets/deal_source_badge.dart';

Promotion deal(int i) => Promotion.fromJson({
  'brand': 'Brand $i',
  'promotion_title': 'Offer $i',
  'source': i == 0 ? 'email' : 'web',
});

Widget fixture({
  int count = 40,
  Object revision = 'account|for_you',
  List<Promotion>? ranked,
  DealDismissalCallback? onDismiss,
  DealDismissalCallback? onUndo,
}) => MaterialApp(
  home: Scaffold(
    body: CustomScrollView(
      cacheExtent: 5000,
      slivers: [
        DealFeedSliver(
          rankedDeals: ranked ?? List.generate(count, deal),
          revision: revision,
          countBuilder: (n) => Text('$n deals'),
          emptyState: const Center(child: Text('No deals')),
          onDismiss: onDismiss ?? (p, pos, dir) async {},
          onUndo: onUndo ?? (p, pos, dir) async {},
          itemBuilder: (context, p, pos, dismiss) => SizedBox(
            height: 110,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DealBrandLabel(promo: p),
                Text(p.title),
                IconButton(
                  tooltip: 'Not interested',
                  onPressed: dismiss,
                  icon: const Icon(Icons.thumb_down_outlined),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  ),
);

void main() {
  void expectTenDeals(WidgetTester tester) {
    expect(
      tester
          .widget<SliverList>(find.byType(SliverList))
          .delegate
          .estimatedChildCount,
      10,
    );
  }

  testWidgets('only ten cards are listed; reserve is not shown', (
    tester,
  ) async {
    await tester.pumpWidget(fixture());
    expectTenDeals(tester);
    expect(find.text('Offer 10'), findsNothing);
    expect(find.text('Email'), findsOneWidget);
    expect(find.byIcon(Icons.mail_outline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dx in [-450.0, 450.0]) {
    testWidgets('horizontal swipe $dx dismisses and replaces a deal', (
      tester,
    ) async {
      final events = <(String, int, DismissDirection)>[];
      await tester.pumpWidget(
        fixture(
          onDismiss: (p, pos, dir) async {
            events.add((p.id, pos, dir));
          },
        ),
      );
      await tester.drag(find.text('Offer 0'), Offset(dx, 0));
      await tester.pumpAndSettle();
      expect(find.text('Offer 0'), findsNothing);
      expect(find.text('Offer 10'), findsOneWidget);
      expectTenDeals(tester);
      expect(events.single, (
        deal(0).id,
        1,
        dx < 0 ? DismissDirection.endToStart : DismissDirection.startToEnd,
      ));
      expect(find.text('Undo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a short drag does not submit negative feedback', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      fixture(
        onDismiss: (p, pos, dir) async {
          calls++;
        },
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Offer 0')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Offer 0'), findsOneWidget);
    expect(find.text('Offer 10'), findsNothing);
  });

  testWidgets('vertical scrolling does not dismiss a card', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      fixture(
        onDismiss: (p, pos, dir) async {
          calls++;
        },
      ),
    );
    await tester.drag(find.text('Offer 0'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expectTenDeals(tester);
  });

  testWidgets(
    'undo restores the original position and removes the replacement',
    (tester) async {
      var undone = 0;
      await tester.pumpWidget(
        fixture(
          onUndo: (p, pos, dir) async {
            undone++;
          },
        ),
      );
      await tester.drag(find.text('Offer 0'), const Offset(450, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(undone, 1);
      expect(find.text('Offer 0'), findsOneWidget);
      expect(find.text('Offer 10'), findsNothing);
      expectTenDeals(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('last remaining card can still be undone from the empty state', (
    tester,
  ) async {
    await tester.pumpWidget(fixture(count: 1));
    await tester.drag(find.text('Offer 0'), const Offset(-450, 0));
    await tester.pumpAndSettle();
    expect(find.text('No deals'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Offer 0'), findsOneWidget);
    expect(find.text('No deals'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu command uses the same replacement and undo path', (
    tester,
  ) async {
    DismissDirection? direction;
    await tester.pumpWidget(
      fixture(
        onDismiss: (p, pos, dir) async {
          direction = dir;
        },
      ),
    );
    await tester.tap(find.byTooltip('Not interested').first);
    await tester.pumpAndSettle();
    expect(direction, DismissDirection.none);
    expect(find.text('Offer 10'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Offer 0'), findsOneWidget);
  });

  testWidgets('persistence failure restores the card without an exception', (
    tester,
  ) async {
    await tester.pumpWidget(
      fixture(
        onDismiss: (p, pos, dir) async {
          throw StateError('Offline');
        },
      ),
    );
    await tester.drag(find.text('Offer 0'), const Offset(450, 0));
    await tester.pumpAndSettle();
    expect(find.text('Offer 0'), findsOneWidget);
    expect(find.text('Could not save your feedback'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an account/filter revision resets the bounded reserve', (
    tester,
  ) async {
    await tester.pumpWidget(fixture());
    await tester.pumpWidget(
      fixture(revision: 'different-account|near_me', ranked: [deal(99)]),
    );
    expect(find.text('Offer 0'), findsNothing);
    expect(find.text('Offer 99'), findsOneWidget);
    await tester.drag(find.text('Offer 99'), const Offset(450, 0));
    await tester.pumpAndSettle();
    expect(find.text('No deals'), findsOneWidget);
    expect(find.text('Offer 10'), findsNothing);
  });

  testWidgets(
    'pending feedback from an old revision cannot restore a private card',
    (tester) async {
      final pending = Completer<void>();
      await tester.pumpWidget(
        fixture(onDismiss: (p, pos, dir) => pending.future),
      );
      await tester.drag(find.text('Offer 0'), const Offset(450, 0));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        fixture(revision: 'other-owner', ranked: [deal(99)]),
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Offer 99'), findsOneWidget);
      expect(find.text('Offer 0'), findsNothing);
      expect(find.text('Undo'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('updated eligibility replaces a stale cached candidate', (
    tester,
  ) async {
    await tester.pumpWidget(fixture());
    await tester.pumpWidget(
      fixture(
        ranked: List.generate(
          40,
          deal,
        ).where((p) => p.id != deal(10).id).toList(),
      ),
    );
    await tester.drag(find.text('Offer 0'), const Offset(450, 0));
    await tester.pumpAndSettle();
    expect(find.text('Offer 11'), findsOneWidget);
    expect(find.text('Offer 10'), findsNothing);
  });
}
