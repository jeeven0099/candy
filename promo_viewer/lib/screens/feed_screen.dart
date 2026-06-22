import 'package:flutter/material.dart';
import '../models/promotion.dart';
import '../services/location_service.dart';
import '../services/promotions_service.dart';
import '../widgets/deal_card.dart';
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

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

enum _SortMode { relevance, bestDeals, nearMe }

class _FeedScreenState extends State<FeedScreen> {
  List<Promotion> _all = [];
  List<Promotion> _filtered = [];
  bool _loading = true;
  bool _locating = false;
  String _selectedCategory = 'All';
  String _query = '';
  bool _activeOnly = true;
  _SortMode _sortMode = _SortMode.relevance;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final promos = await PromotionsService.load();
    promos.sort((a, b) => b.confidenceScore.compareTo(a.confidenceScore));
    setState(() {
      _all = promos;
      _loading = false;
      _applyFilters();
    });
  }

  Future<void> _enableNearMe() async {
    if (_sortMode == _SortMode.nearMe) {
      setState(() {
        _sortMode = _SortMode.relevance;
        _applyFilters();
      });
      return;
    }
    setState(() => _locating = true);
    final position = await LocationService.getPosition();
    if (position == null) {
      setState(() => _locating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );
      }
      return;
    }
    await LocationService.attachDistances(_all, position);
    setState(() {
      _locating = false;
      _sortMode = _SortMode.nearMe;
      _applyFilters();
    });
  }

  void _applyFilters() {
    final cats = _selectedCategory == 'All'
        ? null
        : _categoryMap[_selectedCategory];
    final q = _query.toLowerCase();

    var result = _all.where((p) {
      if (_activeOnly && !p.isActive) return false;
      if (!p.isValidToday) return false;
      if (p.discountType == 'unknown') return false;
      if (cats != null && !cats.contains(p.category.toLowerCase())) {
        return false;
      }
      if (q.isNotEmpty &&
          !p.brand.toLowerCase().contains(q) &&
          !p.title.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();

    if (_sortMode == _SortMode.bestDeals) {
      result.sort((a, b) => b.dealScore.compareTo(a.dealScore));
    } else if (_sortMode == _SortMode.nearMe) {
      result.sort((a, b) {
        final da = a.distanceKm ?? double.infinity;
        final db = b.distanceKm ?? double.infinity;
        return da.compareTo(db);
      });
    }

    setState(() => _filtered = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildCategoryChips(),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Deals',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              _SortButton(
                label: 'Best deals',
                icon: Icons.star_outline,
                active: _sortMode == _SortMode.bestDeals,
                onTap: () => setState(() {
                  _sortMode = _sortMode == _SortMode.bestDeals
                      ? _SortMode.relevance
                      : _SortMode.bestDeals;
                  _applyFilters();
                }),
              ),
              const SizedBox(width: 6),
              _NearMeButton(
                active: _sortMode == _SortMode.nearMe,
                loading: _locating,
                onTap: _enableNearMe,
              ),
              const SizedBox(width: 8),
              _ActiveToggle(
                value: _activeOnly,
                onChanged: (v) {
                  _activeOnly = v;
                  _applyFilters();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          SearchBar(
            controller: _searchController,
            hintText: 'Search brands or deals...',
            leading: const Icon(Icons.search, size: 20),
            trailing: [
              if (_query.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _query = '';
                    _applyFilters();
                  },
                ),
            ],
            onChanged: (v) {
              _query = v;
              _applyFilters();
            },
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: WidgetStatePropertyAll(Colors.grey.shade100),
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
              onSelected: (_) {
                _selectedCategory = cat;
                _applyFilters();
              },
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? Colors.white : Colors.black87,
              ),
              selectedColor: Colors.black87,
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

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_offer_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'No deals found',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: _filtered.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '${_filtered.length} deals',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }
          final promo = _filtered[i - 1];
          return DealCard(
            promo: promo,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DealDetailScreen(promo: promo),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _SortButton({required this.label, required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2E7D32) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: active ? Colors.white : Colors.black54),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NearMeButton extends StatelessWidget {
  final bool active;
  final bool loading;
  final VoidCallback onTap;
  const _NearMeButton({required this.active, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1565C0) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: active ? Colors.white : Colors.black54,
                ),
              )
            else
              Icon(
                Icons.near_me,
                size: 13,
                color: active ? Colors.white : Colors.black54,
              ),
            const SizedBox(width: 5),
            Text(
              'Near me',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ActiveToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: value ? Colors.black87 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'Active only',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: value ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }
}
