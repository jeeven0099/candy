import 'package:flutter/material.dart';
import '../theme/candy_colors.dart';

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip({super.key, required this.status});

  Color get _color {
    switch (status) {
      case 'active':          return Candy.mint;
      case 'probably_active': return Candy.mint;
      case 'online_only':     return Candy.lavender;
      case 'expired':         return Candy.muted;
      case 'needs_review':    return const Color(0xFFF57F17);
      case 'low_confidence':  return Candy.muted;
      default:                return Candy.muted;
    }
  }

  String get _label {
    switch (status) {
      case 'active':          return 'Active';
      case 'probably_active': return 'Active';
      case 'online_only':     return 'Online';
      case 'expired':         return 'Expired';
      case 'needs_review':    return 'Unverified';
      case 'low_confidence':  return 'Unverified';
      default:                return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          _label,
          style: TextStyle(
            color: _color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
