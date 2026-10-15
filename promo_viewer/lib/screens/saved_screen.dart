import 'package:flutter/material.dart';

import '../models/promotion.dart';
import '../services/interaction_service.dart';
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
    final service = SavedDealsService();
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final saved = service.all;
        final catalog = {for (final offer in all) offer.id: offer};
        return Scaffold(
          backgroundColor: Candy.cream,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.favorite,
                            size: 23,
                            color: Candy.raspberry,
                          ),
                          const SizedBox(width: 9),
                          const Expanded(
                            child: Text(
                              'Saved',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Candy.chocolate,
                              ),
                            ),
                          ),
                          Text(
                            '${saved.length}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Candy.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (saved.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.favorite_border,
                            size: 44,
                            color: Candy.muted,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No saved deals',
                            style: TextStyle(fontSize: 16, color: Candy.muted),
                          ),
                        ],
                      ),
                    )
                  else
                    SliverList.builder(
                      itemCount: saved.length,
                      itemBuilder: (context, index) {
                        final entry = saved[index];
                        final offer = catalog[entry.id];
                        if (offer == null) {
                          return _UnavailableSavedDeal(entry: entry);
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DealCard(
                              key: ValueKey('saved|${offer.id}'),
                              promo: offer,
                              memberships: memberships,
                              rankingMode: 'saved',
                              onTap: () {
                                InteractionService().recordClick(
                                  offer.id,
                                  brand: offer.brand,
                                  category: offer.category,
                                  meta: InteractionService.promoMeta(
                                    offer,
                                    rankingMode: 'saved',
                                  ),
                                );
                                Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => DealDetailScreen(
                                      promo: offer,
                                      rankingMode: 'saved',
                                    ),
                                  ),
                                );
                              },
                            ),
                            if (entry.remindAt != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  28,
                                  0,
                                  16,
                                  8,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.notifications_outlined,
                                      size: 14,
                                      color: Candy.muted,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Reminder ${MaterialLocalizations.of(context).formatShortDate(entry.remindAt!.toLocal())}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Candy.muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UnavailableSavedDeal extends StatelessWidget {
  final SavedDeal entry;
  const _UnavailableSavedDeal({required this.entry});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.brand,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Candy.chocolate,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: Candy.muted),
              ),
              const SizedBox(height: 4),
              const Text(
                'Deal unavailable',
                style: TextStyle(fontSize: 12, color: Candy.muted),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Remove from Saved',
          icon: const Icon(Icons.favorite, color: Candy.raspberry),
          onPressed: () async {
            try {
              await SavedDealsService().unsave(entry.id);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not remove this deal')),
                );
              }
            }
          },
        ),
      ],
    ),
  );
}
