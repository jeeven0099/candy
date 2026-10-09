import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/models/promotion.dart';
import 'package:promo_viewer/services/notification_deal_resolver.dart';
import 'package:promo_viewer/services/promotions_service.dart';

Map<String, dynamic> offer(
  String title, {
  String brand = 'Target',
  double quality = 80,
}) => {
  'brand': brand,
  'promotion_title': title,
  'global_quality_score': quality,
};

String catalog(List<Map<String, dynamic>> offers) =>
    jsonEncode({'promotions': offers});

void main() {
  setUp(() => PromotionsService.cached = []);
  tearDown(() => PromotionsService.cached = []);

  test('matches push IDs with trailing punctuation and legacy app IDs', () {
    final promo = Promotion.fromJson(offer('Save 50%!'));
    expect(promo.id, 'target_save_50_');
    expect(NotificationDealResolver.matches(promo, 'target_save_50'), true);
    expect(NotificationDealResolver.matches(promo, promo.id), true);
    expect(NotificationDealResolver.matches(promo, 'another_deal'), false);
  });

  test(
    'trims before truncating long push IDs, including leading punctuation',
    () {
      final title = List.filled(30, 'discount').join(' ');
      final promo = Promotion.fromJson(offer(title, brand: '!Target'));
      final pushId = 'target_${title.replaceAll(' ', '_')}'.substring(0, 100);
      expect(NotificationDealResolver.matches(promo, pushId), true);
    },
  );

  test('cached public deals resolve without I/O', () async {
    final promo = Promotion.fromJson(offer('Save 50%!'));
    PromotionsService.cached = [promo];
    final resolver = NotificationDealResolver(
      loadCatalog: (_) async => throw StateError('No I/O'),
    );
    expect(await resolver.resolve('target_save_50'), same(promo));
  });

  test(
    'notification lookup does not apply feed quality or dedup filtering',
    () async {
      final lowQuality = offer('Save 20%!', quality: 20);
      final resolver = NotificationDealResolver(
        loadCatalog: (_) async => catalog([lowQuality]),
      );
      final promo = await resolver.resolve('target_save_20');
      expect(promo?.title, 'Save 20%!');
      expect(promo?.globalQualityScore, 20);
      expect(PromotionsService.cached, isEmpty);
    },
  );

  test('missing ID bypasses TTL and checks the refreshed catalog', () async {
    final reads = <bool>[];
    final resolver = NotificationDealResolver(
      loadCatalog: (refresh) async {
        reads.add(refresh);
        return catalog(refresh ? [offer('New offer!')] : []);
      },
    );
    expect((await resolver.resolve('target_new_offer'))?.title, 'New offer!');
    expect(reads, [false, true]);
  });

  test(
    'removed deal returns unavailable after checking both catalogs',
    () async {
      final reads = <bool>[];
      final resolver = NotificationDealResolver(
        loadCatalog: (refresh) async {
          reads.add(refresh);
          return catalog([]);
        },
      );
      expect(await resolver.resolve('missing'), isNull);
      expect(reads, [false, true]);
    },
  );
}
