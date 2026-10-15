import 'dart:async';

import '../models/promotion.dart';
import '../services/interaction_service.dart';
import '../services/saved_deals_service.dart';
import '../services/supabase_service.dart';

enum DealFeedAction { save, dismiss }

typedef UndoDealFeedback = Future<void> Function();
typedef DealFeedbackCallback =
    Future<UndoDealFeedback> Function(
      Promotion promo,
      int position,
      DealFeedAction action,
      String? swipeDirection,
    );

Future<UndoDealFeedback> recordDealFeedFeedback(
  Promotion promo, {
  required int position,
  required String rankingMode,
  required DealFeedAction action,
  String? swipeDirection,
}) async {
  final owner = SupabaseService.currentUserId;
  final interactions = InteractionService();
  final saved = SavedDealsService();
  final meta = {
    ...InteractionService.promoMeta(
      promo,
      rankingMode: rankingMode,
      feedPosition: position,
    ),
    'feedback_method': swipeDirection == null ? 'menu' : 'swipe',
    'feedback_action': action.name,
    'swipe_direction': ?swipeDirection,
  };
  unawaited(
    interactions.recordFeedImpression(
      promo,
      rankingMode: rankingMode,
      feedPosition: position,
    ),
  );
  if (action == DealFeedAction.save) {
    final wasSaved = saved.isSaved(promo.id);
    await saved.save(promo, feedbackMeta: meta);
    final savedAt = saved.get(promo.id)?.savedAt;
    return () async {
      if (owner != SupabaseService.currentUserId || wasSaved) return;
      if (saved.get(promo.id)?.savedAt != savedAt) return;
      await saved.unsave(promo.id, feedbackMeta: meta);
    };
  }
  try {
    await interactions.skipDeal(
      promo.id,
      brand: promo.brand,
      category: promo.category,
      meta: meta,
    );
  } catch (_) {
    if (owner == SupabaseService.currentUserId) {
      await interactions.unskipDeal(
        promo.id,
        brand: promo.brand,
        category: promo.category,
        meta: meta,
      );
    }
    rethrow;
  }
  return () async {
    if (owner != SupabaseService.currentUserId) return;
    await interactions.unskipDeal(
      promo.id,
      brand: promo.brand,
      category: promo.category,
      meta: meta,
    );
  };
}
