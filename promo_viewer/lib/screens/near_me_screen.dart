import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/promotion.dart';
import '../theme/candy_colors.dart';
import '../services/interaction_service.dart';
import '../services/location_service.dart';
import '../utils/deal_grouper.dart';
import '../utils/feed_ranker.dart';
import '../utils/format_utils.dart';
import '../widgets/deal_card.dart';
import '../widgets/grocery_group_card.dart';
import 'deal_detail_screen.dart';

const _kRadiusKey = 'near_me_radius_mi';
const _kRadiusOptions = [1, 3, 5, 10, 25];

const _kCategories = ['All', 'Food & Coffee', 'Grocery', 'Retail', 'Beauty', 'Entertainment'];
const _kCategoryMap = <String, List<String>>{
  'Food & Coffee': ['food', 'fast_food', 'restaurant', 'coffee'],
  'Grocery':       ['grocery', 'supermarket'],
  'Retail':        ['retail', 'fashion', 'clothing', 'apparel'],
  'Beauty':        ['beauty', 'personal_care'],
  'Entertainment': ['entertainment', 'gaming', 'movies', 'sports'],
};

class NearMeScreen extends StatefulWidget {
  final List<Promotion> all;
  final Position? position;
  final bool locating;
  final Set<String> memberships;
  final DateTime? lastUpdated;
  final Future<void> Function() onRefresh;

  const NearMeScreen({
    super.key,
    required this.all,
    required this.position,
    required this.locating,
    required this.onRefresh,
    this.memberships = const {},
    this.lastUpdated,
  });

  @override
  State<NearMeScreen> createState() => _NearMeScreenState();
}

class _NearMeScreenState extends State<NearMeScreen> {
  String _query = '';
  String _selectedCategory = 'All';
  int _radiusMi = 5;
  bool _showAll = false;
  final _searchController = TextEditingController();
  final _svc = InteractionService();
  final _markedSeen = <String>{};

  @override
  void initState() {
    super.initState();
    _loadRadius();
  }

  Future<void> _loadRadius() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_kRadiusKey);
    if (saved != null && mounted) setState(() => _radiusMi = saved);
  }

  Future<void> _setRadius(int mi) async {
    setState(() => _radiusMi = mi);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kRadiusKey, mi);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _hasMembership(Promotion p) {
    if (widget.memberships.isEmpty) return false;
    final brand = p.brand.toLowerCase();
    final memberName = (p.membershipName ?? '').toLowerCase();
    return widget.memberships.any((m) =>
        m.contains(brand) || brand.contains(m) ||
        (memberName.isNotEmpty && (m.contains(memberName) || memberName.contains(m))));
  }

  bool _isQualityDeal(Promotion p) {
    if (p.confidenceScore < 0.75) return false;
    if (p.discountType == 'points') return false;
    return p.rankScore(distanceKm: p.distanceKm, isMember: _hasMembership(p)) >= 65;
  }

  List<Promotion> get _filtered {
    if (widget.position == null) return [];
    final q = _query.toLowerCase();
    final radiusKm = _radiusMi * 1.60934;
    final cats = _selectedCategory == 'All' ? null : _kCategoryMap[_selectedCategory];

    return widget.all.where((p) {
      if (!p.isActive) return false;
      if (!p.isValidToday) return false;
      if (p.distanceKm == null) return false;
      if (p.promotionType == 'reward' || p.promotionType == 'membership_benefit') return false;
      const nearMeRedemption = {'in_store', 'in_app', 'app_reward', 'show_code', 'open_maps'};
      if (!nearMeRedemption.contains(p.redemptionMethod)) return false;
      if (p.dealScope == 'online_only') return false;
      if (p.source == 'email') return false;
      const blockedCategories = {'finance', 'travel', 'streaming', 'subscription', 'meal_kit', 'delivery_only'};
      if (blockedCategories.contains(p.category)) return false;
      const blockedBrands = {'chase', 'uber', 'hungryroot'};
      if (blockedBrands.contains(p.brand.toLowerCase())) return false;
      if ((p.distanceKm ?? double.infinity) > radiusKm) return false;
      if (cats != null && !cats.contains(p.category.toLowerCase())) return false;
      if (q.isNotEmpty &&
          !p.brand.toLowerCase().contains(q) &&
          !p.title.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.rankScore(distanceKm: b.distanceKm, isMember: _hasMembership(b))
          .compareTo(a.rankScore(distanceKm: a.distanceKm, isMember: _hasMembership(a))));
  }

  // Search bypasses cap; browsing shows curated top 10 with personalized scoring.
  // Local deals (source == local_neighborhood) are capped at 3; nationals fill the rest.
  List<Promotion> _toDisplay(List<Promotion> base) {
    if (_query.isNotEmpty || _showAll) return base;

    final local = base.where((p) => p.isLocal && p.confidenceScore >= 0.85 && _isQualityDeal(p)).toList()
      ..sort((a, b) => b.rankScore(distanceKm: b.distanceKm, isMember: _hasMembership(b))
          .compareTo(a.rankScore(distanceKm: a.distanceKm, isMember: _hasMembership(a))));
    final topLocal = local.take(3).toList();

    final nationalLimit = 10 - topLocal.length;
    final national = base.where((p) => !p.isLocal).toList();
    final topNational = selectTopDeals(
      national.where(_isQualityDeal).toList(), _svc,
      getDistance: (p) => p.distanceKm,
      getIsMember: _hasMembership,
      limit: nationalLimit,
    );

    final combined = [...topLocal, ...topNational]
      ..sort((a, b) => b.rankScore(distanceKm: b.distanceKm, isMember: _hasMembership(b))
          .compareTo(a.rankScore(distanceKm: a.distanceKm, isMember: _hasMembership(a))));
    return combined;
  }

  void _maybeMarkSeen(List<Promotion> promos) {
    if (_showAll || _query.isNotEmpty) return;
    final newIds = promos.map((p) => p.id).where((id) => !_markedSeen.contains(id)).toList();
    if (newIds.isEmpty) return;
    _markedSeen.addAll(newIds);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _svc.recordSeen(newIds);
    });
  }

  void _showRadiusPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(
                'Distance Radius',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            ..._kRadiusOptions.map((mi) => ListTile(
                  title: Text('Within $mi mi'),
                  leading: Icon(
                    _radiusMi == mi ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: _radiusMi == mi ? Candy.raspberry : null,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _setRadius(mi);
                  },
                )),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _filtered;
    final display = _toDisplay(all);
    _maybeMarkSeen(display);

    return Scaffold(
      backgroundColor: Candy.cream,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildCategoryChips(),
            const Divider(height: 1),
            Expanded(child: _buildBody(display, all)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final updated = widget.lastUpdated;
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
                  Text(
                    widget.position != null
                        ? LocationService.cityName(
                            widget.position!.latitude,
                            widget.position!.longitude,
                          )
                        : 'Sweet deals nearby',
                    style: const TextStyle(
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
                    Text('Locating…', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                )
              else if (widget.position == null)
                Text('Location unavailable',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500))
              else if (updated != null)
                Text(
                  formatLastUpdated(updated),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
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
            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _showRadiusPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Candy.raspberry.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Candy.raspberry.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.near_me, size: 13, color: Candy.raspberry),
                  const SizedBox(width: 5),
                  Text(
                    'Within $_radiusMi mi',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Candy.raspberry,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(Icons.arrow_drop_down, size: 16, color: Candy.raspberry),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _kCategories.length,
        itemBuilder: (context, i) {
          final cat = _kCategories[i];
          final selected = cat == _selectedCategory;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: ChoiceChip(
              label: Text(cat),
              selected: selected,
              onSelected: (_) => setState(() {
                _selectedCategory = cat;
                _showAll = false;
              }),
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? Colors.white : Colors.black87,
              ),
              selectedColor: Candy.raspberry,
              backgroundColor: Colors.grey.shade100,
              side: BorderSide.none,
              shape: const StadiumBorder(),
              showCheckmark: false,
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(List<Promotion> display, List<Promotion> all) {
    if (widget.locating) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Finding your location…', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    if (widget.position == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('Location permission required',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
            const SizedBox(height: 6),
            Text(
              'Allow location access in Settings\nto see deals near you.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (display.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No deals within $_radiusMi mi',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
            if (_radiusMi < 25) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.zoom_out_map, size: 16),
                label: const Text('Expand Radius'),
                onPressed: _showRadiusPicker,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Candy.raspberry,
                  side: const BorderSide(color: Candy.raspberry),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final isCurated = _query.isEmpty && !_showAll;
    final showSeeAll = isCurated && display.length < all.length;
    final items = groupGroceryDeals(display);

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: items.length + 1 + (showSeeAll ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == 0) {
            final label = isCurated
                ? '${display.length} of ${all.length} deals within $_radiusMi mi'
                : '${display.length} deal${display.length == 1 ? '' : 's'} within $_radiusMi mi';
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
            );
          }
          if (showSeeAll && i == items.length + 1) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: OutlinedButton(
                onPressed: () => setState(() => _showAll = true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Candy.raspberry,
                  side: const BorderSide(color: Candy.raspberry),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('See all ${all.length} deals'),
              ),
            );
          }
          final item = items[i - 1];
          if (item is GroceryGroup) {
            return GroceryGroupCard(promos: item.items, memberships: widget.memberships);
          }
          final promo = item as Promotion;
          return DealCard(
            promo: promo,
            memberships: widget.memberships,
            onTap: () {
              _svc.recordClick(promo.id);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DealDetailScreen(promo: promo)),
              ).then((_) { if (mounted) setState(() {}); });
            },
          );
        },
      ),
    );
  }
}
