import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/fast_redemption.dart';
import '../models/promotion.dart';
import '../services/interaction_service.dart';
import '../services/promotions_service.dart';
import '../services/location_service.dart';
import '../services/saved_deals_service.dart';
import '../services/timezone_service.dart';
import '../theme/candy_colors.dart';
import '../widgets/brand_logo.dart';
import '../widgets/effort_chip.dart';
import '../widgets/fast_redeem_button.dart';
import '../widgets/save_sheet.dart';
import '../widgets/status_chip.dart';
import '../widgets/urgency_chip.dart';
import '../widgets/value_tier_badge.dart';

class DealDetailScreen extends StatefulWidget {
  final Promotion promo;
  final String? rankingMode;
  final int? feedPosition;
  const DealDetailScreen({
    super.key,
    required this.promo,
    this.rankingMode,
    this.feedPosition,
  });

  @override
  State<DealDetailScreen> createState() => _DealDetailScreenState();
}

class _DealDetailScreenState extends State<DealDetailScreen> {
  final _scrollController = ScrollController();
  bool _hasTrackedScroll = false;
  bool _hasTrackedHistorical = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final maxExtent = pos.maxScrollExtent;
    if (maxExtent <= 0) return;
    final depth = pos.pixels / maxExtent;

    if (!_hasTrackedScroll && depth >= 0.5) {
      _hasTrackedScroll = true;
      InteractionService().recordDetailScrolled(
        widget.promo.id,
        brand: widget.promo.brand,
        meta: InteractionService.promoMeta(
          widget.promo,
          rankingMode: widget.rankingMode,
          feedPosition: widget.feedPosition,
        ),
      );
    }
    final hasHistorical = widget.promo.globalQualityScore >= 40;
    if (hasHistorical && !_hasTrackedHistorical && depth >= 0.35) {
      _hasTrackedHistorical = true;
      InteractionService().recordHistoricalComparisonViewed(
        widget.promo.id,
        brand: widget.promo.brand,
        meta: InteractionService.promoMeta(
          widget.promo,
          rankingMode: widget.rankingMode,
          feedPosition: widget.feedPosition,
        ),
      );
    }
  }

  Promotion get _p => widget.promo;

  bool get _hasSticky => _p.fastRedemption != null && _p.fastRedemption!.eligible;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Candy.cream,
      bottomNavigationBar: _hasSticky
          ? _StickyRedeemBar(fr: _p.fastRedemption!, promo: _p)
          : null,
      appBar: AppBar(
        backgroundColor: Candy.cream,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Candy.chocolate,
        title: Text(
          _p.brand,
          style: const TextStyle(
            color: Candy.chocolate,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [_DetailSaveButton(promo: _p)],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              // 1. Hero: brand + title + quality badge + primary CTA
              _DealHeroSection(promo: _p, hasSticky: _hasSticky),
              const SizedBox(height: 10),

              // 2. Savings breakdown (when we have a meaningful estimate)
              if (_p.estimatedSavings != null && _p.estimatedSavings! >= 5) ...[
                _SavingsBreakdownCard(promo: _p),
                const SizedBox(height: 10),
              ],

              // 3. Quick summary — answers "should I redeem?" in 3 bullets
              _QuickSummaryCard(promo: _p),
              const SizedBox(height: 10),

              // 4. Source trust
              if (_p.source == 'web' && _p.verifyUrl != null) ...[
                _TrustCard(
                  domain: _p.websiteDomain ?? _p.brand,
                  url: _p.verifyUrl!,
                  score: _p.confidenceScore,
                  promoId: _p.id,
                  brand: _p.brand,
                ),
                const SizedBox(height: 10),
              ],

              // 5. Historical comparison (when quality score is meaningful)
              if (_p.globalQualityScore >= 40) ...[
                _HistoricalComparisonCard(promo: _p),
                const SizedBox(height: 10),
              ],

              // 6. Why this deal is good (from explanation codes)
              if (_hasWhyContent(_p)) ...[
                _WhyGoodDealSection(promo: _p),
                const SizedBox(height: 10),
              ],

              // 7. Promo code
              if (_p.promoCode != null) ...[
                _PromoCodeCard(promo: _p),
                const SizedBox(height: 10),
              ],

              // 8. Eligibility ("Can I use this?")
              _EligibilityCard(promo: _p),
              const SizedBox(height: 10),

              // 9. Step-by-step redemption
              if (_p.redemptionSteps.isNotEmpty) ...[
                _RedemptionStepsCard(steps: _p.redemptionSteps),
                const SizedBox(height: 10),
              ],

              // 10. Day/time availability
              if (_p.validDays.isNotEmpty || _p.timeStart != null) ...[
                _WhenCard(promo: _p),
                const SizedBox(height: 10),
              ],


            ],
          ),
        ),
      ),
    );
  }

  static bool _hasWhyContent(Promotion p) {
    return p.valueExplanationCodes.any((c) => _positiveCode(c));
  }

  static bool _positiveCode(String c) =>
      c != 'HIGH_SPEND_REQUIRED' && c != 'LOW_CONFIDENCE_WARNING';
}

// ---------------------------------------------------------------------------
// 1. Deal hero section
// ---------------------------------------------------------------------------

class _DealHeroSection extends StatelessWidget {
  final Promotion promo;
  final bool hasSticky;
  const _DealHeroSection({required this.promo, required this.hasSticky});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BrandLogo(promo: promo, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  promo.brand,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Candy.chocolate,
                  ),
                ),
              ),
              StatusChip(status: promo.status),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            promo.title,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              height: 1.3,
              letterSpacing: -0.3,
              color: Candy.chocolate,
            ),
          ),
          const SizedBox(height: 12),
          // Quality badge + effort + urgency chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (promo.globalQualityScore > 0)
                ValueTierBadge(qualityScore: promo.globalQualityScore, fontSize: 12),
              EffortChip(promo: promo),
              UrgencyChip(promo: promo),
              if (promo.endDate != null && UrgencyChip(promo: promo).build(context) is SizedBox)
                _TagChip(
                  label: 'Expires ${promo.endDate!}',
                  icon: Icons.calendar_today_outlined,
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Discount value badge + category
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (promo.displayValue.isNotEmpty)
                _ValueBadge(value: promo.displayValue, type: promo.discountType),
              _TagChip(label: _capitalize(promo.category)),
              if (promo.redemptionMethod != 'unknown')
                _TagChip(label: _formatRedemption(promo.redemptionMethod)),
            ],
          ),
          if (promo.minimumSpend != null) ...[
            const SizedBox(height: 6),
            Text(
              'Min spend: ${promo.minimumSpend}',
              style: const TextStyle(fontSize: 12, color: Candy.muted),
            ),
          ],
          if (promo.verifyUrl != null && !hasSticky) ...[
            const SizedBox(height: 16),
            _ShopNowButton(promo: promo),
          ],
        ],
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');

  static String _formatRedemption(String r) => const {
        'in_app':       'In app',
        'in_store':     'In store',
        'online':       'Online',
        'show_code':    'Promo code',
        'scan_barcode': 'Scan barcode',
      }[r] ?? r;
}

// ---------------------------------------------------------------------------
// 2. Savings breakdown card
// ---------------------------------------------------------------------------

class _SavingsBreakdownCard extends StatelessWidget {
  final Promotion promo;
  const _SavingsBreakdownCard({required this.promo});

  static String _contextNote(Promotion p) {
    return switch (p.discountType) {
      'free_item'      => 'Free item added to your order',
      'free_shipping'  => 'Shipping cost eliminated from your order',
      'points'         => 'Earned toward future rewards',
      'cashback'       => 'Credited back after purchase',
      _                => 'Estimated vs. typical full price',
    };
  }

  @override
  Widget build(BuildContext context) {
    final savings = promo.estimatedSavings!;
    final pct = promo.effectiveDiscountPct > 0 ? promo.effectiveDiscountPct / 100 : null;
    final rawUsual = pct != null && pct < 1.0 ? savings / pct : null;
    // Suppress price comparison when implied "usual" would be implausibly high.
    final usualPrice = (rawUsual != null && rawUsual <= 500) ? rawUsual : null;
    final todayPrice = usualPrice != null ? usualPrice - savings : null;
    final discountPct = promo.effectiveDiscountPct > 0
        ? promo.effectiveDiscountPct.round()
        : null;

    // Fraction of the original price the user actually pays (for the visual bar).
    final paidFraction = pct != null ? (1.0 - pct).clamp(0.0, 1.0) : null;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero: what you actually spend (when known), otherwise fall back to savings
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todayPrice != null ? 'YOU PAY' : 'YOU SAVE',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Candy.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      todayPrice != null
                          ? '~\$${todayPrice.round()}'
                          : '~\$${savings.round()}',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.5,
                        height: 1.0,
                        color: todayPrice != null ? Candy.chocolate : Candy.mint,
                      ),
                    ),
                  ],
                ),
              ),
              if (discountPct != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Candy.mint.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Candy.mint.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    '$discountPct%\nOFF',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Candy.mint,
                      height: 1.15,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
            ],
          ),

          // Price comparison (when we have enough data for before/after)
          if (usualPrice != null && todayPrice != null && paidFraction != null) ...[
            const SizedBox(height: 16),
            _SpendBar(paidFraction: paidFraction, savingsAmount: savings.round()),
            const SizedBox(height: 14),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _PriceColumn(
                      label: 'Regular price',
                      price: '~\$${usualPrice.round()}',
                      strikethrough: true,
                      color: Candy.muted,
                    ),
                  ),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Candy.border,
                    indent: 4,
                    endIndent: 4,
                  ),
                  Expanded(
                    child: _PriceColumn(
                      label: 'You save',
                      price: '~\$${savings.round()}',
                      strikethrough: false,
                      color: Candy.mint,
                      bold: true,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              _contextNote(promo),
              style: const TextStyle(
                fontSize: 13,
                color: Candy.muted,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpendBar extends StatelessWidget {
  /// [paidFraction] is the portion of regular price the user pays (0–1).
  /// [savingsAmount] is the dollar savings shown in the label.
  final double paidFraction;
  final int savingsAmount;
  const _SpendBar({required this.paidFraction, required this.savingsAmount});

  @override
  Widget build(BuildContext context) {
    final paidPct  = (paidFraction * 100).round().clamp(1, 99);
    final savedPct = (100 - paidPct).clamp(1, 99);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(
            children: [
              // Paid portion — chocolate/dark
              Expanded(
                flex: paidPct,
                child: Container(height: 8, color: Candy.chocolate.withValues(alpha: 0.18)),
              ),
              // Saved portion — mint/green
              Expanded(
                flex: savedPct,
                child: Container(height: 8, color: Candy.mint),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: Candy.mint, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              '\$$savingsAmount saved',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Candy.mint,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PriceColumn extends StatelessWidget {
  final String label;
  final String price;
  final bool strikethrough;
  final Color color;
  final bool bold;
  const _PriceColumn({
    required this.label,
    required this.price,
    required this.strikethrough,
    required this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Candy.muted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          price,
          style: TextStyle(
            fontSize: 16,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            color: color,
            decoration: strikethrough ? TextDecoration.lineThrough : null,
            decorationColor: Candy.muted,
            decorationThickness: 2,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Quick summary card — 3-bullet answer to "should I redeem?"
// ---------------------------------------------------------------------------

class _QuickSummaryCard extends StatelessWidget {
  final Promotion promo;
  const _QuickSummaryCard({required this.promo});

  static String? _codeToText(String code, Promotion p) {
    return switch (code) {
      'HIGH_EFFECTIVE_DISCOUNT' => 'Higher discount than ${p.brand} usually offers',
      'STRONG_DISCOUNT'         => 'Strong discount — above average for this category',
      'HIGH_VALUE_SAVINGS'      => 'Saves more than \$50 — significant dollar value',
      'GOOD_VALUE_SAVINGS'      => 'Solid dollar savings on this purchase',
      'NO_MEMBERSHIP_REQUIRED'  => 'No membership required — open to everyone',
      'LOW_REDEMPTION_FRICTION' => 'Easy to redeem — no extra steps',
      'NO_PURCHASE_MINIMUM'     => 'No minimum spend — works on any purchase amount',
      'STRONG_ECONOMIC_VALUE'   => 'Strong overall value for this type of promotion',
      _                         => null,
    };
  }

  List<String> _bullets() {
    final result = <String>[];

    for (final code in promo.valueExplanationCodes) {
      if (result.length >= 3) break;
      final text = _codeToText(code, promo);
      if (text != null) result.add(text);
    }

    // Fallbacks from structured fields
    if (result.length < 3 && !promo.requiresMembership) {
      const line = 'No membership required — open to everyone';
      if (!result.contains(line)) result.add(line);
    }
    if (result.length < 3 && !promo.requiresApp) {
      const line = 'No app required — works without installing anything';
      if (!result.contains(line)) result.add(line);
    }
    if (result.length < 3 && promo.confidenceScore >= 0.8) {
      result.add('Verified from ${promo.websiteDomain ?? 'the official website'}');
    }
    if (result.isEmpty) {
      result.add('${promo.displayValue} — ${promo.brand} promotion');
    }

    return result.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bullets = _bullets();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (promo.globalQualityScore > 0) ...[
            ValueTierBadge(qualityScore: promo.globalQualityScore, fontSize: 13),
            const SizedBox(height: 12),
          ],
          ...bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: _GreenDot(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      b,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: Candy.chocolate,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GreenDot extends StatelessWidget {
  const _GreenDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(color: Candy.mint, shape: BoxShape.circle),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Trust card
// ---------------------------------------------------------------------------

class _TrustCard extends StatelessWidget {
  final String domain;
  final String url;
  final double score;
  final String promoId;
  final String brand;
  const _TrustCard({
    required this.domain,
    required this.url,
    required this.score,
    required this.promoId,
    required this.brand,
  });

  String get _confidenceLabel {
    if (score >= 0.8) return 'High confidence';
    if (score >= 0.6) return 'Medium confidence';
    return 'Low confidence';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateLabel = '${months[now.month - 1]} ${now.day}';
    return _Card(
      child: GestureDetector(
        onTap: () async {
          InteractionService().recordVerifyTap(promoId, brand: brand);
          final uri = Uri.tryParse(url);
          if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.verified_outlined,
                size: 18,
                color: Color(0xFF2E7D32),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Official source: $domain',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Candy.chocolate,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Last checked $dateLabel · $_confidenceLabel',
                    style: const TextStyle(fontSize: 11, color: Candy.muted),
                  ),
                  Builder(builder: (context) {
                    final uri = Uri.tryParse(url);
                    final path = uri != null && (uri.path.isNotEmpty && uri.path != '/')
                        ? uri.path + (uri.query.isNotEmpty ? '?${uri.query}' : '')
                        : null;
                    if (path == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        path,
                        style: const TextStyle(fontSize: 10, color: Candy.muted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'View source →',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2A5F3A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Historical comparison card
// ---------------------------------------------------------------------------

class _HistoricalComparisonCard extends StatelessWidget {
  final Promotion promo;
  const _HistoricalComparisonCard({required this.promo});

  String _categoryRank() {
    final category = promo.category.toLowerCase();
    final peers = PromotionsService.cached
        .where((p) => p.category.toLowerCase() == category)
        .toList();
    final score = promo.globalQualityScore;
    final int topPct;
    if (peers.length < 5) {
      // Sparse category — fall back to score thresholds
      if (score >= 80) topPct = 10;
      else if (score >= 65) topPct = 25;
      else if (score >= 50) topPct = 40;
      else topPct = 50;
    } else {
      final beaten = peers.where((p) => p.globalQualityScore < score).length;
      final raw = ((1.0 - beaten / peers.length) * 100).round();
      if (raw <= 5) topPct = 5;
      else if (raw <= 10) topPct = 10;
      else if (raw <= 15) topPct = 15;
      else if (raw <= 20) topPct = 20;
      else if (raw <= 25) topPct = 25;
      else if (raw <= 30) topPct = 30;
      else if (raw <= 40) topPct = 40;
      else topPct = 50;
    }
    return 'Top $topPct%';
  }

  String _categoryLabel() {
    final raw = promo.category;
    if (raw.isEmpty) return 'deals';
    return '${raw[0].toUpperCase()}${raw.substring(1)} deals';
  }

  @override
  Widget build(BuildContext context) {
    final rank = _categoryRank();
    final todayRatio = (promo.globalQualityScore / 100).clamp(0.0, 1.0);
    const typicalRatio = 0.52;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'HOW IT COMPARES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Candy.muted,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                rank,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.0,
                  color: Candy.mint,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'in ${_categoryLabel()}',
                  style: const TextStyle(fontSize: 13, color: Candy.muted, height: 1.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _CompareBar(label: 'Today\'s deal', ratio: todayRatio, highlight: true),
          const SizedBox(height: 8),
          _CompareBar(label: 'Typical deal', ratio: typicalRatio, highlight: false),
        ],
      ),
    );
  }
}

class _CompareBar extends StatelessWidget {
  final String label;
  final double ratio;
  final bool highlight;
  const _CompareBar({required this.label, required this.ratio, required this.highlight});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: highlight ? Candy.chocolate : Candy.muted,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 7,
            backgroundColor: Candy.border,
            color: highlight ? Candy.mint : Candy.muted.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 6. Why this deal is good
// ---------------------------------------------------------------------------

class _WhyGoodDealSection extends StatelessWidget {
  final Promotion promo;
  const _WhyGoodDealSection({required this.promo});

  static String? _codeToText(String code, Promotion p) {
    return switch (code) {
      'HIGH_EFFECTIVE_DISCOUNT' => 'Higher discount than ${p.brand} usually offers',
      'STRONG_DISCOUNT'         => 'Strong discount — above average for this category',
      'HIGH_VALUE_SAVINGS'      => 'Saves more than \$50 — significant dollar value',
      'GOOD_VALUE_SAVINGS'      => 'Solid dollar savings on this purchase',
      'EXPIRES_SOON'            => 'Ending soon — act before it expires',
      'EXPIRES_TODAY'           => 'Last chance — expires today',
      'NO_MEMBERSHIP_REQUIRED'  => 'No membership required — anyone can use this',
      'LOW_REDEMPTION_FRICTION' => 'Easy to redeem — no extra steps required',
      'NO_PURCHASE_MINIMUM'     => 'No minimum spend — works on a single item',
      'STRONG_ECONOMIC_VALUE'   => 'Strong overall economic value for this promotion',
      'HIGH_SPEND_REQUIRED'     => null,
      'LOW_CONFIDENCE_WARNING'  => null,
      _                         => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final items = promo.valueExplanationCodes
        .map((c) => _codeToText(c, promo))
        .whereType<String>()
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Why this is good',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Candy.chocolate,
            ),
          ),
          const SizedBox(height: 12),
          ...items.map(
            (text) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(Icons.check_circle_outline,
                        size: 17, color: Candy.mint),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: Candy.chocolate,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7. Promo code card
// ---------------------------------------------------------------------------

class _PromoCodeCard extends StatelessWidget {
  final Promotion promo;
  const _PromoCodeCard({required this.promo});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Promo code',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Candy.chocolate),
          ),
          const SizedBox(height: 10),
          _PromoCodeBox(promo: promo),
        ],
      ),
    );
  }
}

class _PromoCodeBox extends StatefulWidget {
  final Promotion promo;
  const _PromoCodeBox({required this.promo});

  @override
  State<_PromoCodeBox> createState() => _PromoCodeBoxState();
}

class _PromoCodeBoxState extends State<_PromoCodeBox> {
  // Fire code_copied once per page view — subsequent copies are intentional
  // repeat actions but don't need separate analytics events.
  bool _hasFiredCopy = false;

  @override
  Widget build(BuildContext context) {
    final code = widget.promo.promoCode!;
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: code));
        if (!_hasFiredCopy) {
          _hasFiredCopy = true;
          InteractionService().recordCodeCopied(
            widget.promo.id,
            brand: widget.promo.brand,
            code: code,
            meta: InteractionService.promoMeta(widget.promo),
          );
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied "$code"'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Candy.lavender.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Candy.lavender.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.confirmation_number_outlined, size: 18, color: Candy.lavender),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                code,
                style: const TextStyle(
                  color: Candy.lavender,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: 2.0,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const Icon(Icons.copy, size: 16, color: Candy.lavender),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 8. Eligibility card
// ---------------------------------------------------------------------------

class _EligibilityCard extends StatelessWidget {
  final Promotion promo;
  const _EligibilityCard({required this.promo});

  static const _orange = Color(0xFFF57F17);

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Can I use this?',
            style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: Candy.chocolate),
          ),
          const SizedBox(height: 12),
          if (!promo.requiresMembership)
            _EligRow(Icons.check_circle_outline, 'No membership required', Candy.mint)
          else ...[
            _EligRow(
              Icons.lock_outline,
              promo.membershipName ?? 'Members only',
              _orange,
            ),
            if (promo.membershipCost != null && promo.membershipCost!.isNotEmpty)
              _EligRow(
                promo.membershipCost!.toLowerCase().contains('free')
                    ? Icons.check_circle_outline
                    : Icons.credit_card_outlined,
                promo.membershipCost!.toLowerCase().contains('free')
                    ? 'Free to join'
                    : 'Paid membership',
                promo.membershipCost!.toLowerCase().contains('free')
                    ? Candy.mint
                    : _orange,
              ),
          ],
          if (!promo.requiresApp)
            _EligRow(Icons.check_circle_outline, 'No app required', Candy.mint)
          else
            _EligRow(Icons.phone_android_outlined, 'App required', _orange),
          if (promo.purchaseRequired)
            _EligRow(Icons.shopping_cart_outlined, 'Purchase required', Candy.muted),
          if (promo.redemptionMethod != 'unknown')
            _EligRow(
              _redemptionIcon(promo.redemptionMethod),
              _redemptionText(promo.redemptionMethod),
              Candy.muted,
            ),
          if (promo.minimumSpend != null)
            _EligRow(Icons.attach_money, 'Min spend: ${promo.minimumSpend}', Candy.muted),
          if (promo.distanceKm != null)
            _EligRow(
              Icons.near_me,
              'Nearest store: ${LocationService.formatDistance(promo.distanceKm)}',
              Candy.muted,
            ),
        ],
      ),
    );
  }

  static IconData _redemptionIcon(String r) => switch (r) {
        'online'       => Icons.language,
        'in_store'     => Icons.store_outlined,
        'in_app'       => Icons.phone_android_outlined,
        'show_code'    => Icons.confirmation_number_outlined,
        'scan_barcode' => Icons.qr_code_scanner,
        _              => Icons.storefront_outlined,
      };

  static String _redemptionText(String r) => const {
        'online':       'Redeem online',
        'in_store':     'Redeem in store',
        'in_app':       'Redeem in app',
        'show_code':    'Show promo code',
        'scan_barcode': 'Scan barcode at checkout',
      }[r] ?? 'Redeem';
}

class _EligRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _EligRow(this.icon, this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, color: Candy.chocolate, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 9. Redemption steps card
// ---------------------------------------------------------------------------

class _RedemptionStepsCard extends StatelessWidget {
  final List<String> steps;
  const _RedemptionStepsCard({required this.steps});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How to redeem',
            style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: Candy.chocolate),
          ),
          const SizedBox(height: 12),
          ...steps.asMap().entries.map(
            (e) => _StepRow(index: e.key + 1, text: e.value),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 10. When available card
// ---------------------------------------------------------------------------

class _WhenCard extends StatelessWidget {
  final Promotion promo;
  const _WhenCard({required this.promo});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available',
            style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: Candy.chocolate),
          ),
          const SizedBox(height: 10),
          if (promo.validDays.isNotEmpty) _ValidDaysRow(days: promo.validDays),
          if (promo.timeStart != null) ...[
            if (promo.validDays.isNotEmpty) const SizedBox(height: 8),
            _TimeRow(
              timeStart: promo.timeStart!,
              timeEnd: promo.timeEnd,
              promoTz: promo.promotionTimezone,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sticky redeem bar
// ---------------------------------------------------------------------------

class _StickyRedeemBar extends StatelessWidget {
  final FastRedemption fr;
  final Promotion promo;
  const _StickyRedeemBar({required this.fr, required this.promo});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FastRedeemButton(fr: fr, brand: promo.brand, promoId: promo.id),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Save button (app bar)
// ---------------------------------------------------------------------------

class _DetailSaveButton extends StatelessWidget {
  final Promotion promo;
  const _DetailSaveButton({required this.promo});

  @override
  Widget build(BuildContext context) {
    final svc = SavedDealsService();
    return ListenableBuilder(
      listenable: svc,
      builder: (ctx, _) {
        final saved = svc.isSaved(promo.id);
        return IconButton(
          icon: Icon(
            saved ? Icons.favorite : Icons.favorite_border,
            color: saved ? Candy.raspberry : Candy.chocolate,
          ),
          onPressed: () async {
            if (saved) {
              await svc.unsave(promo.id);
            } else {
              await svc.save(promo);
              InteractionService().recordDealSaved(
                promo.id,
                brand: promo.brand,
                category: promo.category,
                meta: InteractionService.promoMeta(promo),
              );
              if (ctx.mounted) {
                showModalBottomSheet(
                  context: ctx,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (_) => SaveSheet(promo: promo, svc: svc),
                );
              }
            }
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shop now button
// ---------------------------------------------------------------------------

class _ShopNowButton extends StatelessWidget {
  final Promotion promo;
  const _ShopNowButton({required this.promo});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: () async {
        InteractionService().recordRedeemClicked(
          promo.id,
          brand: promo.brand,
          actionType: 'open_url',
          meta: InteractionService.promoMeta(promo),
        );
        final uri = Uri.tryParse(promo.verifyUrl!);
        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      style: FilledButton.styleFrom(
        backgroundColor: Candy.raspberry,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: const Text(
        'View Deal',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets (used in multiple sections)
// ---------------------------------------------------------------------------

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ValueBadge extends StatelessWidget {
  final String value;
  final String type;
  const _ValueBadge({required this.value, required this.type});

  Color get _color => switch (type) {
        'percentage_off' => Candy.mint,
        'amount_off'     => Candy.raspberry,
        'free_item'      => Candy.mint,
        'free_shipping'  => Candy.mint,
        'points'         => Candy.lavender,
        'sale_price'     => Candy.raspberry,
        _                => Candy.muted,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Text(
        value.toUpperCase(),
        style: TextStyle(
          color: _color,
          fontWeight: FontWeight.w800,
          fontSize: 14,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  const _TagChip({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EDE8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: Candy.muted),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Candy.chocolate,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int index;
  final String text;
  const _StepRow({required this.index, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Candy.raspberry,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$index',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, height: 1.4, color: Candy.chocolate),
            ),
          ),
        ],
      ),
    );
  }
}

class _ValidDaysRow extends StatelessWidget {
  final List<String> days;
  const _ValidDaysRow({required this.days});

  @override
  Widget build(BuildContext context) {
    const order = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    const abbr  = {
      'Monday': 'Mon', 'Tuesday': 'Tue', 'Wednesday': 'Wed',
      'Thursday': 'Thu', 'Friday': 'Fri', 'Saturday': 'Sat', 'Sunday': 'Sun',
    };
    final sorted = [...days]..sort((a, b) =>
        order.indexOf(a).compareTo(order.indexOf(b)));
    return Wrap(
      spacing: 6,
      children: sorted.map((d) => Chip(
        label: Text(
          abbr[d] ?? d,
          style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: Candy.raspberry),
        ),
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: Candy.raspberry.withValues(alpha: 0.08),
        side: BorderSide(color: Candy.raspberry.withValues(alpha: 0.2)),
      )).toList(),
    );
  }
}

class _TimeRow extends StatelessWidget {
  final String timeStart;
  final String? timeEnd;
  final String promoTz;
  const _TimeRow({required this.timeStart, this.timeEnd, required this.promoTz});

  @override
  Widget build(BuildContext context) {
    final localStart = TimezoneService.convertTime(timeStart, promoTz);
    final localEnd   = timeEnd != null
        ? TimezoneService.convertTime(timeEnd!, promoTz)
        : null;
    final deviceTz   = TimezoneService.tzAbbr(TimezoneService.deviceTimezoneName);
    final label = localEnd != null
        ? '${TimezoneService.formatTime(localStart)} – ${TimezoneService.formatTime(localEnd)} $deviceTz'
        : '${TimezoneService.formatTime(localStart)} $deviceTz';
    return Row(
      children: [
        const Icon(Icons.access_time, size: 16, color: Candy.muted),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w500, color: Candy.chocolate),
        ),
      ],
    );
  }
}
