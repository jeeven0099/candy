import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/promotion.dart';
import '../utils/ranking_contract.dart';
import 'supabase_service.dart';
import 'user_prefs_service.dart';

class EmailDealsService {
  static List<Promotion> _cached = [];
  static String? _owner;
  static int _generation = 0;
  static List<Promotion> get cached =>
      _owner == SupabaseService.currentUserId ? _cached : [];

  static Future<List<Promotion>> loadForCurrentUser() async {
    final owner = SupabaseService.currentUserId;
    final generation = ++_generation;
    if (_owner != owner) _cached = [];
    _owner = owner;
    if (!SupabaseService.isLoggedIn) {
      _cached = [];
      return [];
    }

    var userId = UserPrefsService().userId;
    if (userId == null) {
      await UserPrefsService().load();
      userId = UserPrefsService().userId;
    }
    if (userId == null) {
      if (generation == _generation) _cached = [];
      return [];
    }
    if (owner != SupabaseService.currentUserId || generation != _generation) {
      return [];
    }

    try {
      final rowsRaw = await SupabaseService.client
          .from('user_email_deals')
          .select(
            'id,user_id,status,visibility,promotion_json,'
            'personal_rank_score,personal_rank_model,personal_rank_reasons,'
            'personal_rank_summary,email_subject,sender_email,email_date,'
            'expires_at,received_at',
          )
          .eq('user_id', userId)
          .eq('status', 'active')
          .gte('personal_rank_score', RankingContract.emailPersonalRankFloor)
          .gte(
            'received_at',
            DateTime.now()
                .toUtc()
                .subtract(const Duration(days: 14))
                .toIso8601String(),
          )
          .order('personal_rank_score', ascending: false)
          .limit(50);
      final rows = rowsRaw as List<dynamic>;

      final now = DateTime.now();
      final deals = <Promotion>[];
      for (final row in rows.whereType<Map<String, dynamic>>()) {
        final expiresAt = _parseDate(row['expires_at']);
        if (expiresAt != null && expiresAt.isBefore(now)) continue;
        final receivedAt = _parseDate(row['received_at']);
        if (receivedAt == null ||
            receivedAt.isBefore(now.subtract(const Duration(days: 14)))) {
          continue;
        }

        final promotionJson = _promotionJson(row['promotion_json']);
        if (promotionJson.isEmpty) continue;
        final rankScore =
            (row['personal_rank_score'] as num?)?.toDouble() ?? 0.0;

        promotionJson['source'] = 'email';
        promotionJson['visibility'] =
            promotionJson['visibility'] ??
            row['visibility'] ??
            'private_user_offer';
        promotionJson['personal_rank_score'] = rankScore;
        promotionJson['personal_rank_model'] = row['personal_rank_model'];
        promotionJson['personal_rank_reasons'] = _stringList(
          row['personal_rank_reasons'],
        );
        promotionJson['personal_rank_summary'] =
            row['personal_rank_summary'] as String?;
        promotionJson['email_subject'] =
            promotionJson['email_subject'] ?? row['email_subject'];
        promotionJson['sender_email'] =
            promotionJson['sender_email'] ?? row['sender_email'];
        promotionJson['status'] = promotionJson['status'] ?? 'active';
        promotionJson['global_quality_score'] =
            promotionJson['global_quality_score'] ?? 0.0;

        final promo = Promotion.fromJson(promotionJson);
        if (promo.title.isNotEmpty) deals.add(promo);
      }
      if (owner != SupabaseService.currentUserId || generation != _generation) {
        return [];
      }
      _cached = deals;
    } catch (e) {
      debugPrint('[EmailDealsService] loadForCurrentUser: $e');
      if (owner == SupabaseService.currentUserId && generation == _generation) {
        _cached = [];
      }
    }
    if (owner != SupabaseService.currentUserId || generation != _generation) {
      return [];
    }
    return cached;
  }

  static List<Promotion> mergeWithPublicPromotions(
    List<Promotion> publicPromotions,
    List<Promotion> emailPromotions,
  ) {
    if (emailPromotions.isEmpty) return publicPromotions;

    final byKey = <String, Promotion>{};
    for (final promo in publicPromotions) {
      byKey[_dedupKey(promo)] = promo;
    }
    for (final promo in emailPromotions) {
      final key = _dedupKey(promo);
      final existing = byKey[key];
      if (existing == null ||
          (promo.personalRankScore ?? promo.globalQualityScore) >
              (existing.personalRankScore ?? existing.globalQualityScore)) {
        byKey[key] = promo;
      }
    }
    return byKey.values.toList();
  }

  static Map<String, dynamic> _promotionJson(dynamic raw) {
    if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return {};
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is List) return raw.whereType<String>().toList();
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.whereType<String>().toList();
      } catch (_) {}
    }
    return const [];
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static String _dedupKey(Promotion promo) {
    final brand = promo.brand.trim().toLowerCase();
    final title = promo.title.trim().toLowerCase();
    return '$brand||$title';
  }
}
