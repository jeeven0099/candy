import 'package:flutter/material.dart';
import '../models/promotion.dart';
import '../services/user_prefs_service.dart';
import '../theme/candy_colors.dart';
import '../widgets/deal_card.dart';
import 'deal_detail_screen.dart';

const _kMonthNames = [
  '', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

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
        final birthdayMonth = prefs?.birthdayMonth;
        final isBirthdayMonth =
            birthdayMonth != null && birthdayMonth == DateTime.now().month;

        final birthdayDeals = all
            .where((p) => p.birthdayRelated && p.isActive)
            .toList()
          ..sort((a, b) => b.rankBaseScore.compareTo(a.rankBaseScore));

        return Scaffold(
          backgroundColor: Candy.cream,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(isBirthdayMonth)),
                  if (isBirthdayMonth) ...[
                    if (birthdayDeals.isEmpty)
                      SliverToBoxAdapter(child: _emptyBirthdayDeals())
                    else ...[
                      SliverToBoxAdapter(child: _countBar(birthdayDeals.length)),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) {
                            final p = birthdayDeals[i];
                            return DealCard(
                              promo: p,
                              memberships: memberships,
                              onTap: () => Navigator.push(
                                ctx,
                                MaterialPageRoute(
                                    builder: (_) => DealDetailScreen(promo: p)),
                              ),
                            );
                          },
                          childCount: birthdayDeals.length,
                        ),
                      ),
                    ],
                  ] else
                    SliverToBoxAdapter(
                        child: _notBirthdayMonth(birthdayMonth)),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(bool isBirthdayMonth) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isBirthdayMonth ? Icons.cake : Icons.cake_outlined,
            size: 22,
            color: Candy.raspberry,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'For You',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: Candy.chocolate,
                  ),
                ),
                Text(
                  'Birthday deals just for you',
                  style: TextStyle(
                    fontSize: 12,
                    color: Candy.lavender,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _countBar(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.celebration_outlined, size: 13, color: Candy.raspberry),
          const SizedBox(width: 4),
          Text(
            '$count birthday deal${count == 1 ? '' : 's'} available this month 🎂',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyBirthdayDeals() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cake_outlined, size: 52, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No birthday deals right now',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Check back — new birthday offers are added regularly.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _notBirthdayMonth(int? birthdayMonth) {
    final hasMonth = birthdayMonth != null;
    final monthName = hasMonth ? _kMonthNames[birthdayMonth] : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cake_outlined, size: 52, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            hasMonth
                ? 'Your birthday deals arrive in $monthName 🎂'
                : 'Add your birthday to unlock exclusive deals',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasMonth
                ? 'Birthday deals from your favorite brands will appear here when your month arrives.'
                : 'Set your birth month in Profile → Edit Preferences to see birthday deals from Starbucks, Sephora, and more.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}
