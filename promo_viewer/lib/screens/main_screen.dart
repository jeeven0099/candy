import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/promotion.dart';
import '../theme/candy_colors.dart';
import '../services/interaction_service.dart';
import '../services/notification_service.dart';
import '../services/promotions_service.dart';
import '../services/user_memberships_service.dart';
import 'deal_detail_screen.dart';
import 'profile_screen.dart';
import 'saved_screen.dart';
import 'search_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  List<Promotion> _all = [];
  bool _loading = true;
  bool _error = false;
  Set<String> _memberships = {};
  DateTime? _lastUpdated;
  int _tab = 0;
  final _svc = InteractionService();

  @override
  void initState() {
    super.initState();
    NotificationService.tapNotifier.addListener(_onLateNotificationTap);
    _loadData();
  }

  @override
  void dispose() {
    NotificationService.tapNotifier.removeListener(_onLateNotificationTap);
    super.dispose();
  }

  void _onLateNotificationTap() {
    if (_all.isNotEmpty) _handlePendingNotification(_all);
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        PromotionsService.load(),
        UserMembershipsService.load(),
      ]);
      final promos      = results[0] as List<Promotion>;
      final memberships = results[1] as Set<String>;
      if (mounted) {
        setState(() {
          _all          = promos;
          _memberships  = memberships;
          _loading      = false;
          _error        = false;
          _lastUpdated  = DateTime.now();
        });
      }
      _svc.recordSessionStart();
      _handlePendingNotification(promos);
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  void _handlePendingNotification(List<Promotion> promos) {
    final promoId = NotificationService.pendingPromoId;
    if (promoId == null) return;
    NotificationService.pendingPromoId = null;
    final matches = promos.where((p) => p.id == promoId);
    if (matches.isEmpty || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DealDetailScreen(promo: matches.first)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('Could not load deals',
                  style: TextStyle(fontSize: 16, color: Colors.black54)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  setState(() { _loading = true; _error = false; });
                  _loadData();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final mq = MediaQuery.of(context);
    return Scaffold(
      extendBody: true,
      body: MediaQuery(
        data: mq.copyWith(
          padding: mq.padding.copyWith(
            bottom: mq.padding.bottom + _kNavBarHeight,
          ),
        ),
        child: IndexedStack(
          index: _tab,
          children: [
            SearchScreen(
              all:         _all,
              memberships: _memberships,
              lastUpdated: _lastUpdated,
              onRefresh:   _loadData,
            ),
            SavedScreen(
              all:         _all,
              memberships: _memberships,
              onRefresh:   _loadData,
            ),
            const ProfileScreen(),
          ],
        ),
      ),
      bottomNavigationBar: _GlassNavBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          _svc.recordTabSwitch(i, const ['Deals', 'Saved', 'Profile'][i]);
        },
      ),
    );
  }
}

// ── Constants ─────────────────────────────────────────────────────────────────

const double _kNavBarHeight = 60.0;

// ── Glass navigation bar ──────────────────────────────────────────────────────

class _GlassNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const _GlassNavBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  static const _destinations = [
    (icon: Icons.local_offer_outlined, selectedIcon: Icons.local_offer,  label: 'Deals'),
    (icon: Icons.favorite_border,      selectedIcon: Icons.favorite,      label: 'Saved'),
    (icon: Icons.person_outline,       selectedIcon: Icons.person,        label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.65),
                Colors.white.withValues(alpha: 0.85),
              ],
            ),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.60),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: _kNavBarHeight,
              child: Row(
                children: List.generate(
                  _destinations.length,
                  (i) => Expanded(
                    child: _GlassNavItem(
                      icon:         _destinations[i].icon,
                      selectedIcon: _destinations[i].selectedIcon,
                      label:        _destinations[i].label,
                      selected:     i == selectedIndex,
                      onTap:        () => onDestinationSelected(i),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassNavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GlassNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: selected
                ? BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.50),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.75),
                      width: 0.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  )
                : null,
            child: Icon(
              selected ? selectedIcon : icon,
              size: 22,
              color: selected
                  ? Candy.raspberry
                  : Candy.muted.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected
                  ? Candy.raspberry
                  : Candy.muted.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}
