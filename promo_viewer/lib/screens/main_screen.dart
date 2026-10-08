import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/promotion.dart';
import '../services/email_deals_service.dart';
import '../services/gmail_connection_service.dart';
import '../services/interaction_service.dart';
import '../services/learned_preference_service.dart';
import '../services/user_prefs_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/promotions_service.dart';
import '../services/supabase_service.dart';
import '../services/user_memberships_service.dart';
import '../theme/candy_colors.dart';
import 'deal_detail_screen.dart';
import 'for_you_screen.dart';
import 'near_me_screen.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _svc = InteractionService();

  List<Promotion> _all = [];
  Set<String> _memberships = {};
  Position? _position;
  DateTime? _lastUpdated;
  bool _loading = true;
  bool _error = false;
  bool _locating = false;
  int _tab = 0;

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
    final promoId = NotificationService.tapNotifier.value;
    if (promoId == null || !mounted) return;
    NotificationService.tapNotifier.value = null;
    if (_all.isEmpty) return;
    _openPromoById(promoId);
  }

  void _openPromoById(String promoId) {
    final matches = _all.where((p) => p.id == promoId);
    if (matches.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DealDetailScreen(promo: matches.first),
        ),
      );
    });
  }

  Future<void> _loadData() async {
    try {
      await GmailConnectionService.restorePendingConnect();
      if (GmailConnectionService.hasPendingConnect) {
        try {
          await GmailConnectionService.vaultSessionIfPending(
            SupabaseService.client.auth.currentSession,
          );
        } catch (e) {
          GmailConnectionService.reportFailure('restore_connection', e);
        }
      }
      final results = await Future.wait([
        PromotionsService.load(),
        EmailDealsService.loadForCurrentUser(),
        UserMembershipsService.load(),
      ]);
      final promos = results[0] as List<Promotion>;
      final emailPromos = results[1] as List<Promotion>;
      final memberships = results[2] as Set<String>;
      final learned = LearnedPreferenceService();
      unawaited(learned.loadForCurrentUser(UserPrefsService().userId));
      learned.setMembershipContext(memberships);
      final combined = EmailDealsService.mergeWithPublicPromotions(
        promos,
        emailPromos,
      );

      final position = _position;
      if (position != null) {
        await LocationService.attachDistances(combined, position);
      }

      if (!mounted) return;
      setState(() {
        _all = combined;
        _memberships = memberships;
        _loading = false;
        _error = false;
        _lastUpdated = DateTime.now();
      });
      _svc.recordSessionStart();
      await _navigatePendingNotification();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _navigatePendingNotification() async {
    String? promoId = await NotificationService.consumePendingPromoId();
    promoId ??= NotificationService.pendingPromoId;
    NotificationService.pendingPromoId = null;
    promoId ??= NotificationService.tapNotifier.value;
    NotificationService.tapNotifier.value = null;
    if (promoId == null || !mounted) return;
    _openPromoById(promoId);
  }

  Future<void> _ensureLocation() async {
    if (_locating || _position != null) return;
    setState(() => _locating = true);
    final position = await LocationService.getPosition();
    if (position != null) {
      await LocationService.attachDistances(_all, position);
    }
    if (!mounted) return;
    setState(() {
      _position = position;
      _locating = false;
    });
  }

  Future<void> _refreshCurrentTab() async {
    await _loadData();
    if (_tab == 1) {
      if (_position == null) {
        await _ensureLocation();
      } else {
        await LocationService.attachDistances(_all, _position!);
        if (mounted) setState(() {});
      }
    }
  }

  void _selectTab(int index) {
    final returningFromSettings = _tab == 2 && index != 2;
    setState(() => _tab = index);
    _svc.recordTabSwitch(
      index,
      const ['For You', 'Near Me', 'Settings'][index],
    );
    if (index == 1) {
      _ensureLocation();
    }
    if (returningFromSettings) unawaited(_reloadEmailDeals());
  }

  Future<void> _reloadEmailDeals() async {
    try {
      final account = SupabaseService.currentUserId;
      final emails = await EmailDealsService.loadForCurrentUser();
      if (!mounted || account != SupabaseService.currentUserId) return;
      final combined = EmailDealsService.mergeWithPublicPromotions(
        PromotionsService.cached,
        emails,
      );
      if (_position != null) {
        await LocationService.attachDistances(combined, _position!);
      }
      if (!mounted || account != SupabaseService.currentUserId) return;
      setState(() => _all = combined);
    } catch (_) {
      debugPrint('[MainScreen] Could not refresh email deals');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Could not load deals',
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = false;
                  });
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
            ForYouScreen(
              all: _all,
              active: _tab == 0,
              memberships: _memberships,
              onRefresh: _refreshCurrentTab,
            ),
            NearMeScreen(
              all: _all,
              active: _tab == 1,
              position: _position,
              locating: _locating,
              memberships: _memberships,
              lastUpdated: _lastUpdated,
              onRefresh: _refreshCurrentTab,
              onRequestLocation: _ensureLocation,
            ),
            const ProfileScreen(),
          ],
        ),
      ),
      bottomNavigationBar: _GlassNavBar(
        selectedIndex: _tab,
        onDestinationSelected: _selectTab,
      ),
    );
  }
}

const double _kNavBarHeight = 60.0;

class _GlassNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const _GlassNavBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  static const _destinations = [
    (
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome,
      label: 'For You',
    ),
    (
      icon: Icons.near_me_outlined,
      selectedIcon: Icons.near_me,
      label: 'Near Me',
    ),
    (
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Settings',
    ),
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
                      icon: _destinations[i].icon,
                      selectedIcon: _destinations[i].selectedIcon,
                      label: _destinations[i].label,
                      selected: i == selectedIndex,
                      onTap: () => onDestinationSelected(i),
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
