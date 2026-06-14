import 'package:flutter/material.dart';
import '../models/promotion.dart';
import '../theme/candy_colors.dart';
import 'brand_logo.dart';
import '../screens/deal_detail_screen.dart';

class GroceryGroupCard extends StatefulWidget {
  final List<Promotion> promos;
  final Set<String> memberships;

  const GroceryGroupCard({
    super.key,
    required this.promos,
    this.memberships = const {},
  });

  @override
  State<GroceryGroupCard> createState() => _GroceryGroupCardState();
}

class _GroceryGroupCardState extends State<GroceryGroupCard> {
  static const _previewCount = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final promos = widget.promos;
    final brand = promos.first.brand;
    final visible = _expanded ? promos : promos.take(_previewCount).toList();
    final overflow = promos.length - _previewCount;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(promos.first, brand, promos.length),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 6),
            ...visible.map((p) => _buildItemRow(context, p)),
            if (!_expanded && overflow > 0)
              _buildShowMore(overflow)
            else if (_expanded && overflow > 0)
              _buildShowLess(),
          ],
        ),
      ),
    );
  }

  String _headerLabel(String category) {
    switch (category) {
      case 'grocery':
      case 'food':
        return 'Weekly specials';
      case 'fashion':
        return 'Sale items';
      default:
        return 'Sale items';
    }
  }

  IconData _headerIcon(String category) {
    switch (category) {
      case 'grocery':
      case 'food':
        return Icons.local_grocery_store_outlined;
      case 'fashion':
        return Icons.shopping_bag_outlined;
      default:
        return Icons.sell_outlined;
    }
  }

  Widget _buildHeader(Promotion first, String brand, int count) {
    final category = first.category;
    return Row(
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: BrandLogo(promo: first, size: 36),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                brand,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Candy.chocolate,
                ),
              ),
              Text(
                _headerLabel(category),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Candy.mint.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count items',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1FA870),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemRow(BuildContext context, Promotion p) {
    final discount = _discountLabel(p);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DealDetailScreen(promo: p)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        child: Row(
          children: [
            Icon(_headerIcon(p.category), size: 14, color: Candy.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                p.title,
                style: const TextStyle(
                  fontSize: 13,
                  color: Candy.chocolate,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (discount != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Candy.raspberry.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  discount,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Candy.raspberry,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: Candy.muted),
          ],
        ),
      ),
    );
  }

  Widget _buildShowMore(int overflow) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = true),
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            const SizedBox(width: 22),
            Text(
              '+ $overflow more item${overflow == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 13,
                color: Candy.raspberry,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShowLess() {
    return GestureDetector(
      onTap: () => setState(() => _expanded = false),
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            const SizedBox(width: 22),
            Text(
              'Show less',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _discountLabel(Promotion p) {
    if (p.discountValue != null && p.discountValue!.isNotEmpty) {
      return p.discountValue;
    }
    return null;
  }
}
