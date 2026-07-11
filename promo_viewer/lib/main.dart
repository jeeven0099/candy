import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'theme/candy_colors.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://c51b5b12b038586731b61a2de7c26a6b@o4511633696620544.ingest.us.sentry.io/4511633700683776';
      options.tracesSampleRate = 0.2;
    },
    appRunner: () async {
      WidgetsFlutterBinding.ensureInitialized();
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
    );
  }
}
