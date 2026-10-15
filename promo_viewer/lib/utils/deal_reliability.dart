import 'package:timezone/timezone.dart' as tz;

import '../models/promotion.dart';
import 'source_link.dart';

const reliabilityVersion = 'captured_source_v1';
const sourceEvidenceMaxAge = Duration(days: 14);

class DealReliability {
  final List<String> reasons;
  final DateTime? checkedAt;
  bool get eligible => reasons.isEmpty;

  DealReliability(Iterable<String> reasons, this.checkedAt)
    : reasons = List.unmodifiable(reasons);
}

DateTime? sourceCaptureDate(String? raw) {
  if (raw == null ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d+)?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$',
      ).hasMatch(raw)) {
    return null;
  }
  final day = DateTime.tryParse(raw.substring(0, 10));
  if (day == null ||
      day.toIso8601String().substring(0, 10) != raw.substring(0, 10)) {
    return null;
  }
  return DateTime.tryParse(raw)?.toUtc();
}

DateTime? _offerBoundary(String raw, String timezone, {required bool end}) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
  if (match == null) return sourceCaptureDate(raw);
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final calendar = DateTime.utc(year, month, day);
  if (calendar.year != year || calendar.month != month || calendar.day != day) {
    return null;
  }
  try {
    final location = tz.getLocation(timezone);
    return tz.TZDateTime(location, year, month, day + (end ? 1 : 0)).toUtc();
  } catch (_) {
    return null;
  }
}

DealReliability assessDealReliability(Promotion p, {DateTime? now}) {
  final time = (now ?? DateTime.now()).toUtc();
  final reasons = <String>[];
  if (p.brand.trim().isEmpty) reasons.add('missing_brand');
  if (p.title.trim().isEmpty) reasons.add('missing_title');
  if (!p.confidenceScore.isFinite ||
      p.confidenceScore < 0 ||
      p.confidenceScore > 1 ||
      !p.globalQualityScore.isFinite) {
    reasons.add('invalid_scores');
  }
  if (p.extractionStatus != null && p.extractionStatus != 'success') {
    reasons.add('extraction_not_successful');
  }
  if (p.verifyUrl == null) reasons.add('missing_trusted_source_link');
  if (!const {
    'online',
    'in_store',
    'in_app',
    'app_reward',
    'show_code',
    'scan_barcode',
    'open_maps',
  }.contains(p.redemptionMethod)) {
    reasons.add('unknown_redemption_method');
  }
  if (!p.redemptionSteps.any((step) => step.trim().isNotEmpty)) {
    reasons.add('missing_redemption_steps');
  }
  if (p.requiresMembership && (p.membershipName?.trim().isEmpty ?? true)) {
    reasons.add('missing_membership_name');
  }
  if ((p.promotionType == 'coupon' || p.redemptionMethod == 'show_code') &&
      (p.promoCode?.trim().isEmpty ?? true)) {
    reasons.add('missing_promo_code');
  }
  if (p.discountType == 'unknown' ||
      (!const {'free_item', 'free_shipping'}.contains(p.discountType) &&
          (p.discountValue?.trim().isEmpty ?? true))) {
    reasons.add('missing_concrete_value');
  }

  final start = p.startDate == null
      ? null
      : _offerBoundary(p.startDate!, p.promotionTimezone, end: false);
  final end = p.endDate == null
      ? null
      : _offerBoundary(p.endDate!, p.promotionTimezone, end: true);
  if (p.startDate != null && start == null) reasons.add('invalid_start_date');
  if (p.endDate != null && end == null) reasons.add('invalid_end_date');
  if (start != null && time.isBefore(start)) reasons.add('offer_not_started');
  if (end != null && !time.isBefore(end)) reasons.add('offer_expired');
  if (start != null && end != null && !start.isBefore(end)) {
    reasons.add('invalid_date_range');
  }

  final evidence = p.sourceEvidence;
  final checked = sourceCaptureDate(evidence?.checkedAt);
  if (evidence == null ||
      evidence.schemaVersion != 1 ||
      evidence.validator != 'captured_text_v1' ||
      evidence.status != 'supported' ||
      (evidence.excerpt?.trim().isEmpty ?? true)) {
    reasons.add('source_evidence_missing');
  } else if (!evidence.matchesOffer(p.sourceEvidenceSnapshot) ||
      !sourceMatchesDomain(evidence.sourceUrl, p.websiteDomain) ||
      evidence.sourceUrl != p.sourceUrl) {
    reasons.add('source_evidence_mismatch');
  }
  if (checked == null) {
    reasons.add('source_capture_date_missing');
  } else if (checked.isAfter(time.add(const Duration(minutes: 5)))) {
    reasons.add('source_capture_date_in_future');
  } else if (time.difference(checked) > sourceEvidenceMaxAge) {
    reasons.add('source_evidence_stale');
  }
  return DealReliability(reasons, checked);
}
