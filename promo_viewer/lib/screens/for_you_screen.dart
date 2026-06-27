import 'package:flutter/material.dart';
import '../models/promotion.dart';
import '../services/interaction_service.dart';
import '../services/user_prefs_service.dart';
import '../theme/candy_colors.dart';
import '../utils/feed_ranker.dart';
import '../widgets/deal_card.dart';
import 'deal_detail_screen.dart';

const _kFeedLimit = 30;

class ForYouScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserPrefsService(),
      builder: (ctx, _) {
        final prefs = UserPrefsService().prefs;
        final svc   = InteractionService();
        final isBirthdayMonth = prefs?.birthdayMonth != null &&
            prefs!.birthdayMonth == DateTime.now().month;

        // Birthday deals — highlighted section, only during birthday month
        final bdayDeals = isBirthdayMonth
            ? (all
                .where((p) => p.birthdayRelated && p.isActive)
                .toList()
              ..sort((a, b) => b.globalQualityScore.compareTo(a.globalQualityScore)))
            : <Promotion>[];
        final bdayIds = {for (final p in bdayDeals) p.id};

        // Main personalized feed — birthday deals excluded (shown above)
        final ranked = selectTopDeals(
          all.where((p) => p.isActive && !bdayIds.contains(p.id)).toList(),
          svc,
          prefs: prefs,
          limit: _kFeedLimit,
          maxPerBrand: 2,
        );

        final hasPrefs = prefs != null && !prefs.isEmpty;

        return Scaffold(
          backgroundColor: Candy.cream,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(hasPrefs)),

                  // ── Birthday deals ──────────────────────────────────────
                  if (isBirthdayMonth) ...[
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

                  // ── Personalized feed ───────────────────────────────────
                  if (ranked.isNotEmpty) ...[
                    SliverToBoxAdapter(child: _sectionHeading(
                      icon: hasPrefs ? Icons.auto_awesome : Icons.trending_up,
                      label: hasPrefs ? 'Picked for you' : 'Top deals right now',
                      count: ranked.length,
                    )),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _dealCard(ctx, ranked[i]),
                        childCount: ranked.length,
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
      memberships: memberships,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DealDetailScreen(promo: p)),
      ),
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
