import 'package:flutter/material.dart';
import '../models/promotion.dart';
import '../theme/candy_colors.dart';

class SavingsLabel extends StatelessWidget {
  final Promotion promo;
  final double fontSize;
  final FontWeight fontWeight;
  final Color? color;

  const SavingsLabel({
    super.key,
    required this.promo,
    this.fontSize = 26,
    this.fontWeight = FontWeight.w800,
    this.color,
  });

  // Categories where "Free drink" or "30% off" reads better than "Save $5"
  static const _commodityCats = {'food', 'fast_food', 'coffee', 'grocery', 'restaurant'};

  String get _text {
    final savings = promo.estimatedSavings;
    final cat = promo.category.toLowerCase();
    if (savings != null && savings >= 10 && !_commodityCats.contains(cat)) {
      return 'Save \$${savings.round()}';
    }
    return switch (promo.discountType) {
      'free_item'     => 'Free item',
      'free_shipping' => 'Free shipping',
      _               => promo.displayValue,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: fontSize >= 20 ? -1.0 : -0.3,
        height: 1.1,
        color: color ?? Candy.chocolate,
      ),
    );
  }
}
