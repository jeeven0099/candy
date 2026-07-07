import 'dart:async';

import 'package:flutter/material.dart';
import '../models/promotion.dart';
import '../services/category_prefs_service.dart';
import '../services/interaction_service.dart';
import '../theme/candy_colors.dart';
import '../utils/deal_grouper.dart';
import '../utils/feed_ranker.dart';
import '../utils/format_utils.dart';
import '../widgets/deal_card.dart';
import '../widgets/grocery_group_card.dart';
import 'deal_detail_screen.dart';

const _categoryMap = {
  'Food':       ['food', 'fast_food', 'restaurant'],
  'Coffee':     ['coffee'],
  'Retail':     ['retail'],
  'Fashion':    ['fashion', 'clothing', 'apparel'],
  'Beauty':     ['beauty', 'personal_care'],
  'Tech':       ['tech', 'electronics'],
  'Home':       ['home', 'home_goods', 'furniture'],
  'Travel':     ['travel', 'hotels', 'airlines'],
  'Automotive': ['automotive', 'gas'],
  'Grocery':    ['grocery', 'supermarket'],
};

class OnlineScreen extends StatefulWidget {
  final List<Promotion> all;
  final Set<String> memberships;
  final DateTime? lastUpdated;
  final Future<void> Function() onRefresh;

  const OnlineScreen({
    super.key,
    required this.all,
    required this.onRefresh,
    this.memberships = const {},
    this.lastUpdated,
  });

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  String _query = '';
  String _selectedCategory = 'All';
  bool _showAll = false;
  final _searchController = TextEditingController();
  final _svc = InteractionService();
  final _catSvc = CategoryPrefsService();
  final _markedSeen = <String>{};
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
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
    if (p.discountType == 'unknown') return false;
    if (p.discountType == 'points') return false;
    if (p.discountType == 'free_shipping') return false;
    if (p.requiresMembership) {
      final cost = (p.membershipCost ?? '').toLowerCase();
      if (cost.contains('paid') && !_hasMembership(p)) return false;
    }
    return p.rankScore(isMember: _hasMembership(p)) >= 65;
  }

  double _boostedScore(Promotion p) =>
      p.rankScore(isMember: _hasMembership(p)) + _catSvc.affinityBoost(p.category);

  List<Promotion> get _filtered {
    final cats = _selectedCategory == 'All' ? null : _categoryMap[_selectedCategory];
    final q = _query.toLowerCase();

    return widget.all.where((p) {
      if (!p.isActive) return false;
      if (!p.isValidToday) return false;
      if (p.promotionType == 'reward' || p.promotionType == 'membership_benefit') return false;
      final isOnline = p.redemptionMethod == 'online' ||
          (p.redemptionMethod == 'show_code' && p.dealScope == 'online_only');
      if (!isOnline) return false;
      if (p.isLocal) return false;
      if (cats != null && !cats.contains(p.category.toLowerCase())) return false;
      if (q.isNotEmpty &&
          !p.brand.toLowerCase().contains(q) &&
          !p.title.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => _boostedScore(b).compareTo(_boostedScore(a)));
  }

  List<Promotion> _toDisplay(List<Promotion> base) {
    if (_query.isNotEmpty || _showAll) return base;
    final quality = base.where(_isQualityDeal).toList();
    return selectTopDeals(quality, _svc, getIsMember: _hasMembership);
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

  void _onQueryChanged(String v) {
    setState(() {
      _query = v;
      _showAll = false;
    });
    _searchDebounce?.cancel();
    if (v.trim().length >= 3) {
      _searchDebounce = Timer(const Duration(milliseconds: 1200), () {
        _inferAndRecordCategory(v.trim());
      });
    }
  }

  void _inferAndRecordCategory(String query) {
    // Keyword match first — works even before results are visible
    final keyword = _catSvc.resolveQueryToCategory(query);
    if (keyword != null) {
      _catSvc.recordCategoryInterest(keyword, weight: 2).then((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    // Fall back to dominant category of current results
    final results = _filtered;
    if (results.isEmpty) return;
    final counts = <String, int>{};
    for (final p in results.take(10)) {
      counts[p.category] = (counts[p.category] ?? 0) + 1;
    }
    final top = counts.entries.reduce((a, b) => a.value > b.value ? a : b);
    if (top.value / results.take(10).length >= 0.5) {
      final label = _catSvc.rawCategoryToLabel(top.key);
      if (label != null) {
        _catSvc.recordCategoryInterest(label, weight: 2).then((_) {
          if (mounted) setState(() {});
        });
      }
    }
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
              const Icon(Icons.laptop, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Online',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: Candy.chocolate,
                      ),
                    ),
                    Text(
                      'Online treats',
                      style: TextStyle(
                        fontSize: 12,
                        color: Candy.lavender,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (updated != null)
                Text(
                  formatLastUpdated(updated),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SearchBar(
            controller: _searchController,
            hintText: 'Search online deals…',
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
            onChanged: _onQueryChanged,
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: const WidgetStatePropertyAll(Colors.white),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    final categories = _catSvc.getOrderedCategories();
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: categories.length,
        itemBuilder: (context, i) {
          final cat = categories[i];
          final selected = cat == _selectedCategory;
          final isPromoted = cat != 'All' && _catSvc.isPromoted(cat);
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
                color: selected
                    ? Colors.white
                    : isPromoted
                        ? Candy.raspberry
                        : Colors.black87,
              ),
              selectedColor: Candy.raspberry,
              backgroundColor: isPromoted
                  ? Candy.raspberry.withValues(alpha: 0.08)
                  : Colors.grey.shade100,
              side: isPromoted && !selected
                  ? BorderSide(color: Candy.raspberry.withValues(alpha: 0.3))
                  : BorderSide.none,
              shape: const StadiumBorder(),
              showCheckmark: false,
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(List<Promotion> display, List<Promotion> all) {
    if (display.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.laptop_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No online deals found',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
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
                ? '${display.length} of ${all.length} deals'
                : '${display.length} deal${display.length == 1 ? '' : 's'}';
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
              _svc.recordClick(promo.id, brand: promo.brand, category: promo.category);
              // Bump local category affinity on deal click
              final label = _catSvc.rawCategoryToLabel(promo.category);
              if (label != null) {
                _catSvc.recordCategoryInterest(label, weight: 1);
              }
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
