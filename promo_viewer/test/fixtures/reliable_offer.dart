import 'package:promo_viewer/models/promotion.dart';

Map<String, dynamic> reliableOfferJson(Map<String, dynamic> fields) {
  final json = <String, dynamic>{
    'brand': 'Example Store',
    'website_domain': 'example.com',
    'source_url': 'https://example.com/offers',
    'promotion_title': '20% off shoes',
    'discount_type': 'percentage_off',
    'discount_value': '20%',
    'redemption_method': 'in_store',
    'redemption_steps': ['Show this offer in store.'],
    'status': 'active',
    'confidence_score': 0.95,
    'global_quality_score': 90,
    ...fields,
  };
  if (json['website_domain'] == null) json['website_domain'] = 'example.com';
  json['source_url'] = 'https://${json['website_domain']}/offers';
  final offer = Promotion.fromJson(json);
  json['source_evidence'] = {
    'schema_version': 1,
    'validator': 'captured_text_v1',
    'status': 'supported',
    'source_url': json['source_url'],
    'checked_at': DateTime.now().toUtc().toIso8601String(),
    'excerpt': 'Example source passage for a trusted test offer.',
    'offer': offer.sourceEvidenceSnapshot,
  };
  return json;
}
