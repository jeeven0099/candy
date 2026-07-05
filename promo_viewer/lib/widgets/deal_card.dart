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
import 'fast_redeem_button.dart';
import 'save_sheet.dart';

class DealCard extends StatelessWidget {
  final Promotion promo;
  final VoidCallback? onTap;
  final Set<String> memberships;

  const DealCard({super.key, required this.promo, this.onTap, this.memberships = const {}});

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

  // Days until expiry — null if unknown or already expired
  int? get _daysLeft {
    if (promo.endDate == null) return null;
    final end = DateTime.tryParse(promo.endDate!);
    if (end == null) return null;
    final diff = end.difference(DateTime.now()).inDays;
    return diff >= 0 ? diff : null;
  }

  @override
  Widget build(BuildContext context) {
    final days = _daysLeft;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            onLongPress: () => _showScoreDebug(context),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header: logo | brand | badge + actions ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BrandLogo(promo: promo, size: 44),
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
                            const SizedBox(height: 4),
                            Text(
                              promo.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                                color: Candy.chocolate,
                              ),
                            ),
                            if (promo.summary != null && promo.summary!.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                promo.summary!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: Candy.muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Badge + actions stacked
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _DiscountBadge(promo: promo),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _HeartButton(promo: promo),
                              _MenuButton(promo: promo),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),

                  // ── Estimated savings line ──
                  if (_showSavings) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.savings_outlined,
                            size: 13, color: const Color(0xFF2E7D32)),
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

                  const SizedBox(height: 10),

                  // ── Tags row ──
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (promo.isLocal && promo.neighborhood != null)
                        _Tag(
                          icon: Icons.storefront,
                          label: 'Local · ${promo.neighborhood}',
                          color: const Color(0xFF2E7D32),
                          filled: true,
                        )
                      else if (promo.promotionType == 'online_only')
                        _Tag(
                          icon: Icons.language,
                          label: 'Online',
                          color: Candy.lavender,
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
                      if (promo.requiresApp)
                        _Tag(icon: Icons.smartphone, label: 'App required'),
                      if (days != null && days <= 7)
                        _UrgencyTag(days: days),
                    ],
                  ),

                  // ── Promo code ──
                  if (promo.promoCode != null) ...[
                    const SizedBox(height: 8),
                    _PromoCodePill(code: promo.promoCode!),
                  ],

                  // ── Fast redeem button ──
                  if (promo.fastRedemption != null &&
                      promo.fastRedemption!.eligible) ...[
                    const SizedBox(height: 12),
                    FastRedeemButton(fr: promo.fastRedemption!, brand: promo.brand, promoId: promo.id),
                  ],

                  // ── Synthesized category note ──
                  if (_onSaleCategories.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        Icon(Icons.local_offer_outlined, size: 11, color: Colors.teal.shade400),
                        ..._onSaleCategories.map((cat) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            cat,
                            style: TextStyle(fontSize: 10, color: Colors.teal.shade700, fontWeight: FontWeight.w500),
                          ),
                        )),
                      ],
                    ),
                  ],

                  // ── Source trust line ──
                  if (promo.source == 'web' && promo.websiteDomain != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.verified_outlined,
                            size: 11, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(
                          'Sourced from ${promo.websiteDomain}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade400),
                        ),
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

  // Show savings line only for % off deals where we have a meaningful estimate
  bool get _showSavings =>
      promo.discountType == 'percentage_off' &&
      promo.estimatedSavings != null &&
      promo.estimatedSavings! >= 10;

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

// Urgency tag — deadline effect: "X days left" feels scarce
class _UrgencyTag extends StatelessWidget {
  final int days;
  const _UrgencyTag({required this.days});

  @override
  Widget build(BuildContext context) {
    final isHot = days <= 2;
    final color = isHot ? const Color(0xFFC62828) : const Color(0xFFE65100);
    final label = days == 0 ? 'Expires today' : '$days day${days == 1 ? '' : 's'} left';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isHot ? Icons.local_fire_department : Icons.schedule,
              size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Discount badge ────────────────────────────────────────────────────────────

class _DiscountBadge extends StatelessWidget {
  final Promotion promo;
  const _DiscountBadge({required this.promo});

  static final _pctRe = RegExp(r'(\d+(?:\.\d+)?)%');
  static final _dolRe = RegExp(r'\$(\d+(?:\.\d+)?)');
  static final _bogoRe = RegExp(r'\bbogo\b|buy.one.get.one', caseSensitive: false);

  (String?, Color) get _labelAndColor {
    switch (promo.discountType) {
      case 'free_item':
        return ('FREE', const Color(0xFF00897B));
      case 'bogo':
        return ('BOGO', const Color(0xFF00897B));
      case 'percentage_off':
        final m = _pctRe.firstMatch(promo.discountValue ?? '');
        if (m == null) return (null, Colors.transparent);
        final pct = double.tryParse(m.group(1)!) ?? 0;
        final label = '${pct.toInt()}% OFF';
        final color = pct >= 50
            ? Candy.raspberry
            : pct >= 25
                ? const Color(0xFFE65100)
                : const Color(0xFF6D4C41);
        return (label, color);
      case 'amount_off':
        final m = _dolRe.firstMatch(promo.discountValue ?? '');
        if (m == null) return (null, Colors.transparent);
        return ('\$${(double.tryParse(m.group(1)!) ?? 0).toInt()} OFF',
            const Color(0xFF2E7D32));
      default:
        // Catch BOGO in title when discount_type is generic
        if (_bogoRe.hasMatch(promo.title)) {
          return ('BOGO', const Color(0xFF00897B));
        }
        return (null, Colors.transparent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (label, color) = _labelAndColor;
    if (label == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ── Heart button ─────────────────────────────────────────────────────────────

class _HeartButton extends StatelessWidget {
  final Promotion promo;
  const _HeartButton({required this.promo});

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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Candy.lavender.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Candy.lavender.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.confirmation_number_outlined,
                size: 13, color: Candy.lavender),
            const SizedBox(width: 6),
            Text(
              code,
              style: const TextStyle(
                color: Candy.lavender,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.2,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.copy, size: 11, color: Candy.lavender),
          ],
        ),
      ),
    );
  }
}

