import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/promotion.dart';
import '../services/interaction_service.dart';
import '../services/location_service.dart';
import '../services/saved_deals_service.dart';
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Candy.pink.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: () => _showScoreDebug(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: logo | brand + title | heart ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BrandLogo(promo: promo, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          promo.brand.toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                            color: Candy.muted,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          promo.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
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
                      ],
                    ),
                  ),
                  _HeartButton(promo: promo),
                ],
              ),

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
                  // Urgency — only show when ≤ 7 days left
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
            ],
          ),
        ),
      ),
    );
  }
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

