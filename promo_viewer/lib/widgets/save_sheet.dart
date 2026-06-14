import 'package:flutter/material.dart';
import '../models/promotion.dart';
import '../services/saved_deals_service.dart';
import '../theme/candy_colors.dart';

class SaveSheet extends StatelessWidget {
  final Promotion promo;
  final SavedDealsService svc;

  const SaveSheet({super.key, required this.promo, required this.svc});

  // Returns (remindAt, offerText) based on how much time is left.
  // remindAt is null when no sensible future reminder can be offered.
  (DateTime?, String) _reminderOffer() {
    final end = promo.endDate != null ? DateTime.tryParse(promo.endDate!) : null;
    if (end == null) return (null, 'No expiry date — reminder not available.');

    final daysLeft = end.difference(DateTime.now()).inDays;

    if (daysLeft > 2) {
      final twoBeforeEnd = end.subtract(const Duration(days: 2));
      final remindAt = DateTime(
          twoBeforeEnd.year, twoBeforeEnd.month, twoBeforeEnd.day, 9, 0);
      return (remindAt, 'Remind you 2 days before it ends?');
    }

    if (daysLeft >= 1) {
      return (
        DateTime.now().add(const Duration(hours: 3)),
        'Deal ends very soon — remind you in 3 hours?',
      );
    }

    return (null, 'Expires today — no reminder needed.');
  }

  @override
  Widget build(BuildContext context) {
    final (remindAt, offerText) = _reminderOffer();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.favorite, color: Candy.raspberry, size: 20),
              SizedBox(width: 8),
              Text(
                'Saved',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Candy.chocolate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            offerText,
            style: const TextStyle(fontSize: 14, color: Candy.muted),
          ),
          const SizedBox(height: 16),
          if (remindAt != null)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('No thanks'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style:
                        FilledButton.styleFrom(backgroundColor: Candy.raspberry),
                    onPressed: () {
                      svc.setReminder(promo.id, remindAt);
                      Navigator.pop(context);
                    },
                    child: const Text('Yes'),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ),
        ],
      ),
    );
  }
}
