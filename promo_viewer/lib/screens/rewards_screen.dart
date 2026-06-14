import 'package:flutter/material.dart';
import '../models/promotion.dart';
import '../theme/candy_colors.dart';
import '../widgets/deal_card.dart';
import 'deal_detail_screen.dart';

class RewardsScreen extends StatefulWidget {
  final List<Promotion> all;
  final Set<String> memberships;
  const RewardsScreen({super.key, required this.all, this.memberships = const {}});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  String _query = '';
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

  List<Promotion> get _filtered {
    final q = _query.toLowerCase();

    return widget.all.where((p) {
      // Rewards tab: loyalty programs and membership benefits only
      if (p.promotionType != 'reward' && p.promotionType != 'membership_benefit') return false;
      // Finance/credit card "rewards" are not loyalty programs
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

  @override
  Widget build(BuildContext context) {
    final promos = _filtered;

    return Scaffold(
      backgroundColor: Candy.cream,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Expanded(child: _buildBody(promos)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.card_membership, size: 22),
              SizedBox(width: 8),
              Column(
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
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(List<Promotion> promos) {
    if (promos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.card_membership_outlined,
                size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No rewards programs found',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: promos.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '${promos.length} programs',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }
        final promo = promos[i - 1];
        return DealCard(
          promo: promo,
          memberships: widget.memberships,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DealDetailScreen(promo: promo)),
          ),
        );
      },
    );
  }
}
