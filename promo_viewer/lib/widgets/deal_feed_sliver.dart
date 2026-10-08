import 'package:flutter/material.dart';

import '../models/promotion.dart';
import '../theme/candy_colors.dart';
import '../utils/deal_feed_queue.dart';
import '../utils/ranking_contract.dart';

typedef DealDismissalCallback =
    Future<void> Function(
      Promotion promo,
      int position,
      DismissDirection direction,
    );

class DealFeedSliver extends StatefulWidget {
  final List<Promotion> rankedDeals;
  final Object revision;
  final Widget Function(BuildContext, Promotion, int, VoidCallback) itemBuilder;
  final Widget Function(int) countBuilder;
  final Widget emptyState;
  final DealDismissalCallback onDismiss;
  final DealDismissalCallback onUndo;

  const DealFeedSliver({
    super.key,
    required this.rankedDeals,
    required this.revision,
    required this.itemBuilder,
    required this.countBuilder,
    required this.emptyState,
    required this.onDismiss,
    required this.onUndo,
  });

  @override
  State<DealFeedSliver> createState() => _DealFeedSliverState();
}

class _DealFeedSliverState extends State<DealFeedSliver> {
  final _queue = DealFeedQueue(reserveLimit: RankingContract.feedReserveLimit);
  int _generation = 0;
  int _dismissSequence = 0;

  @override
  void initState() {
    super.initState();
    _queue.reset(widget.rankedDeals);
  }

  @override
  void didUpdateWidget(covariant DealFeedSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revision != oldWidget.revision) {
      _generation++;
      _dismissSequence++;
      _queue.reset(widget.rankedDeals);
    } else {
      _queue.reconcile(widget.rankedDeals);
    }
  }

  Future<void> _dismiss(
    Promotion promo,
    int position,
    DismissDirection direction,
  ) async {
    final dismissal = _queue.dismiss(promo.id);
    if (dismissal == null) return;
    final sequence = ++_dismissSequence;
    final currentMessenger = ScaffoldMessenger.of(context);
    currentMessenger.clearSnackBars();
    currentMessenger.removeCurrentSnackBar();
    final revision = widget.revision;
    final undo = widget.onUndo;
    setState(() {});
    try {
      await widget.onDismiss(promo, position, direction);
    } catch (_) {
      if (!mounted || widget.revision != revision) return;
      // Dispose the completed Dismissible before restoring its original key.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || widget.revision != revision) return;
      try {
        await undo(promo, position, direction);
      } catch (_) {
        // Keep the local card available even when persistence is unavailable.
      }
      if (!mounted || widget.revision != revision) return;
      setState(() => _queue.undo(dismissal));
      if (sequence != _dismissSequence) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save your feedback')),
      );
      return;
    }
    if (!mounted ||
        widget.revision != revision ||
        sequence != _dismissSequence) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Deal dismissed'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            if (!mounted ||
                widget.revision != revision ||
                sequence != _dismissSequence) {
              return;
            }
            try {
              await undo(promo, position, direction);
              if (!mounted || widget.revision != revision) return;
              setState(() => _queue.undo(dismissal));
            } catch (_) {
              if (mounted &&
                  widget.revision == revision &&
                  sequence == _dismissSequence) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Could not restore this deal')),
                );
              }
            }
          },
        ),
      ),
    );
  }

  Widget _background(Alignment alignment) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Candy.raspberry.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.thumb_down_outlined, color: Candy.raspberry),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final deals = _queue.visible;
    return SliverMainAxisGroup(
      slivers: [
        if (deals.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: widget.emptyState)
        else ...[
          SliverToBoxAdapter(child: widget.countBuilder(deals.length)),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final promo = deals[index];
                return Dismissible(
                  key: ValueKey('$_generation|${promo.id}'),
                  direction: DismissDirection.horizontal,
                  dismissThresholds: const {
                    DismissDirection.startToEnd: 0.35,
                    DismissDirection.endToStart: 0.35,
                  },
                  background: _background(
                    AlignmentDirectional.centerStart.resolve(
                      Directionality.of(context),
                    ),
                  ),
                  secondaryBackground: _background(
                    AlignmentDirectional.centerEnd.resolve(
                      Directionality.of(context),
                    ),
                  ),
                  onDismissed: (direction) =>
                      _dismiss(promo, index + 1, direction),
                  child: widget.itemBuilder(
                    context,
                    promo,
                    index + 1,
                    () => _dismiss(promo, index + 1, DismissDirection.none),
                  ),
                );
              },
              findChildIndexCallback: (key) {
                if (key is! ValueKey<String>) return null;
                final index = deals.indexWhere(
                  (p) => '$_generation|${p.id}' == key.value,
                );
                return index < 0 ? null : index;
              },
              childCount: deals.length,
            ),
          ),
        ],
      ],
    );
  }
}
