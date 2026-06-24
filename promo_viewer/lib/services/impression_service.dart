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

  /// Record that [promos] appeared in [context] (e.g. 'forYou', 'nearMe', 'search_forYou').
  /// Debounced 2 s per context so rapid filter/chip changes don't spam Supabase.
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
    try {
      final rows = promos.asMap().entries.map((e) => {
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
    } catch (e) {
      if (kDebugMode) debugPrint('[ImpressionService] $context: $e');
    }
  }
}
