import 'package:flutter/material.dart';
import '../models/promotion.dart';
import '../theme/candy_colors.dart';

class BrandLogo extends StatefulWidget {
  final Promotion promo;
  final double size;

  const BrandLogo({super.key, required this.promo, this.size = 40});

  @override
  State<BrandLogo> createState() => _BrandLogoState();
}

class _BrandLogoState extends State<BrandLogo> {
  // 0=local asset  1=icon.horse  2=Google favicon  3=initials
  int _attempt = 0;

  String get _initials {
    final words = widget.promo.brand.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) {
      return (words[0][0] + words[1][0]).toUpperCase();
    }
    return widget.promo.brand
        .substring(0, widget.promo.brand.length.clamp(0, 2))
        .toUpperCase();
  }

  Color get _avatarColor {
    const colors = [
      Candy.raspberry,
      Candy.mint,
      Candy.lavender,
      Candy.pink,
      Color(0xFF1565C0),
      Color(0xFFE65100),
      Candy.raspberry,
      Candy.lavender,
    ];
    return colors[widget.promo.brand.hashCode.abs() % colors.length];
  }

  Widget _fallback() {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: _avatarColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(widget.size * 0.25),
      ),
      child: Center(
        child: Text(
          _initials,
          style: TextStyle(
            color: _avatarColor,
            fontWeight: FontWeight.w700,
            fontSize: widget.size * 0.35,
          ),
        ),
      ),
    );
  }

  Widget _shimmer() {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(widget.size * 0.25),
      ),
    );
  }

  void _nextAttempt() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _attempt++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final domain = widget.promo.rootDomain;
    final size = widget.size;

    if (domain == null || _attempt >= 3) return _fallback();

    if (_attempt == 0) {
      // Try local bundled asset first — instant, offline
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.25),
        child: Image.asset(
          'assets/logos/$domain.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) {
            _nextAttempt();
            return _shimmer();
          },
        ),
      );
    }

    final url = _attempt == 1
        ? 'https://icon.horse/icon/$domain'
        : 'https://www.google.com/s2/favicons?domain=$domain&sz=128';

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.25),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) {
          _nextAttempt();
          return _attempt < 3 ? _shimmer() : _fallback();
        },
        loadingBuilder: (context, child, loading) =>
            loading == null ? child : _shimmer(),
      ),
    );
  }
}
