import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/promotion.dart';
import '../services/interaction_service.dart';
import '../services/supabase_service.dart';
import '../services/location_service.dart';
import '../services/user_prefs_service.dart';
import '../theme/candy_colors.dart';
import '../utils/feed_ranker.dart';
import '../utils/format_utils.dart';
import '../utils/ranking_contract.dart';
import '../widgets/deal_card.dart';
import '../widgets/deal_impression_tracker.dart';
import 'deal_detail_screen.dart';

const _kRadiusKey = 'near_me_radius_mi';
const _kRadiusOptions = [1, 3, 5, 10];

class NearMeScreen extends StatefulWidget {
  final List<Promotion> all;
  final bool active;
  final Position? position;
  final bool locating;
  final Set<String> memberships;
  final DateTime? lastUpdated;
  final Future<void> Function() onRefresh;
  final Future<void> Function()? onRequestLocation;

  const NearMeScreen({
    super.key,
    required this.all,
    required this.position,
    required this.locating,
    required this.onRefresh,
    this.memberships = const {},
    this.lastUpdated,
    this.onRequestLocation,
    this.active = true,
  });

  @override
  State<NearMeScreen> createState() => _NearMeScreenState();
}

class _NearMeScreenState extends State<NearMeScreen> {
  final _svc = InteractionService();
  int _radiusMi = RankingContract.nearMeDefaultRadiusMi;
  String _lastRecordedKey = '';

  @override
  void initState() {
    super.initState();
    _loadRadius();
  }

  Future<void> _loadRadius() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_kRadiusKey);
    if (saved != null && mounted) setState(() => _radiusMi = saved);
  }

  Future<void> _setRadius(int miles) async {
    setState(() {
      _radiusMi = miles;
      _lastRecordedKey = '';
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kRadiusKey, miles);
  }

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

  void _showRadiusPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: Text(
                  'Distance Radius',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              for (final miles in _kRadiusOptions)
                ListTile(
                  title: Text('Within $miles mi'),
                  leading: Icon(
                    _radiusMi == miles
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: _radiusMi == miles ? Candy.raspberry : null,
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _setRadius(miles);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserPrefsService(),
      builder: (context, _) {
        final prefs = UserPrefsService().prefs;
        final deals = widget.position == null
            ? <Promotion>[]
            : selectNearbyDeals(
                widget.all,
                _svc,
                getIsMember: _hasMembership,
                prefs: prefs,
                radiusKm: _radiusMi * 1.60934,
                limit: RankingContract.nearMeLimit,
              );
        _recordVisible(deals);

        return Scaffold(
          backgroundColor: Candy.cream,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _header()),
                  if (widget.locating)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (widget.position == null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _locationState(),
                    )
                  else if (deals.isEmpty)
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

  Widget _header() {
    final position = widget.position;
    final updated = widget.lastUpdated;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.near_me, size: 23, color: Candy.raspberry),
              const SizedBox(width: 9),
              const Text(
                'Near Me',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: Candy.chocolate,
                ),
              ),
              const Spacer(),
              if (updated != null)
                Text(
                  formatLastUpdated(updated),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.location_on,
                size: 14,
                color: position != null ? Candy.mint : Colors.grey.shade400,
              ),
              const SizedBox(width: 4),
              Text(
                widget.locating
                    ? 'Locating...'
                    : position != null
                    ? LocationService.cityName(
                        position.latitude,
                        position.longitude,
                      )
                    : 'Location unavailable',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: position != null
                      ? Candy.chocolate
                      : Colors.grey.shade400,
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _showRadiusPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Candy.raspberry.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Candy.raspberry.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_radiusMi mi',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Candy.raspberry,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_drop_down,
                        size: 16,
                        color: Candy.raspberry,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _countLabel(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(
        '$count nearby deals',
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
      distanceKm: promo.distanceKm,
      isMember: _hasMembership(promo),
      prefs: UserPrefsService().prefs,
    );
    Future<bool> recordImpression() => _svc.recordFeedImpression(
      promo,
      rankingMode: 'near_me',
      feedPosition: position,
      runtimeScore: score,
    );
    return DealImpressionTracker(
      trackingKey:
          '${SupabaseService.currentUserId}|near_me|${promo.source}|${promo.id}',
      active: widget.active,
      onImpression: recordImpression,
      child: DealCard(
        promo: promo,
        onInteraction: () => unawaited(recordImpression()),
        memberships: widget.memberships,
        feedPosition: position,
        rankingMode: 'near_me',
        onTap: () async {
          _svc.recordClick(
            promo.id,
            brand: promo.brand,
            category: promo.category,
            meta: InteractionService.promoMeta(
              promo,
              rankingMode: 'near_me',
              feedPosition: position,
              runtimeScore: score,
            ),
          );
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DealDetailScreen(
                promo: promo,
                rankingMode: 'near_me',
                feedPosition: position,
              ),
            ),
          );
          if (mounted) setState(() => _lastRecordedKey = '');
        },
      ),
    );
  }

  Widget _locationState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.location_off_outlined,
          size: 48,
          color: Colors.grey.shade300,
        ),
        const SizedBox(height: 12),
        Text(
          'Location required',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: widget.onRequestLocation == null
              ? null
              : () {
                  widget.onRequestLocation!();
                },
          icon: const Icon(Icons.near_me, size: 16),
          label: const Text('Use Location'),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.storefront_outlined, size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(
          'No high-quality deals within $_radiusMi mi',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
        ),
        if (_radiusMi < _kRadiusOptions.last) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.zoom_out_map, size: 16),
            label: const Text('Expand Radius'),
            onPressed: _showRadiusPicker,
            style: OutlinedButton.styleFrom(
              foregroundColor: Candy.raspberry,
              side: const BorderSide(color: Candy.raspberry),
            ),
          ),
        ],
      ],
    );
  }
}
