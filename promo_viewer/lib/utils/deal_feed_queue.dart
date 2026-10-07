import '../models/promotion.dart';

class DismissedFeedDeal {
  final Promotion promo;
  final int index;
  final String? replacementId;
  const DismissedFeedDeal(this.promo, this.index, this.replacementId);
}

/// Keeps visible cards stable while a bounded, ranked reserve replaces rejects.
class DealFeedQueue {
  final int visibleLimit;
  final int reserveLimit;
  final List<Promotion> _visible = [];
  final List<Promotion> _reserve = [];
  final Set<String> _dismissed = {};

  DealFeedQueue({this.visibleLimit = 10, this.reserveLimit = 30});

  List<Promotion> get visible => List.unmodifiable(_visible);
  List<Promotion> get reserve => List.unmodifiable(_reserve);

  void reset(List<Promotion> ranked) {
    _visible.clear();
    _reserve.clear();
    _dismissed.clear();
    reconcile(ranked);
  }

  void reconcile(List<Promotion> ranked) {
    final eligible = <String, Promotion>{};
    for (final p in ranked) {
      if (!_dismissed.contains(p.id)) eligible.putIfAbsent(p.id, () => p);
    }
    // Refresh objects (including source labels), but do not shuffle kept cards.
    final kept = [
      for (final p in _visible)
        if (eligible.containsKey(p.id)) eligible[p.id]!,
    ];
    final keptIds = kept.map((p) => p.id).toSet();
    final remaining = eligible.values.where((p) => !keptIds.contains(p.id));
    final ordered = [...kept, ...remaining];
    _visible
      ..clear()
      ..addAll(ordered.take(visibleLimit));
    _reserve
      ..clear()
      ..addAll(ordered.skip(visibleLimit).take(reserveLimit));
  }

  DismissedFeedDeal? dismiss(String id) {
    final index = _visible.indexWhere((p) => p.id == id);
    if (index < 0) return null;
    final promo = _visible.removeAt(index);
    _dismissed.add(id);
    final replacement = _reserve.isEmpty ? null : _reserve.removeAt(0);
    if (replacement != null) _visible.insert(index, replacement);
    return DismissedFeedDeal(promo, index, replacement?.id);
  }

  bool undo(DismissedFeedDeal dismissal) {
    if (!_dismissed.remove(dismissal.promo.id)) return false;
    _visible.removeWhere((p) => p.id == dismissal.promo.id);
    _reserve.removeWhere((p) => p.id == dismissal.promo.id);
    final replacementIndex = _visible.indexWhere(
      (p) => p.id == dismissal.replacementId,
    );
    if (replacementIndex >= 0) {
      _reserve.insert(0, _visible.removeAt(replacementIndex));
    }
    final index = dismissal.index.clamp(0, _visible.length);
    _visible.insert(index, dismissal.promo);
    while (_visible.length > visibleLimit) {
      _reserve.insert(0, _visible.removeLast());
    }
    if (_reserve.length > reserveLimit) {
      _reserve.removeRange(reserveLimit, _reserve.length);
    }
    return true;
  }
}
