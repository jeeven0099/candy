import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/fast_redemption.dart';
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
    final hasSticky = promo.fastRedemption != null && promo.fastRedemption!.eligible;
    return Scaffold(
      backgroundColor: Candy.cream,
      bottomNavigationBar: hasSticky
          ? _StickyFastRedeem(
              fr: promo.fastRedemption!,
              brand: promo.brand,
              promoId: promo.id,
            )
          : null,
      appBar: AppBar(
        backgroundColor: Candy.cream,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Candy.chocolate,
        title: Text(
          promo.brand,
          style: const TextStyle(
            color: Candy.chocolate,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [_DetailSaveButton(promo: promo)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _HeroCard(promo: promo),
          const SizedBox(height: 12),
          if (promo.source == 'web' && promo.verifyUrl != null) ...[
            _TrustCard(
              domain: promo.websiteDomain ?? promo.brand,
              url: promo.verifyUrl!,
              score: promo.confidenceScore,
            ),
            const SizedBox(height: 12),
          ],
          if (promo.promoCode != null) ...[
            _PromoCodeCard(code: promo.promoCode!),
            const SizedBox(height: 12),
          ],
          _EligibilityCard(promo: promo),
          const SizedBox(height: 12),
          if (promo.redemptionSteps.isNotEmpty) ...[
            _RedeemCard(steps: promo.redemptionSteps),
            const SizedBox(height: 12),
          ],
          if (promo.validDays.isNotEmpty || promo.timeStart != null) ...[
            _WhenCard(promo: promo),
            const SizedBox(height: 12),
          ],
          if (promo.termsText != null && promo.termsText!.isNotEmpty) ...[
            _TermsCard(terms: promo.termsText!),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero card
// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  final Promotion promo;
  const _HeroCard({required this.promo});

  @override
  Widget build(BuildContext context) {
    final hasEstimated = promo.estimatedSavings != null && promo.estimatedSavings! > 0;
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
          const SizedBox(height: 14),
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
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (promo.displayValue.isNotEmpty)
                _ValueBadge(value: promo.displayValue, type: promo.discountType),
              _TagChip(label: _capitalize(promo.category)),
              if (promo.redemptionMethod != 'unknown')
                _TagChip(label: _formatRedemption(promo.redemptionMethod)),
              if (promo.endDate != null)
                _TagChip(
                  label: 'Expires ${promo.endDate!}',
                  icon: Icons.calendar_today_outlined,
                ),
            ],
          ),
          if (hasEstimated) ...[
            const SizedBox(height: 10),
            Text(
              '~\$${promo.estimatedSavings!.toStringAsFixed(0)} estimated savings',
              style: const TextStyle(
                fontSize: 13,
                color: Candy.mint,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (promo.minimumSpend != null) ...[
            const SizedBox(height: 4),
            Text(
              'Min spend: ${promo.minimumSpend}',
              style: const TextStyle(fontSize: 12, color: Candy.muted),
            ),
          ],
          const SizedBox(height: 10),
          _HeroEligSummary(promo: promo),
          // Show Shop Now only when there is no sticky FastRedeemButton at the bottom
          if (promo.verifyUrl != null &&
              (promo.fastRedemption == null || !promo.fastRedemption!.eligible)) ...[
            const SizedBox(height: 16),
            _ShopNowButton(url: promo.verifyUrl!),
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

class _HeroEligSummary extends StatelessWidget {
  final Promotion promo;
  const _HeroEligSummary({required this.promo});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    parts.add(promo.requiresMembership
        ? (promo.membershipName ?? 'Members only')
        : 'No membership needed');
    if (!promo.requiresApp) parts.add('No app needed');
    if (promo.purchaseRequired) parts.add('Purchase required');
    return Text(
      parts.join(' · '),
      style: const TextStyle(fontSize: 12, color: Candy.muted, height: 1.4),
    );
  }
}

class _ShopNowButton extends StatelessWidget {
  final String url;
  const _ShopNowButton({required this.url});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: () async {
        final uri = Uri.tryParse(url);
        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      style: FilledButton.styleFrom(
        backgroundColor: Candy.raspberry,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text(
        'Shop Now',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trust card
// ---------------------------------------------------------------------------

class _TrustCard extends StatelessWidget {
  final String domain;
  final String url;
  final double score;
  const _TrustCard({required this.domain, required this.url, required this.score});

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
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'View source →',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2E7D32),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Promo code card
// ---------------------------------------------------------------------------

class _PromoCodeCard extends StatelessWidget {
  final String code;
  const _PromoCodeCard({required this.code});

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
          _PromoCodeBox(code: code),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Eligibility card
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
              style: const TextStyle(
                fontSize: 14, color: Candy.chocolate, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Redeem card
// ---------------------------------------------------------------------------

class _RedeemCard extends StatelessWidget {
  final List<String> steps;
  const _RedeemCard({required this.steps});

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
// When card
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
// Terms card
// ---------------------------------------------------------------------------

class _TermsCard extends StatelessWidget {
  final String terms;
  const _TermsCard({required this.terms});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Terms',
            style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: Candy.chocolate),
          ),
          const SizedBox(height: 6),
          Text(
            terms,
            style: const TextStyle(fontSize: 12, color: Candy.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sticky fast redeem bar
// ---------------------------------------------------------------------------

class _StickyFastRedeem extends StatelessWidget {
  final FastRedemption fr;
  final String brand;
  final String promoId;
  const _StickyFastRedeem({
    required this.fr,
    required this.brand,
    required this.promoId,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FastRedeemButton(fr: fr, brand: brand, promoId: promoId),
      ),
    );
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
// Shared small widgets
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
              style: const TextStyle(
                fontSize: 14, height: 1.4, color: Candy.chocolate),
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
          border: Border.all(color: Candy.lavender.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.confirmation_number_outlined,
              size: 18,
              color: Candy.lavender,
            ),
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
