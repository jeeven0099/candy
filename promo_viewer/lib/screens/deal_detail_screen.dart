import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/promotion.dart';
import '../services/location_service.dart';
import '../services/saved_deals_service.dart';
import '../services/timezone_service.dart';
import '../theme/candy_colors.dart';
import '../widgets/brand_logo.dart';
import '../widgets/fast_redeem_button.dart';
import '../widgets/save_sheet.dart';
import '../widgets/status_chip.dart';

class DealDetailScreen extends StatelessWidget {
  final Promotion promo;
  const DealDetailScreen({super.key, required this.promo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Candy.cream,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: Candy.cream,
            foregroundColor: Candy.chocolate,
            elevation: 0,
            actions: [_DetailSaveButton(promo: promo)],
            flexibleSpace: FlexibleSpaceBar(
              background: _BrandHeader(promo: promo),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StatusChip(status: promo.status),
                      const Spacer(),
                      if (promo.displayValue.isNotEmpty)
                        _BigValueBadge(
                          value: promo.displayValue,
                          type: promo.discountType,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    promo.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      letterSpacing: -0.3,
                      color: Candy.chocolate,
                    ),
                  ),

                  // ── Fast redeem if eligible ──────────────────────────────
                  if (promo.fastRedemption != null &&
                      promo.fastRedemption!.eligible) ...[
                    const SizedBox(height: 20),
                    FastRedeemButton(fr: promo.fastRedemption!, brand: promo.brand),
                  ],

                  const SizedBox(height: 24),
                  _Divider(),
                  _DetailRow(Icons.category_outlined, 'Category', _capitalize(promo.category)),
                  _DetailRow(Icons.local_offer_outlined, 'Type', _formatType(promo.discountType)),
                  _DetailRow(Icons.storefront_outlined, 'Redemption', _formatRedemption(promo.redemptionMethod)),
                  if (promo.minimumSpend != null)
                    _DetailRow(Icons.shopping_cart_outlined, 'Min spend', promo.minimumSpend!),
                  if (promo.endDate != null)
                    _DetailRow(Icons.calendar_today_outlined, 'Expires', promo.endDate!),
                  if (promo.distanceKm != null)
                    _DetailRow(
                      Icons.near_me,
                      'Nearest store',
                      LocationService.formatDistance(promo.distanceKm),
                    ),
                  _Divider(),
                  if (promo.promoCode != null) ...[
                    _SectionHeader('Promo code'),
                    const SizedBox(height: 10),
                    _PromoCodeBox(code: promo.promoCode!),
                    _Divider(),
                  ],
                  _SectionHeader('Can I use this?'),
                  const SizedBox(height: 8),
                  _RequirementRow(
                    label: 'Requires membership',
                    value: promo.requiresMembership
                        ? (promo.membershipName ?? 'Members only')
                        : 'No',
                    met: !promo.requiresMembership,
                  ),
                  if (promo.requiresMembership)
                    _RequirementRow(
                      label: 'Membership cost',
                      value: _formatMembershipCost(promo.membershipCost),
                      met: _isMembershipFree(promo.membershipCost),
                    ),
                  _RequirementRow(
                    label: 'Requires app',
                    value: promo.requiresApp ? 'Yes' : 'No',
                    met: !promo.requiresApp,
                  ),
                  _RequirementRow(
                    label: 'Purchase required',
                    value: promo.purchaseRequired ? 'Yes' : 'No',
                    met: !promo.purchaseRequired,
                  ),
                  _RequirementRow(
                    label: 'Redemption',
                    value: _formatRedemption(promo.redemptionMethod),
                    met: true,
                  ),
                  if (promo.minimumSpend != null)
                    _RequirementRow(
                      label: 'Minimum spend',
                      value: promo.minimumSpend!,
                      met: true,
                    ),
                  if (promo.redemptionSteps.isNotEmpty) ...[
                    _Divider(),
                    _SectionHeader('How to redeem'),
                    const SizedBox(height: 8),
                    ...promo.redemptionSteps.asMap().entries.map(
                      (e) => _StepRow(index: e.key + 1, text: e.value),
                    ),
                  ],
                  if (promo.validDays.isNotEmpty || promo.timeStart != null) ...[
                    _Divider(),
                    _SectionHeader('When'),
                    const SizedBox(height: 8),
                    if (promo.validDays.isNotEmpty)
                      _ValidDaysRow(days: promo.validDays),
                    if (promo.timeStart != null) ...[
                      const SizedBox(height: 6),
                      _TimeRow(
                        timeStart: promo.timeStart!,
                        timeEnd: promo.timeEnd,
                        promoTz: promo.promotionTimezone,
                      ),
                    ],
                  ],
                  if (promo.termsText != null && promo.termsText!.isNotEmpty) ...[
                    _Divider(),
                    _SectionHeader('Terms'),
                    const SizedBox(height: 4),
                    Text(
                      promo.termsText!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Candy.muted,
                        height: 1.5,
                      ),
                    ),
                  ],
                  _Divider(),
                  _ConfidenceBar(score: promo.confidenceScore),
                  if (promo.verifyUrl != null) ...[
                    const SizedBox(height: 16),
                    _VerifySourceRow(url: promo.verifyUrl!),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMembershipCost(String? cost) {
    if (cost == null || cost.isEmpty) return 'Unknown';
    final c = cost.toLowerCase();
    if (c.contains('free')) return 'Free to join';
    if (c.contains('paid')) return 'Paid';
    return cost;
  }

  bool _isMembershipFree(String? cost) {
    if (cost == null) return false;
    return cost.toLowerCase().contains('free');
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');

  String _formatType(String t) {
    const map = {
      'percentage_off': 'Percentage off',
      'amount_off':     'Amount off',
      'free_item':      'Free item',
      'free_shipping':  'Free shipping',
      'points':         'Points / rewards',
      'sale_price':     'Sale price',
      'unknown':        'Unknown',
    };
    return map[t] ?? t;
  }

  String _formatRedemption(String r) {
    const map = {
      'in_app':       'In app',
      'in_store':     'In store',
      'online':       'Online',
      'show_code':    'Promo code',
      'scan_barcode': 'Scan barcode',
      'unknown':      'Unknown',
    };
    return map[r] ?? r;
  }
}

// ---------------------------------------------------------------------------
// Save button in app bar
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
// Brand header
// ---------------------------------------------------------------------------

class _BrandHeader extends StatelessWidget {
  final Promotion promo;
  const _BrandHeader({required this.promo});

  Widget _logoFallback() => Container(
        color: Candy.pink.withValues(alpha: 0.06),
        height: 200,
        child: Center(child: BrandLogo(promo: promo, size: 80)),
      );

  @override
  Widget build(BuildContext context) {
    return promo.ogImageUrl != null
        ? Image.network(
            promo.ogImageUrl!,
            width: double.infinity,
            height: 200,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _logoFallback(),
            loadingBuilder: (_, child, loading) =>
                loading == null ? child : _logoFallback(),
          )
        : _logoFallback();
  }
}

// ---------------------------------------------------------------------------
// Supporting widgets
// ---------------------------------------------------------------------------

class _BigValueBadge extends StatelessWidget {
  final String value;
  final String type;
  const _BigValueBadge({required this.value, required this.type});

  Color get _color {
    switch (type) {
      case 'percentage_off': return Candy.mint;
      case 'amount_off':     return Candy.raspberry;
      case 'free_item':      return Candy.mint;
      case 'free_shipping':  return Candy.mint;
      case 'points':         return Candy.lavender;
      case 'sale_price':     return Candy.raspberry;
      default:               return Candy.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withValues(alpha: 0.25)),
      ),
      child: Text(
        value.toUpperCase(),
        style: TextStyle(
          color: _color,
          fontWeight: FontWeight.w800,
          fontSize: 18,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Candy.muted),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 14, color: Candy.muted)),
          const Spacer(),
          Text(value, style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: Candy.chocolate)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: Candy.chocolate,
      ),
    );
  }
}

class _RequirementRow extends StatelessWidget {
  final String label;
  final String value;
  final bool met;
  const _RequirementRow({required this.label, required this.value, required this.met});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_outline : Icons.info_outline,
            size: 16,
            color: met ? Candy.mint : const Color(0xFFF57F17),
          ),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 14, color: Candy.muted)),
          const Spacer(),
          Text(value, style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: Candy.chocolate)),
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
            child: Text(text, style: const TextStyle(
              fontSize: 14, height: 1.4, color: Candy.chocolate)),
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
    const abbr  = {'Monday':'Mon','Tuesday':'Tue','Wednesday':'Wed','Thursday':'Thu',
                   'Friday':'Fri','Saturday':'Sat','Sunday':'Sun'};
    final sorted = [...days]..sort((a, b) =>
        order.indexOf(a).compareTo(order.indexOf(b)));
    return Wrap(
      spacing: 6,
      children: sorted.map((d) => Chip(
        label: Text(abbr[d] ?? d,
            style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: Candy.raspberry)),
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
    final localEnd   = timeEnd != null ? TimezoneService.convertTime(timeEnd!, promoTz) : null;
    final deviceTz   = TimezoneService.tzAbbr(TimezoneService.deviceTimezoneName);

    final label = localEnd != null
        ? '${TimezoneService.formatTime(localStart)} – ${TimezoneService.formatTime(localEnd)} $deviceTz'
        : '${TimezoneService.formatTime(localStart)} $deviceTz';

    return Row(
      children: [
        const Icon(Icons.access_time, size: 16, color: Candy.muted),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w500, color: Candy.chocolate)),
      ],
    );
  }
}

class _ConfidenceBar extends StatelessWidget {
  final double score;
  const _ConfidenceBar({required this.score});

  @override
  Widget build(BuildContext context) {
    final pct = (score * 100).round();
    final color = score >= 0.8
        ? Candy.mint
        : score >= 0.6
            ? Colors.orange
            : Colors.red;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('Confidence', style: TextStyle(fontSize: 12, color: Candy.muted)),
          const Spacer(),
          Text('$pct%', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score,
            minHeight: 5,
            backgroundColor: Candy.pink.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Divider(height: 24, color: Candy.pink.withValues(alpha: 0.15));
}

class _VerifySourceRow extends StatelessWidget {
  final String url;
  const _VerifySourceRow({required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.tryParse(url);
        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Row(
        children: [
          const Icon(Icons.open_in_new, size: 14, color: Candy.muted),
          const SizedBox(width: 8),
          const Text(
            'Verify on brand website',
            style: TextStyle(
              fontSize: 12,
              color: Candy.muted,
              decoration: TextDecoration.underline,
              decorationColor: Candy.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _PromoCodeBox extends StatelessWidget {
  final String code;
  const _PromoCodeBox({required this.code});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: code));
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
          border: Border.all(
            color: Candy.lavender.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.confirmation_number_outlined,
                size: 18, color: Candy.lavender),
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
