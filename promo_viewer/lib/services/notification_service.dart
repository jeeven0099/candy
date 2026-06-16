import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../screens/deal_detail_screen.dart';
import 'promotions_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  static const _channelId   = 'candy_reminders';
  static const _channelName = 'Deal Reminders';

  final _plugin = FlutterLocalNotificationsPlugin();

  static GlobalKey<NavigatorState>? _navigatorKey;

  // Holds a promoId when the app is launched cold from a notification tap.
  // MainScreen reads this after promotions are loaded and navigates.
  static String? pendingPromoId;

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
    // Capture promoId when the app was fully terminated and the user tapped
    // the notification to open it.
    final launchDetails = await svc._plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      pendingPromoId = launchDetails?.notificationResponse?.payload;
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

  // Called when user taps a notification while app is open or in background.
  static void _handleTap(NotificationResponse response) {
    final promoId = response.payload;
    if (promoId == null || promoId.isEmpty) return;
    final matches = PromotionsService.cached.where((p) => p.id == promoId);
    if (matches.isEmpty) {
      // Promotions not loaded yet — store for MainScreen to handle after load.
      pendingPromoId = promoId;
      return;
    }
    _navigatorKey?.currentState?.push(
      MaterialPageRoute(builder: (_) => DealDetailScreen(promo: matches.first)),
    );
  }

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

  static int _notifId(String id) => id.hashCode & 0x7FFFFFFF;
}
