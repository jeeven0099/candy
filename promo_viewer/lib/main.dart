import 'package:flutter/material.dart';
import 'screens/main_screen.dart';
import 'services/interaction_service.dart';
import 'services/notification_service.dart';
import 'services/saved_deals_service.dart';
import 'services/timezone_service.dart';
import 'theme/candy_colors.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TimezoneService.init();
  await NotificationService.init(navigatorKey: navigatorKey);
  await SavedDealsService.init();
  await InteractionService.init();
  // Fire-and-forget: process pipeline notification candidates on every launch.
  // Rate limits and quiet hours are enforced inside the method.
  NotificationService().processNotificationCandidates();
  runApp(const PromoViewerApp());
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
      home: const MainScreen(),
    );
  }
}
