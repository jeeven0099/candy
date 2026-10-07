import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:promo_viewer/models/promotion.dart';
import 'package:promo_viewer/widgets/deal_source_badge.dart';

Promotion _promo(String source, {String brand = 'Example Store'}) =>
    Promotion.fromJson({'source': source, 'brand': brand});

void main() {
  for (final source in ['email', 'both', 'web', 'local_neighborhood']) {
    testWidgets('Email badge matches source=$source', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DealBrandLabel(promo: _promo(source))),
        ),
      );
      expect(
        find.text('Email'),
        source == 'email' || source == 'both' ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [110.0, 200.0, 440.0]) {
    testWidgets('Email and long brand fit a $width-pixel header', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DealBrandLabel(
                      promo: _promo(
                        'email',
                        brand: 'An Exceptionally Long Retail Brand Name',
                      ),
                    ),
                    const Text('0.4 mi away'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('0.4 mi away'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final badge = tester.getRect(find.text('Email'));
      final container = tester.getRect(find.byType(SizedBox).first);
      expect(badge.left, greaterThanOrEqualTo(container.left));
      expect(badge.right, lessThanOrEqualTo(container.right));
    });
  }

  testWidgets('badge renders at increased text scale', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SizedBox(
              width: 160,
              child: DealBrandLabel(promo: _promo('email')),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Email'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('write optional header screenshot', (tester) async {
    final output = Platform.environment['CANDY_BADGE_SCREENSHOT'];
    if (output == null) return;
    final fontPath = Platform.environment['CANDY_BADGE_FONT'];
    if (fontPath != null) {
      await tester.runAsync(() async {
        final bytes = await File(fontPath).readAsBytes();
        final loader = FontLoader('BadgePreview')
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
        final iconPath = Platform.environment['CANDY_BADGE_ICON_FONT'];
        if (iconPath != null) {
          final icons = await File(iconPath).readAsBytes();
          final iconLoader = FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(icons)));
          await iconLoader.load();
        }
      });
    }
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: fontPath == null ? null : 'BadgePreview'),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(20),
                color: Colors.white,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DealBrandLabel(promo: _promo('email')),
                    const SizedBox(height: 4),
                    const Text('0.4 mi away'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final screenshot = await boundary.toImage(pixelRatio: 2);
      final bytes = await screenshot.toByteData(format: ui.ImageByteFormat.png);
      await File(output).writeAsBytes(bytes!.buffer.asUint8List());
      screenshot.dispose();
    });
  });
}
