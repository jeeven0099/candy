import 'package:flutter/material.dart';
import '../models/promotion.dart';
import '../services/interaction_service.dart';
import '../services/user_prefs_service.dart';
import '../theme/candy_colors.dart';
import '../utils/feed_ranker.dart';
import '../widgets/deal_card.dart';
import 'deal_detail_screen.dart';

const _kFeedLimit = 30;

const _kCategories = [
  ('All',         null),
  ('Food',        ['food']),
  ('Groceries',   ['groceries', 'pharmacy', 'health']),
  ('Fashion',     ['fashion', 'clothing', 'retail']),
  ('Beauty',      ['beauty', 'Premium Beauty']),
  ('Tech',        ['electronics', 'tech', 'gaming']),
  ('Household',   ['home', 'Premium Appliances', 'pets', 'pet supplies', 'household']),
  ('Travel',      ['travel']),
  ('Fitness',     ['fitness', 'Outdoor / Adventure Gear']),
];

class ForYouScreen extends StatefulWidget {
  final List<Promotion> all;
  final Set<String> memberships;
  final Future<void> Function() onRefresh;

  const ForYouScreen({
    super.key,
    required this.all,
    required this.onRefresh,
    this.memberships = const {},
  });

  @override
  State<ForYouScreen> createState() => _ForYouScreenState();
}

class _ForYouScreenState extends State<ForYouScreen> {
  int _selectedChip = 0;
  String _lastRecordedKey = '';

  bool _isPetBrand(Promotion p) =>
      kPetBrandNames.contains(p.brand.toLowerCase());

  List<Promotion> _applyCategory(List<Promotion> deals) {
    final (name, cats) = _kCategories[_selectedChip];
    if (cats == null) return deals;
    if (name == 'Household') {
      // Include home-category deals AND pet brand deals (scraped as 'food')
      return deals.where((p) =>
          _isPetBrand(p) ||
          cats.any((c) => p.category.toLowerCase() == c.toLowerCase())).toList();
    }
    if (name == 'Food') {
      // Exclude pet brands even though their raw category is 'food'
      return deals.where((p) =>
          !_isPetBrand(p) &&
          cats.any((c) => p.category.toLowerCase() == c.toLowerCase())).toList();
    }
    return deals.where((p) => cats.any((c) =>
        p.category.toLowerCase() == c.toLowerCase())).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserPrefsService(),
      builder: (ctx, _) {
        final prefs = UserPrefsService().prefs;
        final svc   = InteractionService();
        final isBirthdayMonth = prefs?.birthdayMonth != null &&
            prefs!.birthdayMonth == DateTime.now().month;

        final bdayDeals = isBirthdayMonth
            ? (widget.all
                .where((p) => p.birthdayRelated && p.isActive)
                .toList()
              ..sort((a, b) => b.globalQualityScore.compareTo(a.globalQualityScore)))
            : <Promotion>[];
        final bdayIds = {for (final p in bdayDeals) p.id};

        final activeDeals = widget.all
            .where((p) => p.isActive && !bdayIds.contains(p.id))
            .toList();

        // When a specific category chip is selected, filter first so the
        // preference-based ranking operates on that category's full deal pool,
        // not just the top-30 preferred deals (which may not include that category).
        final poolForChip =
            _selectedChip == 0 ? activeDeals : _applyCategory(activeDeals);

        final isHousehold = _kCategories[_selectedChip].$1 == 'Household';
        final ranked = selectTopDeals(
          poolForChip,
          svc,
          prefs: prefs,
          limit: _kFeedLimit,
          maxPerBrand: 2,
          // Allow pet brands through isFeedWorthy when Household chip is active.
          extraFavBrands: isHousehold ? kPetBrandNames : const {},
        );

        // Record deals as seen so fatigue accrues. Use a sorted string key so
        // the comparison is by value, not object identity (Dart Set has no ==).
        final ids = ranked.map((p) => p.id).toList()..sort();
        final visibleKey = ids.join(',');
        debugPrint('[Fatigue] ForYou build: ${ids.length} ranked deals, key changed=${visibleKey != _lastRecordedKey}');
        if (visibleKey != _lastRecordedKey) {
          _lastRecordedKey = visibleKey;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint('[Fatigue] postFrameCallback firing, mounted=$mounted');
            if (mounted) svc.recordSeen(ids);
          });
        }

        final filtered = ranked;
        final hasPrefs = prefs != null && !prefs.isEmpty;

        return Scaffold(
          backgroundColor: Candy.cream,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(hasPrefs)),
                  SliverToBoxAdapter(child: _buildChips()),

                  if (isBirthdayMonth && _selectedChip == 0) ...[
                    SliverToBoxAdapter(child: _sectionHeading(
                      icon: Icons.celebration_outlined,
                      label: 'Birthday Deals',
                      count: bdayDeals.length,
                    )),
                    if (bdayDeals.isEmpty)
                      SliverToBoxAdapter(child: _emptyBirthdayDeals())
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _dealCard(ctx, bdayDeals[i]),
                          childCount: bdayDeals.length,
                        ),
                      ),
                  ],

                  if (filtered.isNotEmpty) ...[
                    SliverToBoxAdapter(child: _sectionHeading(
                      icon: hasPrefs ? Icons.auto_awesome : Icons.trending_up,
                      label: hasPrefs ? 'Picked for you' : 'Top deals right now',
                      count: filtered.length,
                    )),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _dealCard(ctx, filtered[i]),
                        childCount: filtered.length,
                      ),
                    ),
                  ] else if (!isBirthdayMonth)
                    SliverToBoxAdapter(child: _emptyState()),

                  const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(bool hasPrefs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'For You',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: Candy.chocolate,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasPrefs
                ? 'Deals picked from your favourite brands & categories'
                : 'Save brands you love to get a personalised feed',
            style: TextStyle(
              fontSize: 13,
              color: Candy.chocolate.withValues(alpha: 0.45),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: _kCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final selected = i == _selectedChip;
          return GestureDetector(
            onTap: () => setState(() => _selectedChip = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? Candy.raspberry : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? Candy.raspberry : Colors.grey.shade200,
                ),
              ),
              child: Text(
                _kCategories[i].$1,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Candy.chocolate,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sectionHeading({
    required IconData icon,
    required String label,
    required int count,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Candy.raspberry),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Candy.chocolate,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          Text(
            '$count deals',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _dealCard(BuildContext context, Promotion p) {
    return DealCard(
      promo: p,
      memberships: widget.memberships,
      onTap: () async {
        InteractionService().recordClick(
          p.id,
          brand: p.brand,
          category: p.category,
        );
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DealDetailScreen(promo: p)),
        );
        // Reset the seen key so returning to the feed triggers recordSeen again —
        // deals the user just scrolled past after viewing the detail get another
        // impression tick, which is what we want for freshness.
        if (mounted) setState(() => _lastRecordedKey = '');
      },
    );
  }

  Widget _emptyBirthdayDeals() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cake_outlined, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'No birthday deals right now',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Check back — new birthday offers are added regularly.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 52, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No deals available right now',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}
