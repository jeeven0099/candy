import 'package:flutter/material.dart';

import '../models/promotion.dart';
import '../services/notification_service.dart';
import '../services/promotions_service.dart';
import '../services/user_memberships_service.dart';
import 'deal_detail_screen.dart';
import 'for_you_screen.dart';
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
  Set<String> _memberships = {};
  DateTime? _lastUpdated;
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
    if (_all.isNotEmpty) _handlePendingNotification(_all);
  }

  Future<void> _loadData() async {
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
        _lastUpdated  = DateTime.now();
      });
    }
    _handlePendingNotification(promos);
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

    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          SearchScreen(
            all:         _all,
            memberships: _memberships,
            lastUpdated: _lastUpdated,
            onRefresh:   _loadData,
          ),
          ForYouScreen(
            all:         _all,
            memberships: _memberships,
            onRefresh:   _loadData,
          ),
          SavedScreen(
            all:         _all,
            memberships: _memberships,
            onRefresh:   _loadData,
          ),
          ProfileScreen(
            memberships: _memberships,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon:         Icon(Icons.local_offer_outlined),
            selectedIcon: Icon(Icons.local_offer),
            label:        'Deals',
          ),
          NavigationDestination(
            icon:         Icon(Icons.cake_outlined),
            selectedIcon: Icon(Icons.cake),
            label:        'For You',
          ),
          NavigationDestination(
            icon:         Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label:        'Saved',
          ),
          NavigationDestination(
            icon:         Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label:        'Profile',
          ),
        ],
      ),
    );
  }
}
