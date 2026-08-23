import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
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
      options.dsn = 'https://c51b5b12b038586731b61a2de7c26a6b@o4511633696620544.ingest.us.sentry.io/4511633700683776';
      options.tracesSampleRate = 0.2;
    },
    appRunner: () async {
      WidgetsFlutterBinding.ensureInitialized();

      bool firebaseReady = false;
      try {
        await Firebase.initializeApp();
        firebaseReady = true;
      } catch (_) {
        // Firebase config files not yet added — push notifications unavailable
      }

      if (firebaseReady) {
        FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);

        // Handle notification tap when app is opened from terminated state
        try {
          final initial = await FirebaseMessaging.instance
              .getInitialMessage()
              .timeout(const Duration(seconds: 5), onTimeout: () => null);
          if (initial != null) {
            final promoId = initial.data['promo_id'] as String?;
            if (promoId != null && promoId.isNotEmpty) {
              await NotificationService.storePendingPromoId(promoId);
            }
          }
        } catch (_) {}

        // Handle notification tap when app is in background
        FirebaseMessaging.onMessageOpenedApp.listen((message) async {
          final promoId = message.data['promo_id'] as String?;
          if (promoId != null && promoId.isNotEmpty) {
            await NotificationService.storePendingPromoId(promoId);
            NotificationService.tapNotifier.value = promoId;
          }
        });
      }

      await NotificationService.init(navigatorKey: navigatorKey);
      runApp(const PromoViewerApp());
    },
  );
}

class PromoViewerApp extends StatelessWidget {
  const PromoViewerApp({super.key});

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
            return IconThemeData(color: Candy.chocolate.withValues(alpha: 0.45));
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                  color: Candy.raspberry, fontWeight: FontWeight.w600, fontSize: 12);
            }
            return TextStyle(
                color: Candy.chocolate.withValues(alpha: 0.45), fontSize: 12);
          }),
        ),
      ),
      home: const SplashScreen(),
      // OAuth redirect deep links arrive as unknown named routes (/login-callback/).
      // Push a transparent, zero-duration route that pops itself — onAuthStateChange handles navigation.
      onUnknownRoute: (settings) => PageRouteBuilder<void>(
        settings: settings,
        opaque: false,
        transitionDuration: Duration.zero,
        pageBuilder: (context, anim, anim2) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          });
          return const SizedBox.shrink();
        },
      ),
    );
  }
}
