import 'package:flutter/material.dart';

class Candy {
  // Primary action
  static const raspberry  = Color(0xFFA72D52);
  static const berry      = Color(0xFFA72D52); // alias

  // Positive / success
  static const mint       = Color(0xFF168A5B);

  // Deal accent — promo codes, online tags, points
  static const orange     = Color(0xFFEA7A1A);
  static const lavender   = orange; // alias kept for existing references

  // Backgrounds
  static const cream      = Color(0xFFFAFAFA); // page background
  static const surface    = Color(0xFFFFFFFF); // card surface

  // Chip / badge backgrounds and dividers
  static const pink       = Color(0xFFF4F4F5);

  // Text
  static const chocolate  = Color(0xFF18181B); // primary text
  static const muted      = Color(0xFF71717A); // secondary / label text

  // Structural
  static const border     = Color(0xFFE4E4E7); // very subtle borders

  // Quality tier colors — used by ValueTierBadge
  static const tierExcellent = Color(0xFF28A745);
  static const tierGreat     = Color(0xFF2ECC71);
  static const tierGood      = Color(0xFFFF9F0A);
  static const tierFair      = Color(0xFFFF6B2B);
  static const tierLow       = Color(0xFFFF453A);
}
