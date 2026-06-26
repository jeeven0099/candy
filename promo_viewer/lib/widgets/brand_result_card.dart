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

    // ── Compute components ────────────────────────────────────────────────
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

    bool isFavBrand = false;
    bool isFavCat   = false;
    String catName  = '';
    if (prefs != null) {
      final bl = brand.toLowerCase();
      isFavBrand = prefs.favoriteBrands.any((b) {
        final bfl = b.toLowerCase();
        return bfl == bl || bl.contains(bfl) || bfl.contains(bl);
      });
      catName = deals.first.category;
      final cl = catName.toLowerCase();
      isFavCat = cl.isNotEmpty &&
          prefs.favoriteCategories.any((c) => c.toLowerCase() == cl);
    }

    final recentSearch   = svc.isBrandRecentlySearched(brand);
    final dealCountBonus = deals.length.clamp(0, 3) * 2.0;
    final bestQ          = deals
        .map((d) => d.globalQualityScore)
        .reduce((a, b) => a > b ? a : b);
    final qualityBonus = bestQ * 0.3;
    final total        = group.bestScore;

    // ── Friendly reasons ──────────────────────────────────────────────────
    final reasons = <({IconData icon, String text, bool active})>[
      (
        icon:   Icons.touch_app_outlined,
        text:   behavAffinity > 0
            ? _behavSentence(brandSaves, brandRedeems, brandClicks)
            : 'No interactions with $brand deals yet',
        active: behavAffinity > 0,
      ),
      (
        icon:   Icons.favorite_outline,
        text:   isFavBrand
            ? '$brand is one of your favourite brands'
            : '$brand is not in your saved brands',
        active: isFavBrand,
      ),
      (
        icon:   Icons.category_outlined,
        text:   isFavCat
            ? '${_capitalize(catName)} matches your saved categories'
            : '${_capitalize(catName)} is not a saved category',
        active: isFavCat,
      ),
      (
        icon:   Icons.search,
        text:   recentSearch
            ? 'You searched for $brand this session'
            : 'You haven\'t searched $brand this session',
        active: recentSearch,
      ),
      (
        icon:   Icons.local_offer_outlined,
        text:   '${deals.length} live deal${deals.length == 1 ? '' : 's'} available from $brand',
        active: deals.length > 1,
      ),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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

            // Header
            const Text(
              'Why this brand ranked here',
              style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: Candy.chocolate,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Candy placed $brand based on these signals.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),

            // ── Visual formula ─────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total = behavior + fav brand + category + recent search + deal count + quality',
                    style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _FormulaCell(
                          value: total,
                          label: 'total',
                          highlight: true,
                        ),
                        _formulaOp('='),
                        _FormulaCell(value: behavAffinity,              label: 'behavior'),
                        _formulaOp('+'),
                        _FormulaCell(value: isFavBrand ? 30.0 : 0.0,   label: 'fav brand'),
                        _formulaOp('+'),
                        _FormulaCell(value: isFavCat   ? 20.0 : 0.0,   label: 'category'),
                        _formulaOp('+'),
                        _FormulaCell(value: recentSearch ? 22.0 : 0.0,  label: 'recent'),
                        _formulaOp('+'),
                        _FormulaCell(value: dealCountBonus,             label: 'deals'),
                        _formulaOp('+'),
                        _FormulaCell(value: qualityBonus,               label: 'quality'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Friendly signal list ───────────────────────────────────────
            ...reasons.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    r.active ? r.icon : r.icon,
                    size: 16,
                    color: r.active ? Candy.raspberry : Colors.grey.shade400,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.text,
                      style: TextStyle(
                        fontSize: 13,
                        color: r.active ? Candy.chocolate : Colors.grey.shade400,
                        fontWeight: r.active ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  String _behavSentence(int saves, int redeems, int clicks) {
    final parts = <String>[];
    if (saves   > 0) parts.add('saved $saves deal${saves   == 1 ? '' : 's'}');
    if (redeems > 0) parts.add('redeemed $redeems deal${redeems == 1 ? '' : 's'}');
    if (clicks  > 0) parts.add('clicked $clicks deal${clicks  == 1 ? '' : 's'}');
    return 'You\'ve ${parts.join(' and ')} from ${widget.group.brand}';
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _formulaOp(String op) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      op,
      style: TextStyle(
        fontSize: 15, fontWeight: FontWeight.w500, color: Colors.grey.shade400,
      ),
    ),
  );

  Color _contextColor(String label) {
    switch (label) {
      case 'Near Me':  return const Color(0xFF1565C0);
      case 'Rewards':  return Candy.mint;
      default:         return Candy.lavender;
    }
  }
}

// ── Formula cell ──────────────────────────────────────────────────────────────

class _FormulaCell extends StatelessWidget {
  final double value;
  final String label;
  final bool highlight;

  const _FormulaCell({
    required this.value,
    required this.label,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final active = value > 0;
    final numStr = value % 1 == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: highlight
                ? Candy.raspberry
                : active
                    ? Candy.raspberry.withValues(alpha: 0.1)
                    : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            numStr,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: highlight
                  ? Colors.white
                  : active
                      ? Candy.raspberry
                      : Colors.grey.shade400,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade500,
          ),
        ),
      ],
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
