import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/promotion.dart';
import '../services/interaction_service.dart';
import '../services/location_service.dart';
import '../services/saved_deals_service.dart';
import '../services/supabase_service.dart';
import '../services/user_prefs_service.dart';
import '../theme/candy_colors.dart';
import '../utils/feed_ranker.dart';
import 'brand_logo.dart';
import 'effort_chip.dart';
import 'fast_redeem_button.dart';
import 'save_sheet.dart';
import 'urgency_chip.dart';
import 'value_tier_badge.dart';

class DealCard extends StatelessWidget {
  final Promotion promo;
  final VoidCallback? onTap;
  final Set<String> memberships;
  final int? feedPosition;
  final String? rankingMode;

  const DealCard({
    super.key,
    required this.promo,
    this.onTap,
    this.memberships = const {},
    this.feedPosition,
    this.rankingMode,
  });

  void _showScoreDebug(BuildContext context) {
    final svc = InteractionService();
    final bd = computeBreakdown(
      promo, svc,
      distanceKm: promo.distanceKm,
      isMember: _isMember,
    );

    final rows = [
      ('Pipeline base',    bd.rankBase,         ''),
      ('Distance',         bd.distanceBonus,    promo.distanceKm != null ? '${LocationService.formatDistance(promo.distanceKm)} away' : 'no location'),
      ('Day of week',      bd.dayBonus,         promo.validDays.isEmpty ? 'any day' : promo.validDays.join(', ')),
      ('Membership',       bd.membershipBonus,  _isMember ? 'member ✓' : promo.requiresMembership ? 'required' : 'open'),
      ('Affinity',         bd.affinityBoost,    'saved/clicked/searched'),
      ('Fatigue penalty',  -bd.fatiguePenalty,  bd.isHidden ? 'HIDDEN (cooldown)' : 'seen ${svc.seenCount(promo.id)}x'),
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(promo.brand, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text(promo.title, maxLines: 2,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            ...rows.map((r) {
              final (label, value, note) = r;
              final isNeg = value < 0;
              final color = value > 0 ? const Color(0xFF2E7D32) : (value < 0 ? const Color(0xFFC62828) : Colors.grey.shade500);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 140, child: Text(label, style: const TextStyle(fontSize: 13))),
                    Text(
                      '${isNeg ? '' : value > 0 ? '+' : ''}${value.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(note, style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
                  ],
                ),
              );
            }),
            const Divider(height: 24),
            Row(
              children: [
                const SizedBox(width: 140, child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w700))),
                Text(
                  bd.isHidden ? 'HIDDEN' : bd.total.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: bd.isHidden ? Colors.red : Candy.raspberry,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool get _isMember {
    if (memberships.isEmpty || !promo.requiresMembership) return false;
    final brand = promo.brand.toLowerCase();
    final name = (promo.membershipName ?? '').toLowerCase();
    return memberships.any((m) =>
        m.contains(brand) || brand.contains(m) ||
        (name.isNotEmpty && (m.contains(name) || name.contains(m))));
  }

  @override
  Widget build(BuildContext context) {
    final hasFastRedeem = promo.fastRedemption != null && promo.fastRedemption!.eligible;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: _LiquidGlassCard(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap == null
                ? null
                : () {
                    InteractionService().recordDealCardOpened(
                      promo.id,
                      brand: promo.brand,
                      category: promo.category,
                      meta: InteractionService.promoMeta(promo, feedPosition: feedPosition, rankingMode: rankingMode),
                    );
                    onTap!();
                  },
            onLongPress: () => _showScoreDebug(context),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── Brand header ──────────────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      BrandLogo(promo: promo, size: 40),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              promo.brand.toUpperCase(),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                                color: Candy.chocolate.withValues(alpha: 0.45),
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            _SourceLabel(promo: promo),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      _HeartButton(promo: promo, feedPosition: feedPosition, rankingMode: rankingMode),
                      _MenuButton(promo: promo),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ── Offer ─────────────────────────────────────────────────
                  Text(
                    promo.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                      color: Candy.chocolate,
                    ),
                  ),
                  if (promo.summary != null && promo.summary!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      promo.summary!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: Candy.muted,
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),

                  // ── Value signals ─────────────────────────────────────────
                  if (promo.globalQualityScore > 0)
                    ValueTierBadge(qualityScore: promo.globalQualityScore, fontSize: 11),
                  if (_showSavings) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.savings_outlined, size: 13, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 4),
                        Text(
                          '~\$${promo.estimatedSavings!.toStringAsFixed(0)} in savings',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_rankingInsight != null) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline, size: 12, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _rankingInsight!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF2E7D32),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 10),

                  // ── Chips ─────────────────────────────────────────────────
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      EffortChip(promo: promo),
                      if (promo.isLocal && promo.neighborhood != null)
                        _Tag(
                          icon: Icons.storefront,
                          label: 'Local · ${promo.neighborhood}',
                          color: const Color(0xFF2E7D32),
                          filled: true,
                        )
                      else if (promo.distanceKm != null)
                        _Tag(
                          icon: Icons.near_me,
                          label: LocationService.formatDistance(promo.distanceKm),
                          color: const Color(0xFF1565C0),
                        ),
                      if (_isMember)
                        _Tag(
                          icon: Icons.verified,
                          label: 'Exclusive',
                          color: Candy.mint,
                          filled: true,
                        )
                      else if (promo.requiresMembership)
                        _Tag(
                          icon: Icons.card_membership,
                          label: (promo.membershipName != null && promo.membershipName!.isNotEmpty)
                              ? promo.membershipName!
                              : 'Members only',
                          color: Candy.lavender,
                        ),
                      UrgencyChip(promo: promo),
                    ],
                  ),

                  // ── Promo code ────────────────────────────────────────────
                  if (promo.promoCode != null) ...[
                    const SizedBox(height: 10),
                    _PromoCodePill(code: promo.promoCode!),
                  ],

                  // ── Fast redeem CTA (centered, 62% width) ─────────────────
                  if (hasFastRedeem) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.62,
                        child: FastRedeemButton(
                          fr: promo.fastRedemption!,
                          brand: promo.brand,
                          promoId: promo.id,
                        ),
                      ),
                    ),
                  ],

                  // ── Meta footer ───────────────────────────────────────────
                  if (_onSaleCategories.isNotEmpty || (promo.source == 'web' && promo.websiteDomain != null)) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (_onSaleCategories.isNotEmpty) ...[
                          Icon(Icons.local_offer_outlined, size: 11, color: Colors.grey.shade400),
                          const SizedBox(width: 3),
                          Text(
                            _onSaleCategories.take(3).join(' · '),
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                          ),
                        ],
                        if (_onSaleCategories.isNotEmpty && promo.source == 'web' && promo.websiteDomain != null)
                          Text('  ·  ', style: TextStyle(fontSize: 11, color: Colors.grey.shade300)),
                        if (promo.source == 'web' && promo.websiteDomain != null) ...[
                          Icon(Icons.verified_outlined, size: 11, color: Colors.grey.shade400),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              promo.websiteDomain!,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],

                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _showSavings =>
      promo.estimatedSavings != null &&
      promo.estimatedSavings! >= 10 &&
      !const {'food', 'fast_food', 'coffee', 'grocery', 'restaurant'}.contains(promo.category.toLowerCase());

  String? get _rankingInsight {
    final score = promo.globalQualityScore;
    if (score <= 0) return null;
    final cat = promo.category.toLowerCase();
    final catLabel = switch (cat) {
      'food' || 'fast_food' || 'restaurant' => 'food',
      'coffee'      => 'coffee',
      'clothing'    => 'clothing',
      'footwear' || 'shoes' => 'footwear',
      'electronics' => 'electronics',
      'beauty'      => 'beauty',
      'home'        => 'home',
      'travel'      => 'travel',
      _             => 'retail',
    };
    if (score >= 80) return 'One of this month\'s best $catLabel deals';
    if (score >= 65) return 'Better than most ${promo.brand} offers';
    return null;
  }

  List<String> get _onSaleCategories => promo.productCategories;
}

// ── Tags ─────────────────────────────────────────────────────────────────────

class _Tag extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final bool filled;
  const _Tag({required this.icon, required this.label, this.color, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.grey.shade500;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? c.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: filled ? Border.all(color: c.withValues(alpha: 0.3)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: c,
              fontWeight: filled ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Heart button ─────────────────────────────────────────────────────────────

class _HeartButton extends StatelessWidget {
  final Promotion promo;
  final int? feedPosition;
  final String? rankingMode;
  const _HeartButton({required this.promo, this.feedPosition, this.rankingMode});

  @override
  Widget build(BuildContext context) {
    final svc = SavedDealsService();
    return ListenableBuilder(
      listenable: svc,
      builder: (ctx, _) {
        final saved = svc.isSaved(promo.id);
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
          icon: Icon(
            saved ? Icons.favorite : Icons.favorite_border,
            size: 20,
            color: saved ? Candy.raspberry : Candy.muted.withValues(alpha: 0.5),
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
                meta: InteractionService.promoMeta(promo, feedPosition: feedPosition, rankingMode: rankingMode),
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


// ── Not-interested menu ───────────────────────────────────────────────────────

class _MenuButton extends StatelessWidget {
  final Promotion promo;
  const _MenuButton({required this.promo});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      iconSize: 18,
      icon: Icon(Icons.more_vert, size: 18, color: Candy.muted.withValues(alpha: 0.45)),
      onSelected: (v) async {
        if (v == 'skip_deal') {
          await InteractionService().skipDeal(promo.id);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('This deal will no longer appear in your feed'),
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => InteractionService().unskipDeal(promo.id),
                ),
              ),
            );
          }
        } else if (v == 'hide_brand') {
          await UserPrefsService().hideBrand(promo.brand);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Hiding ${promo.brand} deals from your feed'),
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => UserPrefsService().unhideBrand(promo.brand),
                ),
              ),
            );
          }
        } else if (v == 'report') {
          if (context.mounted) {
            final outerCtx = context;
            showModalBottomSheet(
              context: context,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (sheetCtx) => _ReportSheet(
                promo: promo,
                onSubmit: (type) {
                  Navigator.pop(sheetCtx);
                  _submitReport(promo, type, outerCtx);
                },
              ),
            );
          }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'skip_deal',
          child: _MenuItem(
            icon: Icons.visibility_off_outlined,
            label: 'Not interested in this deal',
          ),
        ),
        PopupMenuItem(
          value: 'hide_brand',
          child: _MenuItem(
            icon: Icons.not_interested,
            label: 'Not interested in ${promo.brand}',
          ),
        ),
        PopupMenuItem(
          value: 'report',
          child: _MenuItem(
            icon: Icons.flag_outlined,
            label: 'Report wrong or expired',
          ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 14)),
      ],
    );
  }
}

// ── Report sheet ─────────────────────────────────────────────────────────────

const _kReportTypes = [
  (slug: 'wrong_deal',      icon: Icons.edit_off_outlined,         label: 'Wrong deal',         sub: 'The deal details are incorrect'),
  (slug: 'expired',         icon: Icons.event_busy_outlined,        label: 'Expired',            sub: 'This deal has already ended'),
  (slug: 'bad_link',        icon: Icons.link_off,                   label: 'Bad link',           sub: "The link doesn't work"),
  (slug: 'not_real',        icon: Icons.block,                      label: 'Not a real deal',    sub: "Doesn't look like a genuine promotion"),
  (slug: 'store_closed',    icon: Icons.store_mall_directory_outlined, label: 'Store closed',    sub: 'This store location is permanently closed'),
];

Future<void> _submitReport(Promotion promo, String reportType, BuildContext ctx) async {
  // Fire-and-forget: write to user_interactions so pipeline quality is tracked.
  if (SupabaseService.isLoggedIn) {
    final userId = UserPrefsService().userId;
    if (userId != null) {
      try {
        await SupabaseService.client.from('user_interactions').insert({
          'user_id':    userId,
          'event_type': 'reported',
          'promotion_id': promo.id,
          'brand':      promo.brand,
          'category':   promo.category,
          'metadata':   {'report_type': reportType},
        });
      } catch (_) {}
    }
  }
  if (ctx.mounted) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(
        content: Text('Thanks — we\'ll review this deal'),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _ReportSheet extends StatelessWidget {
  final Promotion promo;
  final void Function(String reportType) onSubmit;
  const _ReportSheet({required this.promo, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Report this deal',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          Text(promo.brand,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          ..._kReportTypes.map((t) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(t.icon, size: 22, color: Colors.grey.shade600),
            title: Text(t.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: Text(t.sub, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            onTap: () => onSubmit(t.slug),
          )),
        ],
      ),
    );
  }
}

// ── Liquid glass card surface ─────────────────────────────────────────────────

class _LiquidGlassCard extends StatelessWidget {
  final Widget child;
  const _LiquidGlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: const Color(0xFFE8D5C0).withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFFFFDF9).withValues(alpha: 0.97),
                  const Color(0xFFFFF8F2).withValues(alpha: 0.88),
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.80),
                width: 1.0,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ── Source label ──────────────────────────────────────────────────────────────

class _SourceLabel extends StatelessWidget {
  final Promotion promo;
  const _SourceLabel({required this.promo});

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final String label;
    final Color color;

    if (promo.isLocal && promo.neighborhood != null) {
      icon = Icons.storefront_outlined;
      label = promo.neighborhood!;
      color = const Color(0xFF2E7D32);
    } else if (promo.isLocal) {
      icon = Icons.storefront_outlined;
      label = 'In-store';
      color = const Color(0xFF2E7D32);
    } else if (promo.distanceKm != null) {
      icon = Icons.near_me_outlined;
      label = '${LocationService.formatDistance(promo.distanceKm)} away';
      color = const Color(0xFF1565C0);
    } else {
      icon = Icons.language_outlined;
      label = 'Online';
      color = Candy.muted;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color.withValues(alpha: 0.7)),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color.withValues(alpha: 0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── Promo code pill ───────────────────────────────────────────────────────────

class _PromoCodePill extends StatelessWidget {
  final String code;
  const _PromoCodePill({required this.code});

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Candy.lavender.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Candy.lavender.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                const Icon(Icons.confirmation_number_outlined, size: 14, color: Candy.lavender),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    code,
                    style: const TextStyle(
                      color: Candy.lavender,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: 1.8,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const Icon(Icons.copy_outlined, size: 14, color: Candy.lavender),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Tap to copy',
            style: TextStyle(fontSize: 10, color: Candy.muted.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

