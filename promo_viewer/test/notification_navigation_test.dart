import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/main.dart';
import 'package:promo_viewer/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget details(String id, bool cold) => Scaffold(body: Text('$id|cold=$cold'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationService.resetPendingTapsForTesting();
  });

  testWidgets(
    'cold-launch notification is the first screen instead of splash',
    (tester) async {
      NotificationService.pendingPromoId = 'offer';
      await tester.pumpWidget(
        PromoViewerApp(
          notificationBuilder: details,
          startupBuilder: (_, _) => const Text('Splash'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('offer|cold=true'), findsOneWidget);
      expect(find.text('Splash'), findsNothing);
      expect(NotificationService.pendingPromoId, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('tap while splash initializes replaces it rather than waiting', (
    tester,
  ) async {
    await tester.pumpWidget(
      PromoViewerApp(
        notificationBuilder: details,
        startupBuilder: (_, _) => const Scaffold(body: Text('Splash')),
      ),
    );
    NotificationService.tapNotifier.value = 'offer';
    await tester.pumpAndSettle();
    expect(find.text('offer|cold=true'), findsOneWidget);
    expect(find.text('Splash'), findsNothing);
    expect(navigatorKey.currentState!.canPop(), false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'warm taps work without a feed listener and do not open duplicates',
    (tester) async {
      await tester.pumpWidget(
        PromoViewerApp(
          notificationBuilder: details,
          startupBuilder: (_, onFinished) {
            onFinished();
            return const Scaffold(body: Text('Settings'));
          },
        ),
      );
      NotificationService.tapNotifier.value = 'offer';
      await tester.pumpAndSettle();
      expect(find.text('offer|cold=false'), findsOneWidget);
      NotificationService.tapNotifier.value = 'offer';
      await tester.pumpAndSettle();
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(navigatorKey.currentState!.canPop(), false);
      NotificationService.tapNotifier.value = 'offer';
      await tester.pumpAndSettle();
      expect(find.text('offer|cold=false'), findsOneWidget);
      expect(NotificationService.tapNotifier.value, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'acknowledging an older tap preserves a newer persisted notification',
    () async {
      await NotificationService.storePendingPromoId('old');
      final save = NotificationService.storePendingPromoId('new');
      await NotificationService.acknowledgePromoTap('old');
      await save;
      expect(await NotificationService.consumePendingPromoId(), 'new');
      expect(await NotificationService.consumePendingPromoId(), isNull);
    },
  );

  test(
    'a queued tap is persisted, dispatched, and cleared after handling',
    () async {
      await NotificationService.queuePromoTap('offer');
      expect(NotificationService.tapNotifier.value, 'offer');
      expect(NotificationService.pendingPromoId, 'offer');
      await NotificationService.acknowledgePromoTap('offer');
      expect(NotificationService.tapNotifier.value, isNull);
      expect(await NotificationService.consumePendingPromoId(), isNull);
    },
  );

  test('iOS scene launch ID is read through the native bridge', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const channel = MethodChannel('com.jeeven.candy/notification_launch');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getInitialPromoId');
      return 'scene_offer';
    });
    try {
      expect(await NotificationService.nativeLaunchPromoId(), 'scene_offer');
    } finally {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
}
