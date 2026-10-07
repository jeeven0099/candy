import 'package:flutter/material.dart';

import '../models/promotion.dart';
import '../theme/candy_colors.dart';

class DealBrandLabel extends StatelessWidget {
  final Promotion promo;
  const DealBrandLabel({super.key, required this.promo});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          promo.brand.toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 10,
            color: Candy.chocolate.withValues(alpha: 0.45),
          ),
        ),
        if (promo.isEmailDerived)
          Semantics(
            label: 'Deal from your email',
            child: ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Candy.raspberry.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mail_outline, size: 11, color: Candy.raspberry),
                    SizedBox(width: 3),
                    Text(
                      'Email',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Candy.raspberry,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
