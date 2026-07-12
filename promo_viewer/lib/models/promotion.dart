import 'fast_redemption.dart';

class Promotion {
  final String brand;
  final String category;
  final String title;
  final String promotionType;
  final String discountType;
  final String dealScope;
  final String source; // web | email | both
  final String? discountValue;
  final String status;
  final double confidenceScore;
  final String redemptionMethod;
  final bool requiresMembership;
  final String? membershipName;
  final String? membershipCost;
  final bool requiresApp;
  final String? minimumSpend;
  final String? endDate;
  final bool purchaseRequired;
  final String? promoCode;
  final List<String> redemptionSteps;
  final String? termsText;
  final List<String> validDays;
  final String? timeStart;
  final String? timeEnd;
  final String promotionTimezone;
  final String? sourcePath;
  final String? websiteDomain;
  final String? sourceUrl;
  final String? ogImageUrl;

  // Email-only fields
  final String? visibility;   // public_general_offer | member_offer | private_user_offer
  final String? emailSubject;
  final String? senderEmail;

  final String? summary;

  final FastRedemption? fastRedemption;

  final bool birthdayRelated;

  // Pre-computed in pipeline (generate_scores.py)
  final double globalQualityScore;
  final double? estimatedSavings;

  // Local neighborhood fields (local_neighborhood source only)
  final String? neighborhood;
  final String? address;
  final double? lat;
  final double? lon;

  // Gender targeting — null means not fashion or gender-neutral
  final String? targetGender; // "women" | "men" | "kids" | "unisex"

  // Synthesis metadata — only populated on synthesized deals
  final bool synthesized;
  final String? synthesisReason;
  final List<String> productCategories;
  final List<String> productKeywordsExplicit;
  final List<String> productKeywordsContextual;
  final List<String> matchedProductExamples;

  // Set after location is resolved — not from JSON
  double? distanceKm;

  Promotion({
    required this.brand,
    required this.category,
    required this.title,
    required this.promotionType,
    required this.discountType,
    this.dealScope = 'unknown',
    this.source = 'web',
    this.discountValue,
    required this.status,
    required this.confidenceScore,
    required this.redemptionMethod,
    required this.requiresMembership,
    this.membershipName,
    this.membershipCost,
    required this.requiresApp,
    this.minimumSpend,
    this.endDate,
    this.purchaseRequired = false,
    this.promoCode,
    this.redemptionSteps = const [],
    this.termsText,
    this.validDays = const [],
    this.timeStart,
    this.timeEnd,
    this.promotionTimezone = 'America/New_York',
    this.sourcePath,
    this.websiteDomain,
    this.sourceUrl,
    this.ogImageUrl,
    this.visibility,
    this.emailSubject,
    this.senderEmail,
    this.summary,
    this.birthdayRelated = false,
    this.fastRedemption,
    this.globalQualityScore = 0.0,
    this.estimatedSavings,
    this.neighborhood,
    this.address,
    this.lat,
    this.lon,
    this.targetGender,
    this.synthesized = false,
    this.synthesisReason,
    this.productCategories = const [],
    this.productKeywordsExplicit = const [],
    this.productKeywordsContextual = const [],
    this.matchedProductExamples = const [],
  });

  factory Promotion.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['redemption_steps'];
    final steps = rawSteps is List
        ? rawSteps.whereType<String>().toList()
        : <String>[];

    return Promotion(
      brand: json['brand'] as String? ?? '',
      category: json['category'] as String? ?? 'other',
      title: json['promotion_title'] as String? ?? '',
      promotionType: json['promotion_type'] as String? ?? 'unknown',
      discountType: json['discount_type'] as String? ?? 'unknown',
      dealScope: json['deal_scope'] as String? ?? 'unknown',
      source: json['source'] as String? ?? 'web',
      discountValue: json['discount_value'] as String?,
      status: json['status'] as String? ?? 'needs_review',
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 0.0,
      redemptionMethod: json['redemption_method'] as String? ?? 'unknown',
      requiresMembership: json['requires_membership'] as bool? ?? false,
      membershipName: json['membership_name'] as String?,
      membershipCost: json['membership_cost'] as String?,
      requiresApp: json['requires_app'] as bool? ?? false,
      minimumSpend: json['minimum_spend'] as String?,
      endDate: json['end_date'] as String?,
      purchaseRequired: json['purchase_required'] as bool? ?? false,
      promoCode: json['promo_code'] as String?,
      redemptionSteps: steps,
      termsText: json['terms_text'] as String?,
      validDays: (json['valid_days'] as List?)?.whereType<String>().toList() ?? [],
      timeStart: json['time_start'] as String?,
      timeEnd: json['time_end'] as String?,
      promotionTimezone: json['timezone'] as String? ?? 'America/New_York',
      sourcePath: json['source_path'] as String?,
      websiteDomain: json['website_domain'] as String?,
      sourceUrl: json['source_url'] as String?,
      ogImageUrl: json['og_image_url'] as String?,
      visibility: json['visibility'] as String?,
      emailSubject: json['email_subject'] as String?,
      senderEmail: json['sender_email'] as String?,
      summary: json['short_summary'] as String?,
      birthdayRelated: json['birthday_related'] as bool? ?? false,
      fastRedemption: json['fast_redemption'] != null
          ? FastRedemption.fromJson(
              json['fast_redemption'] as Map<String, dynamic>)
          : null,
      globalQualityScore: ((json['global_quality_score'] ?? json['rank_base_score']) as num?)?.toDouble() ?? 0.0,
      estimatedSavings: (json['estimated_savings'] as num?)?.toDouble(),
      neighborhood: json['neighborhood'] as String?,
      address: json['address'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lon: (json['lon'] as num?)?.toDouble(),
      targetGender: json['target_gender'] as String?,
      synthesized: json['synthesized'] as bool? ?? false,
      synthesisReason: json['synthesis_reason'] as String?,
      productCategories: (json['product_categories'] as List?)?.whereType<String>().toList() ?? [],
      productKeywordsExplicit: (json['product_keywords_explicit'] as List?)?.whereType<String>().toList()
          ?? (json['product_keywords'] as List?)?.whereType<String>().toList()
          ?? [],
      productKeywordsContextual: (json['product_keywords_contextual'] as List?)?.whereType<String>().toList() ?? [],
      matchedProductExamples: (json['matched_product_examples'] as List?)?.whereType<String>().toList() ?? [],
    );
  }

  String get id {
    final raw = '${brand}_$title'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return raw.length > 100 ? raw.substring(0, 100) : raw;
  }

  // Strip subdomains → root domain (e.g. athleta.gap.com → gap.com)
  String? get rootDomain {
    final d = websiteDomain;
    if (d == null || d.isEmpty) return null;
    final parts = d.split('.');
    if (parts.length <= 2) return d;
    return parts.sublist(parts.length - 2).join('.');
  }

  String? get logoUrl {
    final root = rootDomain;
    if (root == null) return null;
    return 'https://icon.horse/icon/$root';
  }

  String? get logoFallbackUrl {
    final root = rootDomain;
    if (root == null) return null;
    return 'https://www.google.com/s2/favicons?domain=$root&sz=128';
  }

  /// Best available URL for verifying the promotion.
  String? get verifyUrl {
    if (sourceUrl != null && sourceUrl!.isNotEmpty) return sourceUrl;
    if (websiteDomain != null && websiteDomain!.isNotEmpty) return 'https://$websiteDomain';
    return null;
  }

  bool get isActive =>
      status == 'active' || status == 'probably_active' || status == 'online_only';

  bool get isLocal => source == 'local_neighborhood';

  /// Full rank score adding runtime signals (distance + membership) to the
  /// pipeline-computed base score.
  ///
  /// [distanceKm]   — null for online deals / before location is resolved.
  /// [isMember]     — true when the user's confirmed memberships match this brand.
  /// [emailAffinityCount] — how many emails from this brand are in the inbox
  ///                        (0 if not tracked; handled in pipeline, passed here
  ///                         only for tab-level re-ranking if needed).
  double rankScore({double? distanceKm, bool isMember = false}) {
    double score = globalQualityScore;

    // ── Distance bonus (Near Me tab) ──────────────────────────────────────
    if (distanceKm != null) {
      final miles = distanceKm * 0.621371;
      if (miles <= 0.5) {
        score += 30;
      } else if (miles <= 1.0) {
        score += 25;
      } else if (miles <= 2.0) {
        score += 18;
      } else if (miles <= 5.0) {
        score += 8;
      } else {
        score += 2;
      }
    }

    // ── Day-of-week factor ────────────────────────────────────────────────
    if (validDays.isNotEmpty) {
      const dayNames = ['monday','tuesday','wednesday','thursday','friday','saturday','sunday'];
      const dayShort = ['mon','tue','wed','thu','fri','sat','sun'];
      final todayIdx = DateTime.now().weekday - 1; // 0=Mon … 6=Sun
      final normalized = validDays.map((d) => d.toLowerCase()).toList();
      final validToday = normalized.any(
        (d) => d == dayNames[todayIdx] || d == dayShort[todayIdx],
      );
      if (validToday) {
        score += 5;   // deal is specifically on today — slight boost
      } else {
        score -= 20;  // deal not valid today — rank below general deals
      }
    }

    // ── Membership bonus ───────────────────────────────────────────────────
    if (isMember) {
      score += 25;
    } else if (!requiresMembership) {
      score += 8;
    } else {
      final cost = (membershipCost ?? '').toLowerCase();
      if (cost.contains('free')) {
        score -= 2;
      } else if (cost.contains('paid')) {
        score -= 15;
      } else {
        score -= 5;
      }
    }

    return score;
  }

  bool get isValidToday {
    if (validDays.isEmpty) return true;
    const dayNames = ['monday','tuesday','wednesday','thursday','friday','saturday','sunday'];
    const dayShort = ['mon','tue','wed','thu','fri','sat','sun'];
    final todayIdx = DateTime.now().weekday - 1;
    final normalized = validDays.map((d) => d.toLowerCase()).toList();
    return normalized.any((d) => d == dayNames[todayIdx] || d == dayShort[todayIdx]);
  }

  /// Legacy value-only score (kept for backwards compatibility).
  double get dealScore {
    double base = 0;

    switch (discountType) {
      case 'free_item':
        base = 85;
      case 'percentage_off':
        final pct = _extractPercent(discountValue);
        base = pct != null ? (40 + pct.clamp(0, 100) * 0.6) : 55;
      case 'amount_off':
        final amt = _extractDollars(discountValue);
        base = amt != null ? (40 + (amt / 5).clamp(0, 40)) : 50;
      case 'sale_price':
        base = 50;
      case 'free_shipping':
        base = 35;
      case 'points':
        base = 20;
      default:
        base = 15;
    }

    return (base * confidenceScore).clamp(0, 100);
  }

  static double? _extractPercent(String? v) {
    if (v == null) return null;
    final m = RegExp(r'(\d+(?:\.\d+)?)%').firstMatch(v);
    return m != null ? double.tryParse(m.group(1)!) : null;
  }

  static double? _extractDollars(String? v) {
    if (v == null) return null;
    final m = RegExp(r'\$(\d+(?:\.\d+)?)').firstMatch(v);
    return m != null ? double.tryParse(m.group(1)!) : null;
  }

  String get displayValue {
    if (discountValue != null && discountValue!.isNotEmpty) return discountValue!;
    switch (discountType) {
      case 'free_shipping': return 'Free Shipping';
      case 'free_item':     return 'Free Item';
      case 'points':        return 'Points';
      default:              return '';
    }
  }
}
