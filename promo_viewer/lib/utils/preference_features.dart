import 'dart:math' as math;

import '../models/promotion.dart';
import '../models/user_prefs.dart';

const preferenceFeatureVersion = 1;
const preferenceFeatureNames = [
  'quality',
  'economic_value',
  'confidence',
  'discount',
  'requires_membership',
  'has_membership',
  'membership_known',
  'requires_app',
  'purchase_required',
  'minimum_spend_required',
  'online_only',
  'email',
  'favorite_brand',
  'favorite_category',
  'priority_match',
  'brand_preference',
  'brand_evidence',
  'category_preference',
  'category_evidence',
  'type_preference',
  'type_evidence',
  'membership_preference',
  'membership_evidence',
  'total_evidence',
  'discount_free',
  'discount_percentage',
  'discount_amount',
  'discount_points',
  'discount_bogo',
  'promotion_reward',
];

String _norm(String value) => value.trim().toLowerCase();
double _unit(num value) => value.toDouble().clamp(0.0, 1.0);

Map<String, dynamic> preferenceOfferSnapshot(Promotion p) => {
  'brand': _norm(p.brand),
  'category': _norm(p.category),
  'promotion_type': _norm(p.promotionType),
  'discount_type': _norm(p.discountType),
  'requires_membership': p.requiresMembership,
};

class _Evidence {
  Map<String, dynamic> offer;
  bool saved = false;
  bool dismissed = false;
  int saveSequence = 0;
  int dismissSequence = 0;
  DateTime savedAt;
  DateTime dismissedAt;

  _Evidence(this.offer, DateTime at) : savedAt = at, dismissedAt = at;
  int get label => dismissed && (!saved || dismissSequence > saveSequence)
      ? -1
      : saved
      ? 1
      : 0;
  DateTime get at => label > 0 ? savedAt : dismissedAt;
}

/// A bounded, account-scoped summary. Repeated actions are not extra evidence.
class PreferenceProfile {
  final Map<String, _Evidence> _deals = {};

  bool isDismissed(String id) => _deals[id]?.dismissed ?? false;

  void clear() => _deals.clear();

  void apply(Map<String, dynamic> event) {
    final type = event['event_type'];
    if (!const {
      'deal_saved',
      'deal_unsaved',
      'not_interested',
      'not_interested_undone',
    }.contains(type)) {
      return;
    }
    final id = event['promotion_id'];
    if (id is! String || id.isEmpty) return;
    final at = DateTime.tryParse(event['created_at'] as String? ?? '');
    if (at == null) return;
    final meta = event['metadata'] is Map ? event['metadata'] as Map : const {};
    final raw = meta['offer_features'];
    final offer = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{
            'brand': _norm(event['brand'] as String? ?? ''),
            'category': _norm(event['category'] as String? ?? ''),
          };
    final sequence =
        int.tryParse('${meta['event_sequence']}') ?? at.microsecondsSinceEpoch;
    final evidence = _deals.putIfAbsent(id, () => _Evidence(offer, at));
    if (type == 'deal_saved' && sequence >= evidence.saveSequence) {
      evidence.saved = true;
      evidence.savedAt = at;
      evidence.saveSequence = sequence;
      evidence.offer = offer;
    } else if (type == 'deal_unsaved' && sequence >= evidence.saveSequence) {
      evidence.saved = false;
      evidence.saveSequence = sequence;
    } else if (type == 'not_interested' &&
        sequence >= evidence.dismissSequence) {
      evidence.dismissed = true;
      evidence.dismissedAt = at;
      evidence.dismissSequence = sequence;
      evidence.offer = offer;
    } else if (type == 'not_interested_undone' &&
        sequence >= evidence.dismissSequence) {
      evidence.dismissed = false;
      evidence.dismissSequence = sequence;
    }
    if (_deals.length > 1000) _deals.remove(_deals.keys.first);
  }

  Map<String, double> features(
    Promotion p, {
    UserPrefs? prefs,
    bool? isMember,
    DateTime? now,
  }) {
    final time = now ?? DateTime.now().toUtc();
    final offer = preferenceOfferSnapshot(p);
    final sums = <String, List<double>>{
      for (final key in ['brand', 'category', 'type', 'membership'])
        key: [0, 0],
    };
    double total = 0;
    for (final entry in _deals.entries) {
      if (entry.key == p.id) continue;
      final e = entry.value;
      if (e.label == 0) continue;
      final days = time.difference(e.at).inSeconds / 86400;
      if (days < 0 || days > 90) continue;
      final weight = math.pow(0.5, days / 30).toDouble();
      total += weight;
      final matches = {
        'brand': offer['brand'] != '' && offer['brand'] == e.offer['brand'],
        'category':
            offer['category'] != '' && offer['category'] == e.offer['category'],
        'type':
            offer['promotion_type'] == e.offer['promotion_type'] &&
            offer['discount_type'] == e.offer['discount_type'],
        'membership':
            offer['requires_membership'] == e.offer['requires_membership'],
      };
      for (final key in sums.keys) {
        if (matches[key]!) {
          sums[key]![0] += weight * e.label;
          sums[key]![1] += weight;
        }
      }
    }
    final priorities = prefs?.dealPriorities.map(_norm).toSet() ?? <String>{};
    final bogo = RegExp(
      r'\bbogo\b|buy.one.get.one',
      caseSensitive: false,
    ).hasMatch(p.title);
    final matched =
        (priorities.contains('free') && p.discountType == 'free_item') ||
        (priorities.contains('bogo') && bogo) ||
        (priorities.contains('discount') &&
            const {
              'percentage_off',
              'amount_off',
              'sale_price',
            }.contains(p.discountType)) ||
        (priorities.contains('online') && p.dealScope == 'online_only') ||
        (priorities.contains('nearby') && p.distanceKm != null) ||
        (priorities.contains('rewards') && p.requiresMembership);
    return {
      'quality': _unit(p.globalQualityScore / 100),
      'economic_value': _unit(p.economicValueScore / 100),
      'confidence': _unit(p.confidenceScore),
      'discount': _unit(p.effectiveDiscountPct / 100),
      'requires_membership': p.requiresMembership ? 1 : 0,
      'has_membership': isMember == true ? 1 : 0,
      'membership_known': isMember == null ? 0 : 1,
      'requires_app': p.requiresApp ? 1 : 0,
      'purchase_required': p.purchaseRequired ? 1 : 0,
      'minimum_spend_required': p.minimumSpend?.trim().isNotEmpty == true
          ? 1
          : 0,
      'online_only': p.dealScope == 'online_only' ? 1 : 0,
      'email': p.isEmailDerived ? 1 : 0,
      'favorite_brand':
          prefs?.favoriteBrands.any((b) => _norm(b) == offer['brand']) == true
          ? 1
          : 0,
      'favorite_category':
          prefs?.favoriteCategories.any((c) => _norm(c) == offer['category']) ==
              true
          ? 1
          : 0,
      'priority_match': matched ? 1 : 0,
      for (final key in sums.keys) ...{
        '${key}_preference': sums[key]![0] / (sums[key]![1] + 4),
        '${key}_evidence': _unit(sums[key]![1] / 20),
      },
      'total_evidence': _unit(total / 20),
      'discount_free': p.discountType == 'free_item' ? 1 : 0,
      'discount_percentage': p.discountType == 'percentage_off' ? 1 : 0,
      'discount_amount': p.discountType == 'amount_off' ? 1 : 0,
      'discount_points': p.discountType == 'points' ? 1 : 0,
      'discount_bogo': bogo ? 1 : 0,
      'promotion_reward':
          const {'reward', 'membership_benefit'}.contains(p.promotionType)
          ? 1
          : 0,
    };
  }
}
