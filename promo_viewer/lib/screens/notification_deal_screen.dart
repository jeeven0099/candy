import 'dart:async';

import 'package:flutter/material.dart';

import '../models/promotion.dart';
import '../services/app_startup_service.dart';
import '../services/notification_deal_resolver.dart';
import '../services/supabase_service.dart';
import 'deal_detail_screen.dart';
import 'main_screen.dart';
import 'onboarding_screen.dart';

class NotificationDealScreen extends StatefulWidget {
  const NotificationDealScreen({
    super.key,
    required this.promoId,
    this.coldStart = false,
    this.initialize,
    this.resolveDeal,
    this.homeBuilder,
    this.onClosed,
  });

  final String promoId;
  final bool coldStart;
  final Future<void> Function()? initialize;
  final Future<Promotion?> Function(String)? resolveDeal;
  final WidgetBuilder? homeBuilder;
  final VoidCallback? onClosed;

  @override
  State<NotificationDealScreen> createState() => _NotificationDealScreenState();
}

class _NotificationDealScreenState extends State<NotificationDealScreen> {
  Promotion? _promo;
  bool _loading = true;
  bool _failed = false;
  bool _initialized = false;

  @override
  void dispose() {
    widget.onClosed?.call();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      await (widget.initialize ?? AppStartupService.init)();
      if (!mounted) return;
      _initialized = true;
      final owner = SupabaseService.currentUserId;
      final promo =
          await (widget.resolveDeal ?? NotificationDealResolver().resolve)(
            widget.promoId,
          );
      if (!mounted) return;
      if (owner != SupabaseService.currentUserId) {
        throw StateError('Account changed while opening a notification');
      }
      setState(() {
        _promo = promo;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _back() {
    if (!widget.coldStart) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder:
            widget.homeBuilder ??
            (_) => SupabaseService.isLoggedIn
                ? const MainScreen()
                : const OnboardingScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final promo = _promo;
    return PopScope<void>(
      canPop: !widget.coldStart,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_loading && _initialized) _back();
      },
      child: promo != null && !_loading && !_failed
          ? DealDetailScreen(
              promo: promo,
              rankingMode: 'notification',
              onBack: widget.coldStart ? _back : null,
            )
          : Scaffold(
              appBar: AppBar(
                title: const Text('Deal'),
                leading: IconButton(
                  tooltip: 'Back',
                  onPressed: widget.coldStart && !_initialized ? null : _back,
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              body: Center(
                child: _loading
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _failed
                                  ? 'Could not open this deal'
                                  : 'This deal is no longer available',
                            ),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
    );
  }
}
