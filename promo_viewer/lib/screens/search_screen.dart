import 'package:flutter/material.dart';
import '../models/promotion.dart';
import '../services/interaction_service.dart';
import '../theme/candy_colors.dart';
import '../utils/format_utils.dart';
import '../utils/search_utils.dart';
import '../widgets/brand_result_card.dart';

// Tappable suggestion chips shown before the user types anything.
const _popularSearches = ['burgers', 'coffee', 'pizza', 'jeans', 'shoes', 'makeup', 'sneakers', 'smoothies'];
const _popularBrands   = ["Starbucks", "Nike", "Chick-fil-A", "Chipotle", "Coach", "Dunkin", "Target", "Sephora"];
const _nearbySearches  = ['coffee near me', 'lunch near me', 'grocery near me', 'deals near me'];

const _filterLabels = ['All', 'Near Me', 'Online', 'Rewards', 'Free/BOGO'];

class SearchScreen extends StatefulWidget {
  final List<Promotion> all;
  final Set<String> memberships;
  final DateTime? lastUpdated;
  final Future<void> Function() onRefresh;

  const SearchScreen({
    super.key,
    required this.all,
    required this.onRefresh,
    this.memberships = const {},
    this.lastUpdated,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _query = '';
  String _activeFilter = 'All';
  final _controller = TextEditingController();

  // Debounce search tracking — fire once per query, not per keystroke.
  String _lastTrackedQuery = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<BrandGroup> get _rawResults => runSearch(widget.all, _query);

  List<BrandGroup> _applyFilter(List<BrandGroup> groups) {
    switch (_activeFilter) {
      case 'Near Me':
        return groups.where((g) => g.contexts.contains('Near Me')).toList();
      case 'Online':
        return groups.where((g) => g.contexts.contains('Online')).toList();
      case 'Rewards':
        return groups.where((g) => g.contexts.contains('Rewards')).toList();
      case 'Free/BOGO':
        return groups.where((g) => g.deals.any((d) =>
            d.discountType == 'free_item' || d.promotionType == 'bogo')).toList();
      default:
        return groups;
    }
  }

  void _setQuery(String q) {
    _controller.text = q;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: q.length),
    );
    setState(() {
      _query = q;
      _activeFilter = 'All';
    });
  }

  void _trackSearch(List<BrandGroup> results) {
    if (_query == _lastTrackedQuery) return;
    _lastTrackedQuery = _query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final svc = InteractionService();
      svc.recordSearch(_query, results.length);
      for (final g in results) {
        if (g.bestTier <= 4) svc.recordBrandSearch(g.brand);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final raw     = _query.trim().isEmpty ? <BrandGroup>[] : _rawResults;
    final results = _applyFilter(raw);
    if (_query.trim().isNotEmpty) _trackSearch(raw);

    return Scaffold(
      backgroundColor: Candy.cream,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Expanded(child: _buildBody(raw, results)),
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
              const Icon(Icons.search, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Search',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: Candy.chocolate,
                      ),
                    ),
                    Text(
                      'All brands & deals',
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
            controller: _controller,
            hintText: 'Search brands, deals, codes…',
            leading: const Icon(Icons.search, size: 20),
            trailing: [
              if (_query.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _controller.clear();
                    setState(() {
                      _query = '';
                      _activeFilter = 'All';
                    });
                  },
                ),
            ],
            onChanged: (v) => setState(() {
              _query = v;
              _activeFilter = 'All';
            }),
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

  Widget _buildBody(List<BrandGroup> raw, List<BrandGroup> results) {
    if (_query.trim().isEmpty) return _buildSuggestions();
    if (raw.isEmpty)           return _buildNoResults();
    return _buildResults(raw, results);
  }

  // ── Empty-state suggestions ───────────────────────────────────────────────

  Widget _buildSuggestions() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        _SuggestionSection(
          label: 'Popular searches',
          chips: _popularSearches,
          onTap: _setQuery,
        ),
        const SizedBox(height: 20),
        _SuggestionSection(
          label: 'Popular brands',
          chips: _popularBrands,
          onTap: _setQuery,
        ),
        const SizedBox(height: 20),
        _SuggestionSection(
          label: 'Try nearby',
          chips: _nearbySearches,
          icon: Icons.near_me,
          onTap: _setQuery,
        ),
      ],
    );
  }

  // ── No results ────────────────────────────────────────────────────────────

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'No results for "$_query"',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Try a brand name, item type, or category',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final s in ['coffee', 'jeans', 'pizza', 'shoes'])
                ActionChip(
                  label: Text(s),
                  onPressed: () => _setQuery(s),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: Colors.grey.shade300),
                  labelStyle: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Results with filter chips ─────────────────────────────────────────────

  Widget _buildResults(List<BrandGroup> raw, List<BrandGroup> filtered) {
    final totalDeals = filtered.fold(0, (sum, g) => sum + g.deals.length);

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 0, bottom: 24),
        // +2: filter chips row + count/empty row
        itemCount: filtered.isEmpty ? 3 : filtered.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) return _buildFilterChips(raw);
          if (i == 1) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                _activeFilter == 'All'
                    ? '${raw.length} brand${raw.length == 1 ? '' : 's'} · $totalDeals deal${totalDeals == 1 ? '' : 's'}'
                    : '${filtered.length} brand${filtered.length == 1 ? '' : 's'} · $totalDeals deal${totalDeals == 1 ? '' : 's'} · $_activeFilter',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }
          if (filtered.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No $_activeFilter deals found',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                ),
              ),
            );
          }
          return BrandResultCard(
            group: filtered[i - 2],
            memberships: widget.memberships,
          );
        },
      ),
    );
  }

  Widget _buildFilterChips(List<BrandGroup> raw) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _filterLabels.length,
        itemBuilder: (context, i) {
          final label    = _filterLabels[i];
          final selected = label == _activeFilter;
          // Count how many brand groups pass this filter for the badge
          int count = 0;
          if (label != 'All') {
            count = _applyFilterForLabel(raw, label).length;
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: ChoiceChip(
              label: Text(
                label == 'All' ? label : (count > 0 ? '$label ($count)' : label),
              ),
              selected: selected,
              onSelected: (_) => setState(() => _activeFilter = label),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? Colors.white : Colors.black87,
              ),
              selectedColor: Candy.raspberry,
              backgroundColor: Colors.white,
              side: BorderSide(
                color: selected ? Candy.raspberry : Colors.grey.shade300,
              ),
              shape: const StadiumBorder(),
              showCheckmark: false,
            ),
          );
        },
      ),
    );
  }

  List<BrandGroup> _applyFilterForLabel(List<BrandGroup> groups, String label) {
    switch (label) {
      case 'Near Me':
        return groups.where((g) => g.contexts.contains('Near Me')).toList();
      case 'Online':
        return groups.where((g) => g.contexts.contains('Online')).toList();
      case 'Rewards':
        return groups.where((g) => g.contexts.contains('Rewards')).toList();
      case 'Free/BOGO':
        return groups.where((g) => g.deals.any((d) =>
            d.discountType == 'free_item' || d.promotionType == 'bogo')).toList();
      default:
        return groups;
    }
  }
}

// ── Suggestion section widget ─────────────────────────────────────────────────

class _SuggestionSection extends StatelessWidget {
  final String label;
  final List<String> chips;
  final IconData? icon;
  final ValueChanged<String> onTap;

  const _SuggestionSection({
    required this.label,
    required this.chips,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Candy.chocolate,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: chips.map((s) {
            return ActionChip(
              avatar: icon != null
                  ? Icon(icon, size: 14, color: Candy.lavender)
                  : null,
              label: Text(s),
              onPressed: () => onTap(s),
              backgroundColor: Colors.white,
              side: BorderSide(color: Candy.pink.withValues(alpha: 0.25)),
              labelStyle: const TextStyle(fontSize: 13, color: Candy.chocolate),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            );
          }).toList(),
        ),
      ],
    );
  }
}
