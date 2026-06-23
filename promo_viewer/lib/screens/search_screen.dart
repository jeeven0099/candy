import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/promotion.dart';
import '../services/interaction_service.dart';
import '../services/location_service.dart';
import '../services/saved_deals_service.dart';
import '../theme/candy_colors.dart';
import '../utils/feed_ranker.dart';
import '../utils/format_utils.dart';
import '../utils/search_utils.dart';
import '../widgets/brand_result_card.dart';

// ── Suggestion constants ──────────────────────────────────────────────────────

const _kPopularSearches = [
  'burgers', 'coffee', 'jeans', 'handbags', 'pizza',
  'groceries', 'makeup', 'shoes',
];
const _kPopularBrands = [
  'Target', 'Starbucks', 'Nike', 'Coach', 'Kroger', 'Chipotle',
];
const _kNearbySearches = [
  'lunch near me', 'coffee near me', 'grocery deals', 'burgers near me',
];

// ── Context chip definitions ───────────────────────────────────────────────────

class _ContextChip {
  final SearchContext ctx;
  final String label;
  final IconData icon;
  const _ContextChip(this.ctx, this.label, this.icon);
}

const _kChips = [
  _ContextChip(SearchContext.forYou,   'For You',   Icons.auto_awesome),
  _ContextChip(SearchContext.nearMe,   'Near Me',   Icons.near_me),
  _ContextChip(SearchContext.online,   'Online',    Icons.language),
  _ContextChip(SearchContext.rewards,  'Rewards',   Icons.card_membership),
  _ContextChip(SearchContext.freeBogo, 'Free/BOGO', Icons.redeem),
  _ContextChip(SearchContext.saved,    'Saved',     Icons.favorite),
];

// ─────────────────────────────────────────────────────────────────────────────

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
  final _controller  = TextEditingController();
  final _svc         = InteractionService();

  String _query         = '';        // live text (controls TextField)
  String _debouncedQ    = '';        // settled query used for actual search
  String _lastTrackedQ  = '';
  SearchContext _ctx    = SearchContext.forYou;

  Timer?    _debounce;
  Position? _position;
  bool      _locating        = false;
  bool      _locationDenied  = false;

  @override
  void initState() {
    super.initState();
    // If any distances are already attached (from the Near Me tab), reuse them.
    if (widget.all.any((p) => p.distanceKm != null)) _position = const _FakePosition();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // ── Computed props ────────────────────────────────────────────────────────

  Set<String> get _savedIds =>
      Set.from(SavedDealsService().all.map((d) => d.id));

  SearchOptions get _opts => SearchOptions(
    memberships:  widget.memberships,
    savedIds:     _savedIds,
    context:      _ctx,
    minConfidence: 0.5,
  );

  List<BrandGroup> get _results {
    if (_debouncedQ.trim().isEmpty) return [];
    return runSearch(widget.all, _debouncedQ, _opts);
  }

  List<BrandGroup> get _contextDeals {
    if (_ctx == SearchContext.forYou) return [];
    final scorer = _ctx == SearchContext.nearMe
        ? _nearMeScorer
        : _ctx == SearchContext.forYou
            ? _forYouScorer
            : null;
    return getContextDeals(widget.all, _opts, scorer: scorer);
  }

  double _nearMeScorer(Promotion p) {
    if (p.distanceKm == null) return -999;
    final miles = p.distanceKm! * 0.621371;
    final dist = miles <= 0.5 ? 30 : miles <= 1.0 ? 25 : miles <= 2.0 ? 18 : miles <= 5.0 ? 8 : 2;
    return p.rankBaseScore + dist;
  }

  double _forYouScorer(Promotion p) =>
      personalizedScore(p, _svc, distanceKm: p.distanceKm);

  // ── Input handling ────────────────────────────────────────────────────────

  void _onQueryChanged(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _debouncedQ = v);
      if (v.trim().isNotEmpty) _trackSearch(v.trim());
    });
  }

  void _setQuery(String q) {
    _controller.text = q;
    _controller.selection = TextSelection.collapsed(offset: q.length);
    _query = q;
    _debouncedQ = q;
    setState(() {});
    _trackSearch(q);
  }

  void _clearQuery() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _query       = '';
      _debouncedQ  = '';
    });
  }

  // ── Context chip selection ────────────────────────────────────────────────

  Future<void> _selectChip(SearchContext ctx) async {
    if (ctx == SearchContext.nearMe && _position == null && !_locationDenied) {
      await _requestLocation();
      if (_locationDenied) return;
    }
    if (_ctx != ctx) {
      _svc.recordSearchEvent('search_filter_chip_changed', params: {
        'chip': ctx.name,
        'query': _query,
      });
    }
    setState(() => _ctx = ctx);
  }

  Future<void> _requestLocation() async {
    setState(() => _locating = true);
    final pos = await LocationService.getPosition();
    if (pos == null) {
      setState(() { _locating = false; _locationDenied = true; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );
      }
      return;
    }
    await LocationService.attachDistances(widget.all, pos);
    setState(() { _locating = false; _position = pos; });
  }

  // ── Analytics ─────────────────────────────────────────────────────────────

  void _trackSearch(String q) {
    if (q == _lastTrackedQ) return;
    _lastTrackedQ = q;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final results = runSearch(widget.all, q, _opts);
      _svc.recordRecentSearch(q);
      _svc.recordSearch(q, results.length);
      if (results.isEmpty) {
        _svc.recordSearchEvent('search_no_results', params: {
          'query': q,
          'chip': _ctx.name,
        });
      } else {
        _svc.recordSearchEvent('search_submitted', params: {
          'query': q,
          'chip': _ctx.name,
          'result_count': '${results.length}',
        });
        for (final g in results) {
          if (g.bestTier <= 4) _svc.recordBrandSearch(g.brand);
        }
      }
    });
  }

  void _onBrandExpanded(BrandGroup g) {
    _svc.recordSearchEvent('brand_result_opened', params: {
      'brand': g.brand,
      'query': _debouncedQ,
      'chip': _ctx.name,
    });
  }

  void _onDealTap(String dealId, String brand) {
    _svc.recordSearchEvent('search_result_clicked', params: {
      'deal_id': dealId,
      'brand': brand,
      'query': _debouncedQ,
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasQuery = _debouncedQ.trim().isNotEmpty;
    final results  = hasQuery ? _results : <BrandGroup>[];

    return Scaffold(
      backgroundColor: Candy.cream,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildContextChips(),
            const Divider(height: 1),
            Expanded(child: _buildBody(hasQuery, results)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final updated = widget.lastUpdated;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
          const SizedBox(height: 10),
          SearchBar(
            controller: _controller,
            hintText: 'Search brands, deals, codes…',
            leading: const Icon(Icons.search, size: 20),
            trailing: [
              if (_query.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _clearQuery,
                ),
            ],
            onChanged: _onQueryChanged,
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

  Widget _buildContextChips() {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _kChips.length,
        itemBuilder: (context, i) {
          final chip     = _kChips[i];
          final selected = chip.ctx == _ctx;
          final isNearMe = chip.ctx == SearchContext.nearMe && _locating;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: ChoiceChip(
              avatar: isNearMe
                  ? SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: selected ? Colors.white : Candy.raspberry,
                      ),
                    )
                  : Icon(chip.icon, size: 14,
                      color: selected ? Colors.white : Candy.chocolate.withValues(alpha: 0.7)),
              label: Text(chip.label),
              selected: selected,
              onSelected: (_) => _selectChip(chip.ctx),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? Colors.white : Candy.chocolate,
              ),
              selectedColor: Candy.raspberry,
              backgroundColor: Colors.white,
              side: BorderSide(
                color: selected ? Candy.raspberry : Colors.grey.shade300,
              ),
              shape: const StadiumBorder(),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          );
        },
      ),
    );
  }

  // ── Body routing ──────────────────────────────────────────────────────────

  Widget _buildBody(bool hasQuery, List<BrandGroup> results) {
    if (hasQuery) {
      return results.isEmpty
          ? _buildNoResults()
          : _buildSearchResults(results);
    }

    // No query: For You shows suggestions; other chips show filtered deals.
    if (_ctx == SearchContext.forYou) return _buildSuggestions();

    // Near Me without location
    if (_ctx == SearchContext.nearMe && _position == null && !_locating) {
      return _buildLocationPrompt();
    }

    final contextGroups = _contextDeals;
    return contextGroups.isEmpty
        ? _buildContextEmpty()
        : _buildGroupList(contextGroups, isContext: true);
  }

  // ── Suggestion state (ForYou, no query) ──────────────────────────────────

  Widget _buildSuggestions() {
    final recents = _svc.getRecentSearches();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        if (recents.isNotEmpty) ...[
          _SectionHeader(
            label: 'Recent',
            trailing: TextButton(
              onPressed: () async {
                for (final q in recents) {
                  await _svc.clearRecentSearch(q);
                }
                setState(() {});
              },
              child: const Text('Clear', style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: recents.map((q) => _SuggestionChip(
              label: q,
              icon: Icons.history,
              onTap: () => _setQuery(q),
              onDelete: () async {
                await _svc.clearRecentSearch(q);
                setState(() {});
              },
            )).toList(),
          ),
          const SizedBox(height: 20),
        ],
        _SectionHeader(label: 'Popular searches'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _kPopularSearches.map((s) => _SuggestionChip(
            label: s, onTap: () => _setQuery(s),
          )).toList(),
        ),
        const SizedBox(height: 20),
        _SectionHeader(label: 'Popular brands'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _kPopularBrands.map((s) => _SuggestionChip(
            label: s,
            icon: Icons.storefront_outlined,
            onTap: () => _setQuery(s),
          )).toList(),
        ),
        const SizedBox(height: 20),
        _SectionHeader(label: 'Nearby searches'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _kNearbySearches.map((s) => _SuggestionChip(
            label: s,
            icon: Icons.near_me,
            onTap: () => _setQuery(s),
          )).toList(),
        ),
      ],
    );
  }

  // ── No-result state ───────────────────────────────────────────────────────

  Widget _buildNoResults() {
    final related = relatedSearches(_debouncedQ);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'No results for "$_debouncedQ"',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _ctx == SearchContext.nearMe
                  ? 'Try "Online" to see all matching deals'
                  : _ctx == SearchContext.online
                      ? 'Try "Near Me" for in-store options'
                      : 'Try a brand name, item type, or category',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
            if (related.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Related searches',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Candy.chocolate.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8, runSpacing: 8,
                alignment: WrapAlignment.center,
                children: related.map((s) => ActionChip(
                  label: Text(s),
                  onPressed: () => _setQuery(s),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: Colors.grey.shade300),
                  labelStyle: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                )).toList(),
              ),
            ],
            const SizedBox(height: 20),
            // Context switch hints
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_ctx != SearchContext.online)
                  _HintChip(
                    label: 'Try Online',
                    onTap: () => _selectChip(SearchContext.online),
                  ),
                if (_ctx != SearchContext.nearMe) ...[
                  const SizedBox(width: 8),
                  _HintChip(
                    label: 'Try Near Me',
                    onTap: () => _selectChip(SearchContext.nearMe),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Location prompt (Near Me, no position) ────────────────────────────────

  Widget _buildLocationPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text(
              'Enable location for nearby deals',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Candy.chocolate),
            ),
            const SizedBox(height: 6),
            Text(
              'Candy uses your location to show deals at stores near you.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.near_me, size: 16),
              label: const Text('Enable location'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Candy.raspberry,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
              ),
              onPressed: () async {
                setState(() => _locationDenied = false);
                await _requestLocation();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Context empty ─────────────────────────────────────────────────────────

  Widget _buildContextEmpty() {
    final label = _kChips.firstWhere((c) => c.ctx == _ctx).label;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'No $label deals right now',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Try searching for a specific brand or item',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── Grouped result list (shared by search results + context deals) ─────────

  Widget _buildSearchResults(List<BrandGroup> results) {
    final total = results.fold(0, (n, g) => n + g.deals.length);
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        itemCount: results.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                '${results.length} brand${results.length == 1 ? '' : 's'} · $total deal${total == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
              ),
            );
          }
          final g = results[i - 1];
          return BrandResultCard(
            group: g,
            memberships: widget.memberships,
            onExpanded:  () => _onBrandExpanded(g),
            onDealTap:   _onDealTap,
          );
        },
      ),
    );
  }

  Widget _buildGroupList(List<BrandGroup> groups, {required bool isContext}) {
    final chipLabel = _kChips.firstWhere((c) => c.ctx == _ctx).label;
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        itemCount: groups.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Top $chipLabel deals',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
              ),
            );
          }
          final g = groups[i - 1];
          return BrandResultCard(
            group: g,
            memberships: widget.memberships,
            onExpanded:  () => _onBrandExpanded(g),
            onDealTap:   _onDealTap,
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tiny widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final Widget? trailing;
  const _SectionHeader({required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Candy.chocolate,
              letterSpacing: 0.2,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  const _SuggestionChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: icon != null ? Icon(icon, size: 14, color: Candy.lavender) : null,
      label: Text(label),
      onPressed: onTap,
      onDeleted: onDelete,
      deleteIconColor: Colors.grey.shade400,
      backgroundColor: Colors.white,
      side: BorderSide(color: Candy.pink.withValues(alpha: 0.25)),
      labelStyle: const TextStyle(fontSize: 13, color: Candy.chocolate),
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 2),
    );
  }
}

class _HintChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _HintChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: Colors.white,
      side: BorderSide(color: Candy.raspberry.withValues(alpha: 0.4)),
      labelStyle: const TextStyle(fontSize: 13, color: Candy.raspberry, fontWeight: FontWeight.w500),
    );
  }
}

// Marker class so we can check "position already set" without holding
// the real Position object (which geolocator requires platform channels).
class _FakePosition implements Position {
  const _FakePosition();
  @override dynamic noSuchMethod(Invocation i) => null;
}
