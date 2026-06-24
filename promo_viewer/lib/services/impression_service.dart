import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/promotion.dart';
import 'supabase_service.dart';
import 'user_prefs_service.dart';

class ImpressionService {
  static final ImpressionService _i = ImpressionService._();
  factory ImpressionService() => _i;
  ImpressionService._();

  // Unique per app launch — correlates events within a session.
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toRadixString(16);

  final Map<String, Timer> _timers = {};

  // Tracks "${promoId}_$context" pairs already written this session.
  // Prevents duplicate rows when the user switches chips rapidly or
  // the feed re-renders without the content actually changing.
  final Set<String> _recorded = {};

  /// Record that [promos] appeared in [context].
  /// Debounced 2 s per context; each (promoId, context) pair is only
  /// inserted once per session to avoid inflating fatigue counters.
  void recordImpressions(List<Promotion> promos, {required String context}) {
    _timers[context]?.cancel();
    _timers[context] = Timer(
      const Duration(seconds: 2),
      () => _write(List.unmodifiable(promos), context),
    );
  }

  Future<void> _write(List<Promotion> promos, String context) async {
    if (!SupabaseService.isLoggedIn) return;
    final userId = UserPrefsService().userId;
    if (userId == null || promos.isEmpty) return;

    // Filter to only promos not yet recorded this session.
    final novel = promos.where((p) => !_recorded.contains('${p.id}_$context')).toList();
    if (novel.isEmpty) return;

    try {
      final rows = novel.asMap().entries.map((e) => {
        'user_id':             userId,
        'session_id':          _sessionId,
        'promotion_id':        e.value.id,
        'brand':               e.value.brand,
        'category':            e.value.category,
        'context':             context,
        'rank_position':       e.key,
        'score_at_impression': e.value.rankBaseScore,
      }).toList();
      await SupabaseService.client.from('deal_impressions').insert(rows);
      for (final p in novel) {
        _recorded.add('${p.id}_$context');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ImpressionService] $context: $e');
    }
  }
}
