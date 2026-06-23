import 'package:flutter/material.dart';

import '../models/promotion.dart';
import '../services/saved_deals_service.dart';
import '../theme/candy_colors.dart';
import '../widgets/deal_card.dart';
import 'deal_detail_screen.dart';

class SavedScreen extends StatelessWidget {
  final List<Promotion> all;
  final Set<String> memberships;
  final Future<void> Function() onRefresh;

  const SavedScreen({
    super.key,
    required this.all,
    required this.onRefresh,
    this.memberships = const {},
  });

  @override
  Widget build(BuildContext context) {
    final svc = SavedDealsService();
    return ListenableBuilder(
      listenable: svc,
      builder: (ctx, _) => _SavedBody(
        all: all,
        memberships: memberships,
        svc: svc,
        onRefresh: onRefresh,
      ),
    );
  }
}

class _SavedBody extends StatelessWidget {
  final List<Promotion> all;
  final Set<String> memberships;
  final SavedDealsService svc;
  final Future<void> Function() onRefresh;

  const _SavedBody({
    required this.all,
    required this.memberships,
    required this.svc,
    required this.onRefresh,
  });

  List<Promotion> get _savedDeals {
    final ids = svc.all.map((d) => d.id).toSet();
    final map  = {for (final p in all) p.id: p};
    return svc.all
        .where((d) => ids.contains(d.id) && map.containsKey(d.id))
        .map((d) => map[d.id]!)
        .toList();
  }

  List<Promotion> get _expiringSoon {
    final now    = DateTime.now();
    final cutoff = now.add(const Duration(days: 7));
    return _savedDeals.where((p) {
      if (p.endDate == null) return false;
      try {
        final end = DateTime.parse(p.endDate!);
        return end.isAfter(now) && end.isBefore(cutoff);
      } catch (_) { return false; }
    }).toList()
      ..sort((a, b) => DateTime.parse(a.endDate!).compareTo(DateTime.parse(b.endDate!)));
  }

  List<Promotion> get _privateDeals {
    return all.where((p) {
      if (p.source != 'email' || !p.isActive) return false;
      final brand = p.brand.toLowerCase();
      if (brand.contains('talent acquisition') || brand.contains(' from ')) return false;
      return p.confidenceScore >= 0.6;
    }).toList()
      ..sort((a, b) => b.rankBaseScore.compareTo(a.rankBaseScore));
  }

  @override
  Widget build(BuildContext context) {
    final saved   = _savedDeals;
    final expiring = _expiringSoon;
    final private = _privateDeals;

    return Scaffold(
      backgroundColor: Candy.cream,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: onRefresh,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              // Expiring soon banner
              if (expiring.isNotEmpty) ...[
                _sectionHeader(context, Icons.timer_outlined, 'Expiring Soon',
                    '${expiring.length} deal${expiring.length == 1 ? '' : 's'} ending in 7 days',
                    color: Candy.raspberry),
                _dealSliver(context, expiring),
              ],
              // Saved deals
              _sectionHeader(context, Icons.favorite, 'Saved',
                  saved.isEmpty ? 'Tap ♡ on any deal to save it' : '${saved.length} saved'),
              if (saved.isEmpty)
                SliverToBoxAdapter(child: _emptyState(
                  icon: Icons.favorite_border,
                  title: 'Nothing saved yet',
                  subtitle: 'Tap ♡ on any deal to save it here',
                ))
              else
                _dealSliverWithReminder(context, saved),
              // Private/email deals
              _sectionHeader(context, Icons.mark_email_unread_outlined, 'Private Deals',
                  'Deals from your inbox'),
              if (private.isEmpty)
                SliverToBoxAdapter(child: _emptyState(
                  icon: Icons.inbox_outlined,
                  title: 'No private deals yet',
                  subtitle: 'Deals emailed to you will appear here',
                ))
              else
                _dealSliver(context, private),
              const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        'Saved',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: Candy.chocolate,
        ),
      ),
    );
  }

  SliverToBoxAdapter _sectionHeader(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle, {
    Color color = Candy.chocolate,
  }) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(width: 8),
            Text(subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  SliverList _dealSliver(BuildContext context, List<Promotion> promos) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (_, i) => DealCard(
          promo: promos[i],
          memberships: memberships,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => DealDetailScreen(promo: promos[i]))),
        ),
        childCount: promos.length,
      ),
    );
  }

  SliverList _dealSliverWithReminder(BuildContext context, List<Promotion> promos) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (_, i) {
          final p      = promos[i];
          final saved  = svc.get(p.id);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DealCard(
                promo: p,
                memberships: memberships,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => DealDetailScreen(promo: p))),
              ),
              if (saved?.remindAt != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 16, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_outlined,
                          size: 12, color: Candy.lavender),
                      const SizedBox(width: 4),
                      Text(
                        'Reminder ${_formatRemindAt(saved!.remindAt!)}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Candy.lavender,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
        childCount: promos.length,
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  String _formatRemindAt(DateTime dt) {
    final diff = dt.difference(DateTime.now()).inDays;
    if (diff < 0)  return '(passed)';
    if (diff == 0) return 'today';
    if (diff == 1) return 'tomorrow';
    return 'in $diff days';
  }
}
