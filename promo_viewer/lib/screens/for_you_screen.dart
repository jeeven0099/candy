import 'package:flutter/material.dart';
import '../models/promotion.dart';
import '../services/saved_deals_service.dart';
import '../theme/candy_colors.dart';
import '../utils/format_utils.dart';
import '../widgets/deal_card.dart';
import 'deal_detail_screen.dart';

class ForYouScreen extends StatefulWidget {
  final List<Promotion> all;
  final Set<String> memberships;
  final DateTime? lastUpdated;
  final Future<void> Function() onRefresh;

  const ForYouScreen({
    super.key,
    required this.all,
    required this.onRefresh,
    this.memberships = const {},
    this.lastUpdated,
  });

  @override
  State<ForYouScreen> createState() => _ForYouScreenState();
}

class _ForYouScreenState extends State<ForYouScreen> {
  final _svc = SavedDealsService();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _svc,
      builder: (ctx, _) {
        final privateDeals = widget.all
            .where((p) {
              if (p.source != 'email' || !p.isActive) return false;
              final brand = p.brand.toLowerCase();
              if (brand.contains('talent acquisition') ||
                  brand.contains(' from ') ||
                  p.confidenceScore < 0.6) {
                return false;
              }
              return true;
            })
            .toList()
          ..sort((a, b) => b.rankBaseScore.compareTo(a.rankBaseScore));

        final savedIds = _svc.all.map((s) => s.id).toList();
        final savedDeals = savedIds
            .map((id) {
              try {
                return widget.all.firstWhere((p) => p.id == id);
              } catch (_) {
                return null;
              }
            })
            .whereType<Promotion>()
            .toList();

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            backgroundColor: Candy.cream,
            body: SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  _buildTabBar(),
                  const Divider(height: 1),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _PrivateTab(
                          promos: privateDeals,
                          memberships: widget.memberships,
                          onRefresh: widget.onRefresh,
                        ),
                        _SavedTab(
                          promos: savedDeals,
                          memberships: widget.memberships,
                          svc: _svc,
                          onRefresh: widget.onRefresh,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    final updated = widget.lastUpdated;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.favorite, size: 22, color: Candy.raspberry),
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
                  'Personal & saved deals',
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
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                formatLastUpdated(updated),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return const TabBar(
      labelColor: Candy.raspberry,
      unselectedLabelColor: Candy.muted,
      indicatorColor: Candy.raspberry,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      tabs: [
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mark_email_unread_outlined, size: 16),
              SizedBox(width: 6),
              Text('Private'),
            ],
          ),
        ),
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_border, size: 16),
              SizedBox(width: 6),
              Text('Saved'),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Private tab — email-sourced deals
// ---------------------------------------------------------------------------

class _PrivateTab extends StatefulWidget {
  final List<Promotion> promos;
  final Set<String> memberships;
  final Future<void> Function() onRefresh;

  const _PrivateTab({
    required this.promos,
    required this.memberships,
    required this.onRefresh,
  });

  @override
  State<_PrivateTab> createState() => _PrivateTabState();
}

class _PrivateTabState extends State<_PrivateTab> {
  static const _kLimit = 10;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final all = widget.promos;
    final display = (_showAll || all.length <= _kLimit) ? all : all.sublist(0, _kLimit);
    final showSeeAll = !_showAll && all.length > _kLimit;

    if (all.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mark_email_unread_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'No private deals yet',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Deals from your emails will appear here',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: display.length + 1 + (showSeeAll ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == 0) {
            final label = showSeeAll
                ? '${display.length} of ${all.length} private deals from your inbox'
                : '${all.length} private deal${all.length == 1 ? '' : 's'} from your inbox';
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, size: 13, color: Candy.raspberry),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          if (showSeeAll && i == display.length + 1) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: OutlinedButton(
                onPressed: () => setState(() => _showAll = true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Candy.raspberry,
                  side: const BorderSide(color: Candy.raspberry),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('See all ${all.length} private deals'),
              ),
            );
          }
          final promo = display[i - 1];
          return DealCard(
            promo: promo,
            memberships: widget.memberships,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DealDetailScreen(promo: promo)),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Saved tab — heart-saved deals
// ---------------------------------------------------------------------------

class _SavedTab extends StatelessWidget {
  final List<Promotion> promos;
  final Set<String> memberships;
  final SavedDealsService svc;
  final Future<void> Function() onRefresh;

  const _SavedTab({
    required this.promos,
    required this.memberships,
    required this.svc,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (promos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Nothing saved yet',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap ♡ on any deal to save it here',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: promos.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '${promos.length} saved',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }
          final promo = promos[i - 1];
          final saved = svc.get(promo.id);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DealCard(
                promo: promo,
                memberships: memberships,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DealDetailScreen(promo: promo)),
                ),
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
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _formatRemindAt(DateTime dt) {
    final diff = dt.difference(DateTime.now()).inDays;
    if (diff < 0) return '(passed)';
    if (diff == 0) return 'today';
    if (diff == 1) return 'tomorrow';
    return 'in $diff days';
  }
}
