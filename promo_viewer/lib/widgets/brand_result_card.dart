import 'package:flutter/material.dart';
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

  const BrandResultCard({
    super.key,
    required this.group,
    this.memberships = const {},
    this.onExpanded,
    this.onDealTap,
  });

  @override
  State<BrandResultCard> createState() => _BrandResultCardState();
}

class _BrandResultCardState extends State<BrandResultCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final lead = group.deals.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            final opening = !_expanded;
            setState(() => _expanded = opening);
            if (opening) widget.onExpanded?.call();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                        children: [
                          _Chip(
                            '${group.deals.length} deal${group.deals.length == 1 ? '' : 's'}',
                            color: Candy.raspberry,
                          ),
                          ...group.contexts.map((c) => _Chip(c, color: _contextColor(c))),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: Candy.muted,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          ...group.deals.map(
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
        const Divider(height: 8, indent: 16, endIndent: 16),
      ],
    );
  }

  Color _contextColor(String label) {
    switch (label) {
      case 'Near Me':  return const Color(0xFF1565C0);
      case 'Rewards':  return Candy.mint;
      default:         return Candy.lavender;
    }
  }
}

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
