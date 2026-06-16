import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/promotion.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/promotions_service.dart';
import '../services/user_memberships_service.dart';
import 'deal_detail_screen.dart';
import 'for_you_screen.dart';
import 'near_me_screen.dart';
import 'online_screen.dart';
import 'rewards_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  List<Promotion> _all = [];
  bool _loading = true;
  Position? _position;
  bool _locating = false;
  Set<String> _memberships = {};
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final results = await Future.wait([
      PromotionsService.load(),
      UserMembershipsService.load(),
    ]);
    final promos = results[0] as List<Promotion>;
    final memberships = results[1] as Set<String>;
    setState(() {
      _all = promos;
      _memberships = memberships;
      _loading = false;
    });
    _fetchLocation();
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

  Future<void> _fetchLocation() async {
    setState(() => _locating = true);
    final position = await LocationService.getPosition();
    if (position != null) {
      await LocationService.attachDistances(_all, position);
    }
    if (mounted) {
      setState(() {
        _position = position;
        _locating = false;
      });
    }
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
          NearMeScreen(
            all: _all,
            position: _position,
            locating: _locating,
            memberships: _memberships,
            onRefresh: _loadData,
          ),
          OnlineScreen(all: _all, memberships: _memberships),
          RewardsScreen(all: _all, memberships: _memberships),
          ForYouScreen(all: _all, memberships: _memberships),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: _locating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.near_me_outlined),
            selectedIcon: const Icon(Icons.near_me),
            label: 'Near Me',
          ),
          const NavigationDestination(
            icon: Icon(Icons.laptop_outlined),
            selectedIcon: Icon(Icons.laptop),
            label: 'Online',
          ),
          const NavigationDestination(
            icon: Icon(Icons.card_membership_outlined),
            selectedIcon: Icon(Icons.card_membership),
            label: 'Rewards',
          ),
          const NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'For You',
          ),
        ],
      ),
    );
  }
}
