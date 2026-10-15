import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/models/promotion.dart';
import 'package:promo_viewer/services/interaction_service.dart';
import 'package:promo_viewer/services/saved_deals_service.dart';
import 'package:promo_viewer/utils/deal_feed_feedback.dart';
import 'package:promo_viewer/utils/feed_ranker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/reliable_offer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Promotion offer;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SavedDealsService.init();
    await InteractionService.init();
    offer = Promotion.fromJson(reliableOfferJson({}));
  });

  for (final mode in ['for_you', 'near_me']) {
    test(
      '$mode right swipe saves, does not dismiss, and Undo removes only its save',
      () async {
        final undo = await recordDealFeedFeedback(
          offer,
          position: 1,
          rankingMode: mode,
          action: DealFeedAction.save,
          swipeDirection: 'right',
        );
        expect(SavedDealsService().isSaved(offer.id), isTrue);
        expect(InteractionService().isDealSkipped(offer.id), isFalse);
        expect(isFeedWorthy(offer), isFalse);
        await undo();
        expect(SavedDealsService().isSaved(offer.id), isFalse);
        expect(InteractionService().isDealSkipped(offer.id), isFalse);
        expect(isFeedWorthy(offer), isTrue);
      },
    );

    test(
      '$mode left swipe dismisses without saving, and Undo cancels it',
      () async {
        final undo = await recordDealFeedFeedback(
          offer,
          position: 2,
          rankingMode: mode,
          action: DealFeedAction.dismiss,
          swipeDirection: 'left',
        );
        expect(SavedDealsService().isSaved(offer.id), isFalse);
        expect(InteractionService().isDealSkipped(offer.id), isTrue);
        await undo();
        expect(InteractionService().isDealSkipped(offer.id), isFalse);
      },
    );
  }

  test('Undo cannot remove a save that existed before the swipe', () async {
    await SavedDealsService().save(offer);
    final undo = await recordDealFeedFeedback(
      offer,
      position: 1,
      rankingMode: 'for_you',
      action: DealFeedAction.save,
      swipeDirection: 'right',
    );
    await undo();
    expect(SavedDealsService().isSaved(offer.id), isTrue);
    expect(SavedDealsService().all, hasLength(1));
  });

  test('Undo cannot remove a later replacement save', () async {
    final undo = await recordDealFeedFeedback(
      offer,
      position: 1,
      rankingMode: 'for_you',
      action: DealFeedAction.save,
      swipeDirection: 'right',
    );
    await SavedDealsService().unsave(offer.id);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await SavedDealsService().save(offer);
    await undo();
    expect(SavedDealsService().isSaved(offer.id), isTrue);
  });
}
