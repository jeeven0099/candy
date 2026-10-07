import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:promo_viewer/models/promotion.dart';
import 'package:promo_viewer/screens/for_you_screen.dart';
import 'package:promo_viewer/screens/near_me_screen.dart';
import 'package:promo_viewer/services/interaction_service.dart';
import 'package:promo_viewer/services/user_prefs_service.dart';
import 'package:promo_viewer/widgets/deal_card.dart';

void main() {
  final screenshotDir = Platform.environment['CANDY_FEED_SCREENSHOT_DIR'];
  setUpAll(() async {
    if (screenshotDir == null) return;
    for (final entry in {
      'FeedbackPreview': Platform.environment['CANDY_BADGE_FONT'],
      'MaterialIcons': Platform.environment['CANDY_BADGE_ICON_FONT'],
    }.entries) {
      if (entry.value == null) continue;
      final bytes = await File(entry.value!).readAsBytes();
      final loader = FontLoader(entry.key)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
  var scenario = 0;
  setUp(() async {
    scenario++;
    SharedPreferences.setMockInitialValues({});
    await InteractionService.init();
    UserPrefsService().clear();
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  List<Promotion> offers() => List.generate(50, (i) {
    final p = Promotion.fromJson({
      'brand': i == 0 ? 'Nike $scenario' : 'Example Store $scenario $i',
      'website_domain': i == 0 ? 'nike.com' : null,
      'promotion_title': 'Offer $i',
      'source': i == 0 ? 'email' : 'web',
      'status': 'active',
      'confidence_score': 0.9,
      'global_quality_score': 95.0 - i / 10,
      'personal_rank_score': i == 0 ? 85.0 : null,
      'discount_type': 'percentage_off',
      'economic_value_score': 60.0,
      'redemption_method': 'in_store',
      'deal_scope': 'in_store_only',
    });
    p.distanceKm = 0.5;
    return p;
  });

  Widget screen(List<Promotion> all, bool nearby, {bool active = true}) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: screenshotDir == null ? null : 'FeedbackPreview',
        ),
        home: nearby
            ? NearMeScreen(
                all: all,
                active: active,
                locating: false,
                position: Position(
                  latitude: 41.8,
                  longitude: -87.6,
                  timestamp: DateTime.now(),
                  accuracy: 0,
                  altitude: 0,
                  altitudeAccuracy: 0,
                  heading: 0,
                  headingAccuracy: 0,
                  speed: 0,
                  speedAccuracy: 0,
                ),
                onRefresh: () async {},
              )
            : ForYouScreen(all: all, active: active, onRefresh: () async {}),
      );

  for (final nearby in [false, true]) {
    final feed = nearby ? 'Near Me' : 'For You';
    for (final width in [390.0, 1024.0]) {
      testWidgets('$feed card shows Email and replaces swipes at width $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final all = offers();
        final previewKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: previewKey, child: screen(all, nearby)),
        );
        await tester.pumpAndSettle();
        if (screenshotDir != null) {
          await tester.runAsync(() async {
            await precacheImage(
              const AssetImage('assets/logos/nike.com.png'),
              tester.element(find.byType(DealCard).first),
            );
          });
          await tester.pumpAndSettle();
          final boundary =
              previewKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$screenshotDir/${nearby ? 'near_me' : 'for_you'}_${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(find.text('Email'), findsOneWidget);
        expect(find.byIcon(Icons.mail_outline), findsOneWidget);
        expect(
          find.text(nearby ? '10 nearby deals' : '10 best deals'),
          findsOneWidget,
        );
        final card = find.widgetWithText(DealCard, 'Offer 0');
        expect(card, findsOneWidget);
        final dx = width * (nearby ? -0.7 : 0.7);
        await tester.drag(card, Offset(dx, 0));
        await tester.pumpAndSettle();
        expect(InteractionService().isDealSkipped(all.first.id), isTrue);
        expect(find.text('Offer 0'), findsNothing);
        expect(find.text('Offer 10'), findsOneWidget);
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(InteractionService().isDealSkipped(all.first.id), isFalse);
        expect(find.text('Offer 0'), findsOneWidget);
        expect(find.text('Offer 10'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('$feed menu dismissal shares the swipe replacement path', (
      tester,
    ) async {
      final all = offers();
      await tester.pumpWidget(screen(all, nearby));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not interested in this deal'));
      await tester.pumpAndSettle();
      expect(find.text('Offer 0'), findsNothing);
      expect(find.text('Offer 10'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Offer 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$feed does not count hidden or reserve cards as seen', (
      tester,
    ) async {
      final all = offers();
      await tester.pumpWidget(screen(all, nearby, active: false));
      await tester.pump(const Duration(seconds: 2));
      expect(InteractionService().seenCount(all.first.id), 0);
      expect(InteractionService().seenCount(all[10].id), 0);
      await tester.pumpWidget(screen(all, nearby));
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump();
      expect(InteractionService().seenCount(all.first.id), 1);
      expect(InteractionService().seenCount(all[10].id), 0);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
