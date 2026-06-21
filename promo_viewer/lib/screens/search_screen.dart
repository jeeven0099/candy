import 'package:flutter/material.dart';
import '../models/promotion.dart';
import '../services/interaction_service.dart';
import '../theme/candy_colors.dart';
import '../utils/format_utils.dart';
import '../utils/search_utils.dart';
import '../widgets/brand_result_card.dart';

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
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<BrandGroup> get _results => runSearch(widget.all, _query);

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      backgroundColor: Candy.cream,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Expanded(child: _buildBody(results)),
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

  Widget _buildBody(List<BrandGroup> results) {
    if (_query.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Search for a brand or deal',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Try "Chick-fil-A", "free", or "coffee"',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (results.isEmpty) {
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
          ],
        ),
      );
    }

    // Record brand-level searches so affinity boosts work in the curated feeds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final svc = InteractionService();
      for (final g in results) {
        if (g.bestTier <= 4) svc.recordBrandSearch(g.brand);
      }
    });

    final totalDeals = results.fold(0, (sum, g) => sum + g.deals.length);
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        itemCount: results.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                '${results.length} brand${results.length == 1 ? '' : 's'} · $totalDeals deal${totalDeals == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }
          return BrandResultCard(
            group: results[i - 1],
            memberships: widget.memberships,
          );
        },
      ),
    );
  }
}
