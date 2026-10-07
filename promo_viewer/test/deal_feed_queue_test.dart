import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/models/promotion.dart';
import 'package:promo_viewer/utils/deal_feed_queue.dart';

Promotion deal(int index, {String source = 'web'}) => Promotion.fromJson({
  'brand': 'Brand $index',
  'promotion_title': 'Offer $index',
  'source': source,
});

void main() {
  test('keeps exactly 10 visible and at most 30 in reserve', () {
    final queue = DealFeedQueue()..reset(List.generate(60, deal));
    expect(queue.visible.length, 10);
    expect(queue.reserve.length, 30);
    expect(queue.visible.first.id, deal(0).id);
    expect(queue.reserve.first.id, deal(10).id);
  });

  test('reject is immediately replaced at the same position', () {
    final queue = DealFeedQueue()..reset(List.generate(40, deal));
    queue.dismiss(deal(2).id);
    expect(queue.visible.length, 10);
    expect(queue.visible[2].id, deal(10).id);
    expect(queue.reserve.length, 29);
    expect(queue.visible.any((p) => p.id == deal(2).id), isFalse);
  });

  test('undo restores the card and returns its replacement to reserve', () {
    final queue = DealFeedQueue()..reset(List.generate(40, deal));
    final dismissed = queue.dismiss(deal(2).id)!;
    expect(queue.undo(dismissed), isTrue);
    expect(
      queue.visible.map((p) => p.id),
      List.generate(10, (i) => deal(i).id),
    );
    expect(queue.reserve.first.id, deal(10).id);
    expect(queue.undo(dismissed), isFalse);
  });

  test('exhausted reserve never manufactures or repeats offers', () {
    final queue = DealFeedQueue()..reset(List.generate(3, deal));
    for (var i = 0; i < 3; i++) {
      queue.dismiss(deal(i).id);
    }
    queue.reconcile(List.generate(3, deal));
    expect(queue.visible, isEmpty);
    expect(queue.reserve, isEmpty);
  });

  test(
    'reconciliation excludes rejects and refills from qualified candidates',
    () {
      final queue = DealFeedQueue()..reset(List.generate(40, deal));
      queue.dismiss(deal(0).id);
      queue.reconcile(List.generate(50, deal));
      expect(queue.visible.length, 10);
      expect(queue.reserve.length, 30);
      expect(queue.visible.first.id, deal(10).id);
      expect(
        [...queue.visible, ...queue.reserve].any((p) => p.id == deal(0).id),
        isFalse,
      );
    },
  );

  test('reset cannot leak the previous account or filter reserve', () {
    final queue = DealFeedQueue()..reset(List.generate(40, deal));
    queue.dismiss(deal(0).id);
    queue.reset([deal(99, source: 'email')]);
    expect(queue.visible.single.id, deal(99).id);
    expect(queue.reserve, isEmpty);
    queue.reset([deal(0)]);
    expect(queue.visible.single.id, deal(0).id);
  });

  test(
    'reconciliation updates source metadata without shifting kept cards',
    () {
      final queue = DealFeedQueue()..reset(List.generate(12, deal));
      queue.reconcile([
        deal(0, source: 'email'),
        ...List.generate(11, (i) => deal(i + 1)),
      ]);
      expect(queue.visible.first.isEmailDerived, isTrue);
      expect(queue.visible[1].id, deal(1).id);
    },
  );

  test('duplicate candidates occupy only one queue slot', () {
    final queue = DealFeedQueue()..reset([deal(0), deal(0), deal(1)]);
    expect(queue.visible.length, 2);
  });

  test('undo does not resurrect a separately rejected replacement', () {
    final queue = DealFeedQueue()..reset(List.generate(40, deal));
    final first = queue.dismiss(deal(0).id)!;
    queue.dismiss(deal(10).id);
    queue.undo(first);
    expect(queue.visible.first.id, deal(0).id);
    expect(queue.visible.length, 10);
    expect(
      [...queue.visible, ...queue.reserve].any((p) => p.id == deal(10).id),
      isFalse,
    );
  });
}
