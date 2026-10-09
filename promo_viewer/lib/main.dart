import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/splash_screen.dart';
import 'screens/notification_deal_screen.dart';
import 'services/notification_service.dart';
import 'services/gmail_connection_service.dart';
import 'theme/candy_colors.dart';

final navigatorKey = GlobalKey<NavigatorState>();

// Must be top-level for FCM background handler
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

void main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn =
          'https://c51b5b12b038586731b61a2de7c26a6b@o4511633696620544.ingest.us.sentry.io/4511633700683776';
      options.tracesSampleRate = 0.2;
    },
    appRunner: () async {
      WidgetsFlutterBinding.ensureInitialized();

      final nativePromoId = await NotificationService.nativeLaunchPromoId();
      if (nativePromoId != null && nativePromoId.isNotEmpty) {
        await NotificationService.storePendingPromoId(nativePromoId);
      }

      bool firebaseReady = false;
      try {
        await Firebase.initializeApp();
        firebaseReady = true;
      } catch (_) {
        // Firebase config files not yet added — push notifications unavailable
      }

      if (firebaseReady) {
        FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);

        FirebaseMessaging.onMessageOpenedApp.listen((message) async {
          final promoId = message.data['promo_id'] as String?;
          if (promoId != null && promoId.isNotEmpty) {
            await NotificationService.queuePromoTap(promoId);
          }
        });

        // Handle notification tap when app is opened from terminated state
        try {
          if (nativePromoId == null) {
            final initial = await FirebaseMessaging.instance
                .getInitialMessage()
                .timeout(const Duration(seconds: 5), onTimeout: () => null);
            if (initial != null) {
              final promoId = initial.data['promo_id'] as String?;
              if (promoId != null && promoId.isNotEmpty) {
                await NotificationService.storePendingPromoId(promoId);
              }
            }
          }
        } catch (_) {}
      }

      await NotificationService.init(navigatorKey: navigatorKey);
      await NotificationService.restorePendingPromoId();
      runApp(const PromoViewerApp());
    },
  );
}

class PromoViewerApp extends StatefulWidget {
  const PromoViewerApp({
    super.key,
    this.notificationBuilder,
    this.startupBuilder,
  });

  final Widget Function(String id, bool coldStart)? notificationBuilder;
  final Widget Function(BuildContext context, VoidCallback onFinished)?
  startupBuilder;

  @override
  State<PromoViewerApp> createState() => _PromoViewerAppState();
}

class _PromoViewerAppState extends State<PromoViewerApp> {
  String? _initialPromoId;
  bool _showingSplash = true;
  final Set<String> _openNotifications = {};

  @override
  void initState() {
    super.initState();
    _initialPromoId =
        NotificationService.pendingPromoId ??
        NotificationService.tapNotifier.value;
    if (_initialPromoId != null) {
      _showingSplash = false;
      _openNotifications.add(_initialPromoId!);
      unawaited(NotificationService.acknowledgePromoTap(_initialPromoId!));
    }
    NotificationService.tapNotifier.addListener(_onNotificationTap);
  }

  @override
  void dispose() {
    NotificationService.tapNotifier.removeListener(_onNotificationTap);
    super.dispose();
  }

  Widget _notificationScreen(String id, bool coldStart) =>
      widget.notificationBuilder?.call(id, coldStart) ??
      NotificationDealScreen(
        promoId: id,
        coldStart: coldStart,
        onClosed: () => _openNotifications.remove(id),
      );

  void _onNotificationTap() {
    final id = NotificationService.tapNotifier.value;
    if (id == null || !mounted) return;
    unawaited(NotificationService.acknowledgePromoTap(id));
    if (!_openNotifications.add(id)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        _openNotifications.remove(id);
        unawaited(NotificationService.queuePromoTap(id));
        return;
      }
      final coldStart = _showingSplash;
      _showingSplash = false;
      final route = MaterialPageRoute<void>(
        settings: RouteSettings(name: 'notification/$id'),
        builder: (_) => _notificationScreen(id, coldStart),
      );
      final closed = coldStart
          ? navigator.pushAndRemoveUntil(route, (_) => false)
          : navigator.push(route);
      unawaited(closed.then((_) => _openNotifications.remove(id)));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Candy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Candy.raspberry,
          brightness: Brightness.light,
        ).copyWith(surface: Candy.cream),
        useMaterial3: true,
        scaffoldBackgroundColor: Candy.cream,
        cardTheme: const CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          indicatorColor: Candy.raspberry.withValues(alpha: 0.12),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Candy.raspberry);
            }
            return IconThemeData(
              color: Candy.chocolate.withValues(alpha: 0.45),
            );
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                color: Candy.raspberry,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              );
            }
            return TextStyle(
              color: Candy.chocolate.withValues(alpha: 0.45),
              fontSize: 12,
            );
          }),
        ),
      ),
      home: _initialPromoId != null
          ? _notificationScreen(_initialPromoId!, true)
          : widget.startupBuilder?.call(
                  context,
                  () => _showingSplash = false,
                ) ??
                SplashScreen(onFinished: () => _showingSplash = false),
      // OAuth redirect deep links arrive as unknown named routes.
      // With scene-based lifecycle (FlutterSceneDelegate), the redirect URL goes
      // through Flutter's navigation channel — app_links never sees it and
      // Supabase's uriLinkStream never fires. We detect the code here and call
      // getSessionFromUrl directly, which triggers onAuthStateChange.signedIn.
      onUnknownRoute: (settings) {
        final uri = Uri.tryParse(settings.name ?? '');
        final callbackParameters = <String, String>{};
        if (uri != null) {
          try {
            callbackParameters.addAll(uri.queryParameters);
            if (uri.fragment.contains('=')) {
              callbackParameters.addAll(Uri.splitQueryString(uri.fragment));
            }
          } on FormatException catch (e) {
            if (GmailConnectionService.hasPendingConnect) {
              GmailConnectionService.reportFailure('oauth_callback', e);
            }
          }
        }
        if (GmailConnectionService.hasPendingConnect &&
            callbackParameters.containsKey('error')) {
          GmailConnectionService.reportFailure(
            'oauth_callback',
            AuthException(
              callbackParameters['error_description'] ??
                  callbackParameters['error']!,
              code: callbackParameters['error'],
            ),
          );
          GmailConnectionService.cancelPendingConnect();
        }
        if (uri != null &&
            callbackParameters.containsKey('code') &&
            !callbackParameters.containsKey('error')) {
          () async {
            try {
              if (GmailConnectionService.hasPendingConnect) {
                GmailConnectionService.log(
                  'oauth_callback',
                  'Received Google authorization return; exchanging code',
                );
              }
              await Supabase.instance.client.auth.getSessionFromUrl(uri);
            } catch (e) {
              if (GmailConnectionService.hasPendingConnect) {
                GmailConnectionService.reportFailure('oauth_callback', e);
                await GmailConnectionService.cancelPendingConnect();
              }
            }
          }();
        }
        return PageRouteBuilder<void>(
          settings: settings,
          opaque: false,
          transitionDuration: Duration.zero,
          pageBuilder: (context, anim, anim2) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(context).canPop()) Navigator.of(context).pop();
            });
            return const SizedBox.shrink();
          },
        );
      },
    );
  }
}
