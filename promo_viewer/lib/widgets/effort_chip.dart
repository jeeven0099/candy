import 'package:flutter/material.dart';
import '../models/promotion.dart';
import '../theme/candy_colors.dart';

class EffortChip extends StatelessWidget {
  final Promotion promo;

  const EffortChip({super.key, required this.promo});

  ({String label, Color color})? get _config {
    final fr = promo.fastRedemption;
    if (fr != null && fr.eligible) {
      return fr.isLowEffort
          ? (label: 'Instant redeem', color: Candy.mint)
          : (label: 'Easy redeem',    color: Candy.mint);
    }
    if (promo.requiresApp)     return (label: 'App required',  color: Candy.orange);
    if (promo.promoCode != null) return (label: 'Code required', color: Candy.orange);
    if (!promo.requiresMembership) return (label: 'Easy redeem', color: Candy.mint);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _config;
    if (cfg == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cfg.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cfg.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: cfg.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            cfg.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cfg.color,
            ),
          ),
        ],
      ),
    );
  }
}
