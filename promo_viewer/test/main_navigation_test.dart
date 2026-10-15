import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:promo_viewer/config.dart';
import 'package:promo_viewer/screens/main_screen.dart';
import 'package:promo_viewer/screens/profile_screen.dart';
import 'package:promo_viewer/screens/saved_screen.dart';
import 'package:promo_viewer/services/interaction_service.dart';
import 'package:promo_viewer/services/remote_data_service.dart';
import 'package:promo_viewer/services/saved_deals_service.dart';
import 'package:promo_viewer/widgets/deal_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'fixtures/reliable_offer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final screenshotDir = Platform.environment['CANDY_SWIPE_SCREENSHOT_DIR'];

  setUpAll(() async {
    for (final font in {
      'FeedbackPreview': Platform.environment['CANDY_BADGE_FONT'],
      'MaterialIcons': Platform.environment['CANDY_BADGE_ICON_FONT'],
    }.entries) {
      if (font.value == null) continue;
      final loader = FontLoader(font.key)
        ..addFont(
          Future.value(
            ByteData.sublistView(await File(font.value!).readAsBytes()),
          ),
        );
      await loader.load();
    }
  });

  setUp(() async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    SharedPreferences.setMockInitialValues({});
    await SavedDealsService.init();
    await InteractionService.init();
    await RemoteDataService.clearServerUrl();
    directory = Directory.systemTemp.createTempSync('candy-saved-navigation-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
  });

  tearDown(() async {
    for (var attempt = 0; ; attempt++) {
      try {
        await directory.delete(recursive: true);
        break;
      } on FileSystemException {
        if (attempt == 5) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  for (final width in [320.0, 1024.0]) {
    testWidgets('right swipe moves a deal to the Saved tab at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rows = [
        for (var i = 0; i < 50; i++)
          reliableOfferJson({
            'brand': i == 0 ? 'Nike' : 'Store $i',
            'website_domain': 'nike.com',
            'promotion_title': 'Offer $i',
            'global_quality_score': 95.0 - i / 10,
          }),
      ];
      final preview = GlobalKey();
      await tester.runAsync(() async {
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              RepaintBoundary(
                key: preview,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(
                    fontFamily: screenshotDir == null
                        ? null
                        : 'FeedbackPreview',
                  ),
                  home: const MainScreen(),
                ),
              ),
            );
            for (
              var i = 0;
              i < 40 && find.byType(DealCard).evaluate().isEmpty;
              i++
            ) {
              await Future<void>.delayed(const Duration(milliseconds: 50));
              await tester.pump();
            }
          },
          () => MockClient(
            (request) async => request.url.toString() == kConfigUrl
                ? http.Response(
                    jsonEncode({'server_url': 'https://example.com/assets'}),
                    200,
                  )
                : http.Response(jsonEncode({'promotions': rows}), 200),
          ),
        );
      });
      await tester.pumpAndSettle();
      for (final tab in ['For You', 'Near Me', 'Saved', 'Settings']) {
        expect(find.text(tab), findsWidgets);
      }
      await tester.drag(
        find.widgetWithText(DealCard, 'Offer 0'),
        Offset(width * 0.8, 0),
      );
      await tester.pumpAndSettle();
      expect(SavedDealsService().all, hasLength(1));
      expect(InteractionService().isDealSkipped('nike_offer_0'), isFalse);
      await tester.tap(find.text('Saved').last);
      await tester.pumpAndSettle();
      expect(find.byType(SavedScreen), findsOneWidget);
      expect(find.widgetWithText(DealCard, 'Offer 0'), findsOneWidget);
      if (screenshotDir != null) {
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/logos/nike.com.png'),
            tester.element(find.byType(DealCard)),
          ),
        );
        await tester.pumpAndSettle();
        final boundary =
            preview.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$screenshotDir/saved_${width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.byTooltip('Remove from Saved'));
      await tester.pumpAndSettle();
      expect(find.text('No saved deals'), findsOneWidget);
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('Gmail Deals'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
