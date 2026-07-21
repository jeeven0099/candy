import 'package:flutter/material.dart';
import '../models/promotion.dart';

class UrgencyChip extends StatelessWidget {
  final Promotion promo;

  const UrgencyChip({super.key, required this.promo});

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
    if (days == null || days > 7) return const SizedBox.shrink();
    final isHot = days <= 2;
    final color = isHot ? const Color(0xFFC62828) : const Color(0xFFE65100);
    final label = days == 0 ? 'Expires today' : '$days day${days == 1 ? '' : 's'} left';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isHot ? Icons.local_fire_department : Icons.schedule,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
