import '../models/promotion.dart';
import 'ranking_contract.dart';
import 'preference_features.dart';

Map<String, dynamic> dealFeedbackMetadata(
  Promotion p, {
  String? rankingMode,
  int? feedPosition,
  double? runtimeScore,
}) {
  final m = <String, dynamic>{
    'brand_id': p.brand.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_'),
    'value_tier': _valueTier(p.globalQualityScore),
    'effort_type': _effortType(p),
    'deal_source': p.source,
    'source_group': p.isEmailDerived ? 'email' : 'public',
    'ranking_version': RankingContract.version,
    'confidence_score': p.confidenceScore,
    'feature_schema': preferenceFeatureVersion,
    'offer_features': preferenceOfferSnapshot(p),
  };
  if (p.personalRankScore != null) {
    m['personal_rank_score'] = p.personalRankScore;
  }
  if (p.personalRankModel != null) {
    m['personal_rank_model'] = p.personalRankModel;
  }
  if (runtimeScore != null) m['runtime_score'] = runtimeScore;
  if (p.globalQualityScore > 0) {
    m['global_quality_score'] = p.globalQualityScore;
  }
  if (p.economicValueScore > 0) {
    m['economic_value_score'] = p.economicValueScore;
  }
  if (p.effectiveDiscountPct > 0) {
    m['effective_discount_pct'] = p.effectiveDiscountPct;
  }
  final end = p.endDate == null ? null : DateTime.tryParse(p.endDate!);
  final days = end?.difference(DateTime.now()).inDays;
  if (days != null && days >= 0) m['days_until_expiry'] = days;
  if (rankingMode != null) m['ranking_mode'] = rankingMode;
  if (feedPosition != null) m['feed_position'] = feedPosition;
  return m;
}

String _valueTier(double score) {
  if (score >= 80) return 'excellent';
  if (score >= 65) return 'great';
  if (score >= 50) return 'good';
  if (score >= 35) return 'fair';
  if (score > 0) return 'low';
  return 'unscored';
}

String _effortType(Promotion p) {
  final fr = p.fastRedemption;
  if (fr != null && fr.eligible) return fr.isLowEffort ? 'instant' : 'easy';
  if (p.requiresApp) return 'app_required';
  if (p.promoCode != null) return 'code_required';
  if (!p.requiresMembership) return 'easy';
  return 'membership_required';
}
