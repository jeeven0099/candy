import 'package:flutter/material.dart';
import '../models/promotion.dart';
import '../theme/candy_colors.dart';
import '../utils/format_utils.dart';
import '../widgets/deal_card.dart';
import 'deal_detail_screen.dart';

const _kDefaultLimit = 10;

class RewardsScreen extends StatefulWidget {
  final List<Promotion> all;
  final Set<String> memberships;
  final DateTime? lastUpdated;
  final Future<void> Function() onRefresh;

  const RewardsScreen({
    super.key,
    required this.all,
    required this.onRefresh,
    this.memberships = const {},
    this.lastUpdated,
  });

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  String _query = '';
  bool _showAll = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _hasMembership(Promotion p) {
    if (widget.memberships.isEmpty) return false;
    final brand = p.brand.toLowerCase();
    final memberName = (p.membershipName ?? '').toLowerCase();
    return widget.memberships.any((m) =>
        m.contains(brand) || brand.contains(m) ||
        (memberName.isNotEmpty && (m.contains(memberName) || memberName.contains(m))));
  }

  // Quality gate for the curated rewards feed.
  // Confirmed memberships and free-to-join programs always make the cut.
  bool _isQualityReward(Promotion p) {
    if (_hasMembership(p)) return true; // confirmed member: always surface
    if (p.confidenceScore < 0.75) return false;
    final cost = (p.membershipCost ?? '').toLowerCase();
    if (cost.isEmpty || cost.contains('free')) return true;
    if (p.discountType == 'free_item') return true;
    return p.rankScore(isMember: false) >= 60;
  }

  List<Promotion> get _filtered {
    final q = _query.toLowerCase();

    return widget.all.where((p) {
      if (p.promotionType != 'reward' && p.promotionType != 'membership_benefit') return false;
      if (p.category == 'finance') return false;
      if (q.isNotEmpty &&
          !p.brand.toLowerCase().contains(q) &&
          !p.title.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.rankScore(isMember: _hasMembership(b))
            .compareTo(a.rankScore(isMember: _hasMembership(a))));
  }

  List<Promotion> _toDisplay(List<Promotion> base) {
    if (_query.isNotEmpty || _showAll) return base;
    final quality = base.where(_isQualityReward).toList();
    return quality.length > _kDefaultLimit ? quality.sublist(0, _kDefaultLimit) : quality;
  }

  @override
  Widget build(BuildContext context) {
    final all = _filtered;
    final display = _toDisplay(all);

    return Scaffold(
      backgroundColor: Candy.cream,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Expanded(child: _buildBody(display, all)),
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
              const Icon(Icons.card_membership, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rewards',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: Candy.chocolate,
                      ),
                    ),
                    Text(
                      'Your rewards',
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
            controller: _searchController,
            hintText: 'Search rewards programs…',
            leading: const Icon(Icons.search, size: 20),
            trailing: [
              if (_query.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
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
            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(List<Promotion> display, List<Promotion> all) {
    if (display.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.card_membership_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No rewards programs found',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
          ],
        ),
      );
    }

    final isCurated = _query.isEmpty && !_showAll;
    final showSeeAll = isCurated && display.length < all.length;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: display.length + 1 + (showSeeAll ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == 0) {
            final label = isCurated
                ? '${display.length} of ${all.length} programs'
                : '${display.length} program${display.length == 1 ? '' : 's'}';
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
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
                child: Text('See all ${all.length} programs'),
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
