import 'package:flutter/material.dart';
import '../models/promotion.dart';
import '../theme/candy_colors.dart';
import '../utils/deal_grouper.dart';
import '../widgets/deal_card.dart';
import '../widgets/grocery_group_card.dart';
import 'deal_detail_screen.dart';

const _categories = [
  'All', 'Food', 'Coffee', 'Retail', 'Fashion', 'Beauty',
  'Tech', 'Home', 'Travel', 'Automotive', 'Grocery',
];

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
  const OnlineScreen({super.key, required this.all, this.memberships = const {}});

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  String _query = '';
  String _selectedCategory = 'All';
  final _searchController = TextEditingController();

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

  List<Promotion> get _filtered {
    final cats = _selectedCategory == 'All' ? null : _categoryMap[_selectedCategory];
    final q = _query.toLowerCase();

    return widget.all.where((p) {
      if (!p.isActive) return false;
      // Rewards programs belong in the Rewards tab
      if (p.promotionType == 'reward' || p.promotionType == 'membership_benefit') return false;
      // Online tab: online redemption, or show_code with online_only scope
      final isOnline = p.redemptionMethod == 'online' ||
          (p.redemptionMethod == 'show_code' && p.dealScope == 'online_only');
      if (!isOnline) return false;
      // Email-only deals are private (from personal inbox) — belong in For You only.
      // source='both' means the deal also exists on the public web, so it stays.
      if (p.source == 'email') return false;
      if (cats != null && !cats.contains(p.category.toLowerCase())) return false;
      if (q.isNotEmpty &&
          !p.brand.toLowerCase().contains(q) &&
          !p.title.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.rankScore(isMember: _hasMembership(b))
            .compareTo(a.rankScore(isMember: _hasMembership(a))));
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
            _buildCategoryChips(),
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
          const Row(
            children: [
              Icon(Icons.laptop, size: 22),
              SizedBox(width: 8),
              Column(
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

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _categories.length,
        itemBuilder: (context, i) {
          final cat = _categories[i];
          final selected = cat == _selectedCategory;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: ChoiceChip(
              label: Text(cat),
              selected: selected,
              onSelected: (_) => setState(() => _selectedCategory = cat),
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

  Widget _buildBody(List<Promotion> promos) {
    if (promos.isEmpty) {
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

    final items = groupGroceryDeals(promos);
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: items.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '${promos.length} deals',
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
            MaterialPageRoute(builder: (_) => DealDetailScreen(promo: promo)),
          ),
        );
      },
    );
  }
}
