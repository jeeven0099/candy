import 'dart:async';

import 'package:flutter/material.dart';

import '../models/promotion.dart';
import '../services/interaction_service.dart';
import '../services/supabase_service.dart';
import '../services/user_prefs_service.dart';
import '../theme/candy_colors.dart';
import '../utils/feed_ranker.dart';
import '../utils/ranking_contract.dart';
import '../widgets/deal_card.dart';
import '../widgets/deal_impression_tracker.dart';
import 'deal_detail_screen.dart';

class ForYouScreen extends StatefulWidget {
  final List<Promotion> all;
  final Set<String> memberships;
  final bool active;
  final Future<void> Function() onRefresh;

  const ForYouScreen({
    super.key,
    required this.all,
    required this.onRefresh,
    this.memberships = const {},
    this.active = true,
  });

  @override
  State<ForYouScreen> createState() => _ForYouScreenState();
}

class _ForYouScreenState extends State<ForYouScreen> {
  final _svc = InteractionService();
  String _lastRecordedKey = '';

  bool _hasMembership(Promotion p) {
    if (widget.memberships.isEmpty) return false;
    final brand = p.brand.toLowerCase();
    final memberName = (p.membershipName ?? '').toLowerCase();
    return widget.memberships.any(
      (m) =>
          m.contains(brand) ||
          brand.contains(m) ||
          (memberName.isNotEmpty &&
              (m.contains(memberName) || memberName.contains(m))),
    );
  }

  void _recordVisible(List<Promotion> deals) {
    final ids = deals.map((p) => p.id).toList()..sort();
    if (ids.isEmpty) return;
    final key = ids.join(',');
    if (key == _lastRecordedKey) return;
    _lastRecordedKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _svc.recordSeen(ids);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserPrefsService(),
      builder: (context, _) {
        final prefs = UserPrefsService().prefs;
        final deals = selectTopDeals(
          widget.all,
          _svc,
          getIsMember: _hasMembership,
          prefs: prefs,
          limit: RankingContract.forYouLimit,
        );
        _recordVisible(deals);

        return Scaffold(
          backgroundColor: Candy.cream,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: CustomScrollView(
                slivers: [
                  const SliverToBoxAdapter(child: _ForYouHeader()),
                  if (deals.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _emptyState(),
                    )
                  else ...[
                    SliverToBoxAdapter(child: _countLabel(deals.length)),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) =>
                            _dealCard(context, deals[index], index + 1),
                        childCount: deals.length,
                      ),
                    ),
                    const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _countLabel(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(
        '$count best deals',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Candy.chocolate.withValues(alpha: 0.45),
        ),
      ),
    );
  }

  Widget _dealCard(BuildContext context, Promotion promo, int position) {
    final score = dealQualityScore(
      promo,
      _svc,
      isMember: _hasMembership(promo),
      prefs: UserPrefsService().prefs,
    );
    Future<bool> recordImpression() => _svc.recordFeedImpression(
      promo,
      rankingMode: 'for_you',
      feedPosition: position,
      runtimeScore: score,
    );
    return DealImpressionTracker(
      trackingKey:
          '${SupabaseService.currentUserId}|for_you|${promo.source}|${promo.id}',
      active: widget.active,
      onImpression: recordImpression,
      child: DealCard(
        promo: promo,
        onInteraction: () => unawaited(recordImpression()),
        memberships: widget.memberships,
        feedPosition: position,
        rankingMode: 'for_you',
        onTap: () async {
          _svc.recordClick(
            promo.id,
            brand: promo.brand,
            category: promo.category,
            meta: InteractionService.promoMeta(
              promo,
              rankingMode: 'for_you',
              feedPosition: position,
              runtimeScore: score,
            ),
          );
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DealDetailScreen(
                promo: promo,
                rankingMode: 'for_you',
                feedPosition: position,
              ),
            ),
          );
          if (mounted) setState(() => _lastRecordedKey = '');
        },
      ),
    );
  }

  Widget _emptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.auto_awesome_outlined,
          size: 52,
          color: Colors.grey.shade300,
        ),
        const SizedBox(height: 16),
        Text(
          'No high-quality deals right now',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
          ),
        ),
      ],
    );
  }
}

class _ForYouHeader extends StatelessWidget {
  const _ForYouHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 22, 16, 10),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 23, color: Candy.raspberry),
          SizedBox(width: 9),
          Text(
            'For You',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: Candy.chocolate,
            ),
          ),
        ],
      ),
    );
  }
}
