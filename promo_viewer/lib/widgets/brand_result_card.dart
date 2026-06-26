import 'package:flutter/material.dart';
import '../models/user_prefs.dart';
import '../services/interaction_service.dart';
import '../services/saved_deals_service.dart';
import '../theme/candy_colors.dart';
import '../utils/search_utils.dart';
import 'brand_logo.dart';
import 'deal_card.dart';
import '../screens/deal_detail_screen.dart';

class BrandResultCard extends StatefulWidget {
  final BrandGroup group;
  final Set<String> memberships;
  final VoidCallback? onExpanded;
  final void Function(String dealId, String brand)? onDealTap;
  final InteractionService? svc;
  final UserPrefs? prefs;

  const BrandResultCard({
    super.key,
    required this.group,
    this.memberships = const {},
    this.onExpanded,
    this.onDealTap,
    this.svc,
    this.prefs,
  });

  @override
  State<BrandResultCard> createState() => _BrandResultCardState();
}

class _BrandResultCardState extends State<BrandResultCard> {
  static const _kPreviewCount = 2;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final lead  = group.deals.first;
    final overflow = group.deals.length - _kPreviewCount;
    final hasMore  = overflow > 0;
    final visible  = _expanded ? group.deals : group.deals.take(_kPreviewCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Brand header — long-press to see score breakdown
        GestureDetector(
          onLongPress: widget.svc != null
              ? () => _showScoreBreakdown(context)
              : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                BrandLogo(promo: lead, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.brand,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Candy.chocolate,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: group.contexts
                            .map((c) => _Chip(c, color: _contextColor(c)))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Top 2 deals (or all when expanded)
        ...visible.map(
          (p) => DealCard(
            promo: p,
            memberships: widget.memberships,
            onTap: () {
              widget.onDealTap?.call(p.id, p.brand);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DealDetailScreen(promo: p)),
              );
            },
          ),
        ),
        // Expand / collapse row
        if (hasMore)
          InkWell(
            onTap: () {
              final opening = !_expanded;
              setState(() => _expanded = opening);
              if (opening) widget.onExpanded?.call();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: Candy.raspberry,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _expanded
                        ? 'Show less'
                        : '+$overflow more from ${group.brand}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Candy.raspberry,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const Divider(height: 8, indent: 16, endIndent: 16),
      ],
    );
  }

  void _showScoreBreakdown(BuildContext context) {
    final svc   = widget.svc!;
    final prefs = widget.prefs;
    final group = widget.group;
    final brand = group.brand;
    final deals = group.deals;

    // ── Behavioral affinity ───────────────────────────────────────────────
    int brandClicks = 0, brandSaves = 0, brandRedeems = 0;
    for (final p in deals) {
      if (svc.clickCount(p.id) > 0)              brandClicks++;
      if (svc.hasFastRedeemed(p.id))             brandRedeems++;
      if (SavedDealsService().get(p.id) != null) brandSaves++;
    }
    final behavAffinity = ((brandSaves.clamp(0, 3) * 10.0)
            + (brandRedeems.clamp(0, 2) * 8.0)
            + (brandClicks.clamp(0, 5) * 3.0))
        .clamp(0.0, 35.0);

    // ── Onboarding preferences ────────────────────────────────────────────
    bool isFavBrand = false;
    bool isFavCat   = false;
    if (prefs != null) {
      final bl = brand.toLowerCase();
      isFavBrand = prefs.favoriteBrands.any((b) {
        final bfl = b.toLowerCase();
        return bfl == bl || bl.contains(bfl) || bfl.contains(bl);
      });
      final cl = deals.first.category.toLowerCase();
      isFavCat = cl.isNotEmpty &&
          prefs.favoriteCategories.any((c) => c.toLowerCase() == cl);
    }

    // ── Other signals ─────────────────────────────────────────────────────
    final recentSearch   = svc.isBrandRecentlySearched(brand);
    final dealCountBonus = deals.length.clamp(0, 3) * 2.0;
    final bestQ          = deals
        .map((d) => d.globalQualityScore)
        .reduce((a, b) => a > b ? a : b);
    final qualityBonus = bestQ * 0.3;

    final total = group.bestScore;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                BrandLogo(promo: deals.first, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    brand,
                    style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700,
                      color: Candy.chocolate,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Candy.raspberry.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Score ${total.toStringAsFixed(1)}',
                    style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: Candy.raspberry,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _ScoreSection(
              label: 'Behavioral affinity',
              value: behavAffinity,
              detail: _behavDetail(brandSaves, brandRedeems, brandClicks),
            ),
            _ScoreSection(
              label: 'Favourite brand',
              value: isFavBrand ? 30.0 : 0.0,
              detail: isFavBrand ? 'In your saved brands' : 'Not a saved brand',
            ),
            _ScoreSection(
              label: 'Favourite category',
              value: isFavCat ? 20.0 : 0.0,
              detail: isFavCat
                  ? '${deals.first.category} is a saved category'
                  : 'Category not saved',
              note: '+ inferred weight from brand mix',
            ),
            _ScoreSection(
              label: 'Recently searched',
              value: recentSearch ? 22.0 : 0.0,
              detail: recentSearch ? 'Searched this session' : 'Not searched this session',
            ),
            _ScoreSection(
              label: 'Deal count (${deals.length})',
              value: dealCountBonus,
              detail: '${deals.length.clamp(0, 3)} × 2 pts',
            ),
            _ScoreSection(
              label: 'Quality tiebreaker',
              value: qualityBonus,
              detail: 'Best deal ${bestQ.toStringAsFixed(0)} × 0.3',
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text(
              'Total: ${total.toStringAsFixed(1)}',
              style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: Candy.chocolate,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Higher score = this brand appears earlier in your feed.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  String _behavDetail(int saves, int redeems, int clicks) {
    if (saves == 0 && redeems == 0 && clicks == 0) return 'No interactions yet';
    final parts = <String>[];
    if (saves   > 0) parts.add('$saves save${saves   == 1 ? '' : 's'}');
    if (redeems > 0) parts.add('$redeems redeem${redeems == 1 ? '' : 's'}');
    if (clicks  > 0) parts.add('$clicks click${clicks  == 1 ? '' : 's'}');
    return parts.join(', ');
  }

  Color _contextColor(String label) {
    switch (label) {
      case 'Near Me':  return const Color(0xFF1565C0);
      case 'Rewards':  return Candy.mint;
      default:         return Candy.lavender;
    }
  }
}

// ── Score row ─────────────────────────────────────────────────────────────────

class _ScoreSection extends StatelessWidget {
  final String label;
  final double value;
  final String detail;
  final String? note;

  const _ScoreSection({
    required this.label,
    required this.value,
    required this.detail,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final positive = value > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: Candy.chocolate)),
                Text(detail,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                if (note != null)
                  Text(note!,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                          fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            positive ? '+${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}' : '0',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: positive ? Candy.raspberry : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Context chip ──────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
