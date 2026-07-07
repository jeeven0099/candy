import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/fast_redemption.dart';
import '../services/interaction_service.dart';
import '../theme/candy_colors.dart';

class FastRedeemButton extends StatelessWidget {
  final FastRedemption fr;
  final String brand;
  final String promoId;
  const FastRedeemButton({super.key, required this.fr, required this.brand, required this.promoId});

  // ── Styling ────────────────────────────────────────────────────────────────

  IconData get _icon {
    switch (fr.actionType) {
      case 'copy_code':               return Icons.copy;
      case 'copy_code_and_open_url':  return Icons.shopping_bag_outlined;
      case 'open_url':                return Icons.open_in_new;
      case 'open_app':                return Icons.smartphone;
      case 'open_maps':               return Icons.near_me;
      case 'open_rewards':            return Icons.card_membership;
      case 'show_barcode_or_code':    return Icons.qr_code;
      default:                        return Icons.help_outline;
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _execute(BuildContext ctx) async {
    InteractionService().recordFastRedeem(promoId, brand: brand);
    switch (fr.actionType) {
      case 'copy_code':
        await _copyCode(ctx);
        if (ctx.mounted) {
          _toast(ctx, 'Code ${fr.primaryValue} copied!');
        }
        if (fr.stepsAfterClick.isNotEmpty && ctx.mounted) {
          _showSteps(ctx, title: 'Code copied — next steps:');
        }

      case 'copy_code_and_open_url':
        await _copyCode(ctx);
        if (ctx.mounted) {
          _toast(ctx, 'Code ${fr.primaryValue} copied. Opening $brand…');
        }
        await _openUrl(fr.primaryUrl);

      case 'open_url':
        await _openUrl(fr.primaryUrl);
        if (fr.stepsAfterClick.isNotEmpty && ctx.mounted) {
          _showSteps(ctx, title: "You're there — next steps:");
        }

      case 'open_app':
        if (ctx.mounted) await _showAppOrBrowserPicker(ctx);

      case 'open_maps':
        final query = Uri.encodeComponent('${fr.primaryValue ?? "store"} near me');
        await _openUrl('https://www.google.com/maps/search/$query');
        if (fr.stepsAfterClick.isNotEmpty && ctx.mounted) {
          _showSteps(ctx, title: 'On arrival:');
        }

      case 'show_barcode_or_code':
        if (ctx.mounted) _showCodeModal(ctx);

      case 'open_rewards':
        await _openUrl(fr.primaryUrl);
        if (fr.stepsAfterClick.isNotEmpty && ctx.mounted) {
          _showSteps(ctx, title: 'Next steps:');
        }

      default:
        if (fr.stepsAfterClick.isNotEmpty && ctx.mounted) {
          _showSteps(ctx, title: 'How to redeem:');
        }
    }
  }

  Future<void> _copyCode(BuildContext ctx) async {
    if (fr.primaryValue == null) return;
    await Clipboard.setData(ClipboardData(text: fr.primaryValue!));
  }

  Future<bool> _openUrl(String? url) async {
    if (url == null) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<void> _showAppOrBrowserPicker(BuildContext ctx) async {
    final choice = await showModalBottomSheet<String>(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'How would you like to open this?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 16),
            _pickerOption(
              icon: Icons.smartphone,
              label: 'Open in App',
              subtitle: 'Launch the $brand app',
              value: 'app',
            ),
            const SizedBox(height: 10),
            _pickerOption(
              icon: Icons.open_in_browser,
              label: 'Open in Browser',
              subtitle: 'Go to the website instead',
              value: 'browser',
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );

    if (choice == null || !ctx.mounted) return;

    if (choice == 'app') {
      final opened = fr.appDeepLink != null
          ? await _openUrl(fr.appDeepLink)
          : false;
      if (!opened && ctx.mounted) await _openUrl(fr.webFallbackUrl ?? fr.primaryUrl);
    } else {
      await _openUrl(fr.webFallbackUrl ?? fr.primaryUrl);
    }

    if (fr.stepsAfterClick.isNotEmpty && ctx.mounted) {
      _showSteps(ctx, title: 'In the app, do this:');
    }
  }

  Widget _pickerOption({
    required IconData icon,
    required String label,
    required String subtitle,
    required String value,
  }) {
    return Builder(builder: (ctx) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pop(ctx, value),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Candy.raspberry.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: Candy.raspberry),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
              const Spacer(),
              Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
            ],
          ),
        ),
      );
    });
  }

  void _toast(BuildContext ctx, String message) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Steps bottom sheet ─────────────────────────────────────────────────────

  void _showSteps(BuildContext ctx, {required String title}) {
    showModalBottomSheet(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            ...fr.stepsAfterClick.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            color: Candy.border,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${e.key + 1}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Candy.chocolate,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(e.value,
                              style: const TextStyle(
                                  fontSize: 14, height: 1.4)),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  // ── Code display modal (show_barcode_or_code) ──────────────────────────────

  void _showCodeModal(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Show this at checkout',
                style:
                    TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  const Icon(Icons.qr_code, size: 48, color: Colors.black54),
                  const SizedBox(height: 12),
                  Text(
                    fr.primaryValue ?? '',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: fr.primaryValue ?? ''));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy code'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!fr.eligible || fr.buttonLabel.isEmpty) return const SizedBox.shrink();
    // Hide if there's genuinely nothing to open or copy (email deal with no URL/code)
    final hasAction = fr.primaryUrl != null ||
        fr.appDeepLink != null ||
        fr.webFallbackUrl != null ||
        fr.primaryValue != null;
    if (!hasAction) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => _execute(context),
        icon: Icon(_icon, size: 16),
        label: Text(fr.buttonLabel),
        style: FilledButton.styleFrom(
          backgroundColor: Candy.raspberry,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
