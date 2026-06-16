import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/promotion.dart';
import '../theme/candy_colors.dart';
import '../utils/deal_grouper.dart';
import '../widgets/deal_card.dart';
import '../widgets/grocery_group_card.dart';
import 'deal_detail_screen.dart';

class NearMeScreen extends StatefulWidget {
  final List<Promotion> all;
  final Position? position;
  final bool locating;
  final Set<String> memberships;
  final Future<void> Function() onRefresh;

  const NearMeScreen({
    super.key,
    required this.all,
    required this.position,
    required this.locating,
    required this.onRefresh,
    this.memberships = const {},
  });

  @override
  State<NearMeScreen> createState() => _NearMeScreenState();
}

class _NearMeScreenState extends State<NearMeScreen> {
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Promotion> get _filtered {
    final position = widget.position;

    // Before location is ready show nothing meaningful
    if (position == null) return [];

    final q = _query.toLowerCase();

    return widget.all.where((p) {
      // Only active deals
      if (!p.isActive) return false;
      // Must have a store distance (brand has locations)
      if (p.distanceKm == null) return false;
      // Rewards programs belong in the Rewards tab
      if (p.promotionType == 'reward' || p.promotionType == 'membership_benefit') return false;
      // Only redemption methods that make sense in-person
      const nearMeRedemption = {
        'in_store', 'in_app', 'app_reward', 'show_code', 'open_maps',
      };
      if (!nearMeRedemption.contains(p.redemptionMethod)) return false;
      // Online-only deals belong in the Online tab
      if (p.dealScope == 'online_only') return false;
      // Email-sourced deals belong in For You, not Near Me
      if (p.source == 'email') return false;
      // Categories that are never walk-in store deals
      const blockedCategories = {
        'finance', 'travel', 'streaming', 'subscription',
        'meal_kit', 'delivery_only',
      };
      if (blockedCategories.contains(p.category)) return false;
      // Brands that are service/delivery/online-only — not physical storefronts
      const blockedBrands = {
        'chase', 'uber', 'hungryroot',
      };
      if (blockedBrands.contains(p.brand.toLowerCase())) return false;
      // Search
      if (q.isNotEmpty &&
          !p.brand.toLowerCase().contains(q) &&
          !p.title.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.rankScore(
            distanceKm: b.distanceKm,
            isMember: _hasMembership(b),
          ).compareTo(a.rankScore(
            distanceKm: a.distanceKm,
            isMember: _hasMembership(a),
          )));
  }

  bool _hasMembership(Promotion p) {
    if (widget.memberships.isEmpty) return false;
    final brand = p.brand.toLowerCase();
    final memberName = (p.membershipName ?? '').toLowerCase();
    return widget.memberships.any((m) =>
        m.contains(brand) || brand.contains(m) ||
        (memberName.isNotEmpty && (m.contains(memberName) || memberName.contains(m))));
  }

  @override
  Widget build(BuildContext context) {
    final promos = _filtered;

    return Scaffold(
      backgroundColor: Candy.cream,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Expanded(child: _buildBody(promos)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.near_me, size: 22),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Near Me',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: Candy.chocolate,
                    ),
                  ),
                  const Text(
                    'Sweet deals nearby',
                    style: TextStyle(
                      fontSize: 12,
                      color: Candy.lavender,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (widget.locating)
                const Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 6),
                    Text('Locating…',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                )
              else if (widget.position == null)
                Text('Location unavailable',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 12),
          SearchBar(
            controller: _searchController,
            hintText: 'Search nearby deals…',
            leading: const Icon(Icons.search, size: 20),
            trailing: [
              if (_query.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
            ],
            onChanged: (v) => setState(() => _query = v),
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: const WidgetStatePropertyAll(Colors.white),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(List<Promotion> promos) {
    if (widget.locating) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Finding your location…',
                style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    if (widget.position == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off_outlined,
                size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Location permission required',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              'Allow location access in your browser\nto see deals near you.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (promos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined,
                size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No nearby deals found',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
          ],
        ),
      );
    }

    final items = groupGroceryDeals(promos);
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: items.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '${promos.length} deals nearby',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }
          final item = items[i - 1];
          if (item is GroceryGroup) {
            return GroceryGroupCard(
              promos: item.items,
              memberships: widget.memberships,
            );
          }
          final promo = item as Promotion;
          return DealCard(
            promo: promo,
            memberships: widget.memberships,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => DealDetailScreen(promo: promo)),
            ),
          );
        },
      ),
    );
  }
}
