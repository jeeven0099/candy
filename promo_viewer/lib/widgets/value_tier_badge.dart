import 'package:flutter/material.dart';
import '../theme/candy_colors.dart';

class ValueTierBadge extends StatelessWidget {
  final double qualityScore;
  final double fontSize;

  const ValueTierBadge({
    super.key,
    required this.qualityScore,
    this.fontSize = 12,
  });

  static ({String label, Color color}) _tier(double score) {
    if (score >= 80) return (label: 'Excellent Value', color: Candy.tierExcellent);
    if (score >= 65) return (label: 'Great Value',     color: Candy.tierGreat);
    if (score >= 50) return (label: 'Good Value',      color: Candy.tierGood);
    if (score >= 35) return (label: 'Fair Value',      color: Candy.tierFair);
    return              (label: 'Low Value',            color: Candy.tierLow);
  }

  @override
  Widget build(BuildContext context) {
    if (qualityScore <= 0) return const SizedBox.shrink();
    final t = _tier(qualityScore);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: t.color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: t.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            t.label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: t.color,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
