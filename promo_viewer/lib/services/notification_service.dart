import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../screens/deal_detail_screen.dart';
import 'promotions_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  static const _channelId   = 'candy_reminders';
  static const _channelName = 'Deal Reminders';

  // Rate-limit config (matches design spec)
  static const _maxPerDay       = 2;
  static const _minGapHours     = 4;
  static const _quietStart      = 22; // 10 PM
  static const _quietEnd        = 8;  // 8 AM
  static const _brandCooldownDays = 7;
  static const _dealCooldownDays  = 7;

  // SharedPreferences keys
  static const _kNotifiedDeals        = 'notif_notified_deals_v1';      // JSON list of {id, ts}
  static const _kNotifiedBrands       = 'notif_notified_brands_v1';     // JSON map brand→ts
  static const _kSentToday            = 'notif_sent_today_v1';          // JSON {date, count}
  static const _kLastSentAt           = 'notif_last_sent_at_v1';        // ISO string

  final _plugin = FlutterLocalNotificationsPlugin();

  static GlobalKey<NavigatorState>? _navigatorKey;

  // Holds a promoId when the app is launched cold from a notification tap.
  static String? pendingPromoId;
  static final tapNotifier = ValueNotifier<String?>(null);

  static Future<void> init({GlobalKey<NavigatorState>? navigatorKey}) async {
    if (kIsWeb) return;
    _navigatorKey = navigatorKey;
    final svc = NotificationService();
    await svc._plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: false,
          requestSoundPermission: true,
        ),
      ),
      onDidReceiveNotificationResponse: _handleTap,
    );
    final launchDetails = await svc._plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final id = launchDetails?.notificationResponse?.payload;
      if (id != null && id.isNotEmpty) {
        pendingPromoId = id;
      }
    }
    final androidPlugin = svc._plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Reminders for saved deals expiring soon.',
      importance: Importance.high,
    ));
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
  }

  static void _handleTap(NotificationResponse response) {
    final promoId = response.payload;
    if (promoId == null || promoId.isEmpty) return;
    final matches = PromotionsService.cached.where((p) => p.id == promoId);
    if (matches.isEmpty) {
      pendingPromoId = promoId;
      tapNotifier.value = promoId;
      return;
    }
    _navigatorKey?.currentState?.push(
      MaterialPageRoute(builder: (_) => DealDetailScreen(promo: matches.first)),
    );
  }

  // ---------------------------------------------------------------------------
  // Pipeline-driven notification candidates
  // ---------------------------------------------------------------------------

  /// Called once on app launch. Reads notification_candidates.json and sends
  /// notifications for qualifying deals that haven't been shown yet.
  Future<void> processNotificationCandidates() async {
    if (kIsWeb) return;

    final Map<String, dynamic> data;
    try {
      final raw = await rootBundle.loadString('assets/notification_candidates.json');
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      return; // file missing or malformed — skip silently
    }

    final candidates = (data['candidates'] as List?)
        ?.whereType<Map<String, dynamic>>()
        .toList() ?? [];
    if (candidates.isEmpty) return;

    if (_inQuietHours()) return;

    final prefs = await SharedPreferences.getInstance();

    final notifiedDeals  = _loadNotifiedDeals(prefs);
    final notifiedBrands = _loadNotifiedBrands(prefs);
    final todayCount     = _loadTodayCount(prefs);

    if (todayCount >= _maxPerDay) return;

    final lastSentStr = prefs.getString(_kLastSentAt);
    if (lastSentStr != null) {
      final last = DateTime.tryParse(lastSentStr);
      if (last != null &&
          DateTime.now().difference(last).inHours < _minGapHours) {
        return;
      }
    }

    int sent = 0;
    final now = DateTime.now();
    final today = _dateKey(now);

    for (final c in candidates) {
      if (todayCount + sent >= _maxPerDay) break;

      final promoId = c['promo_id'] as String? ?? '';
      final brand   = c['brand'] as String? ?? '';

      // Deal cooldown: skip if notified about this exact deal in last 7 days
      if (_isCooledDown(notifiedDeals, promoId, _dealCooldownDays)) continue;

      // Brand cooldown: skip if notified about this brand in last 7 days
      if (_isCooledDown(notifiedBrands, brand, _brandCooldownDays)) continue;

      final notifTitle = c['notification_title'] as String? ?? brand;
      final notifBody  = c['notification_body'] as String? ?? '';
      final score      = (c['notify_score'] as num?)?.toDouble() ?? 0.0;

      await _sendImmediate(
        id: promoId.hashCode & 0x7FFFFFFF,
        title: notifTitle,
        body: notifBody,
        payload: promoId,
        score: score,
      );

      notifiedDeals[promoId] = today;
      notifiedBrands[brand]  = today;
      sent++;

      // Enforce 4-hour gap between consecutive notifications in this batch
      if (sent < _maxPerDay - todayCount) {
        break; // only send one per launch — gap enforced on next open
      }
    }

    if (sent > 0) {
      _saveNotifiedDeals(prefs, notifiedDeals);
      _saveNotifiedBrands(prefs, notifiedBrands);
      _saveTodayCount(prefs, todayCount + sent, today);
      await prefs.setString(_kLastSentAt, now.toIso8601String());
    }
  }

  // ---------------------------------------------------------------------------
  // Reminder scheduling (for saved deals expiring soon — existing feature)
  // ---------------------------------------------------------------------------

  Future<void> scheduleReminder({
    required String promoId,
    required String brand,
    required String title,
    required DateTime remindAt,
  }) async {
    if (kIsWeb) return;
    final when = tz.TZDateTime.from(remindAt, tz.local);
    if (when.isBefore(tz.TZDateTime.now(tz.local))) return;

    await _plugin.zonedSchedule(
      id: _notifId(promoId),
      title: '$brand deal is expiring soon!',
      body: title,
      payload: promoId,
      scheduledDate: when,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancelReminder(String promoId) async {
    if (kIsWeb) return;
    await _plugin.cancel(id: _notifId(promoId));
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<void> _sendImmediate({
    required int id,
    required String title,
    required String body,
    required String payload,
    required double score,
  }) async {
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          subtitle: 'Tap to see deal',
        ),
      ),
      payload: payload,
    );
  }

  bool _inQuietHours() {
    final h = DateTime.now().hour;
    return h >= _quietStart || h < _quietEnd;
  }

  bool _isCooledDown(Map<String, String> history, String key, int cooldownDays) {
    final ts = history[key];
    if (ts == null) return false;
    final d = DateTime.tryParse(ts);
    if (d == null) return false;
    return DateTime.now().difference(d).inDays < cooldownDays;
  }

  String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  // notifiedDeals: { promoId → "YYYY-MM-DD" }
  Map<String, String> _loadNotifiedDeals(SharedPreferences prefs) {
    final raw = prefs.getString(_kNotifiedDeals);
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  void _saveNotifiedDeals(SharedPreferences prefs, Map<String, String> map) {
    // Prune entries older than cooldown period to keep storage small
    final cutoff = DateTime.now().subtract(const Duration(days: _dealCooldownDays));
    map.removeWhere((_, ts) {
      final d = DateTime.tryParse(ts);
      return d != null && d.isBefore(cutoff);
    });
    prefs.setString(_kNotifiedDeals, jsonEncode(map));
  }

  Map<String, String> _loadNotifiedBrands(SharedPreferences prefs) {
    final raw = prefs.getString(_kNotifiedBrands);
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  void _saveNotifiedBrands(SharedPreferences prefs, Map<String, String> map) {
    final cutoff = DateTime.now().subtract(const Duration(days: _brandCooldownDays));
    map.removeWhere((_, ts) {
      final d = DateTime.tryParse(ts);
      return d != null && d.isBefore(cutoff);
    });
    prefs.setString(_kNotifiedBrands, jsonEncode(map));
  }

  int _loadTodayCount(SharedPreferences prefs) {
    final raw = prefs.getString(_kSentToday);
    if (raw == null) return 0;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final today = _dateKey(DateTime.now());
      if (map['date'] == today) return (map['count'] as num?)?.toInt() ?? 0;
    } catch (_) {}
    return 0;
  }

  void _saveTodayCount(SharedPreferences prefs, int count, String today) {
    prefs.setString(_kSentToday, jsonEncode({'date': today, 'count': count}));
  }

  static int _notifId(String id) => id.hashCode & 0x7FFFFFFF;
}
