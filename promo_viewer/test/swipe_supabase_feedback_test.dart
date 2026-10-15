import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:promo_viewer/models/promotion.dart';
import 'package:promo_viewer/services/auth_service.dart';
import 'package:promo_viewer/services/interaction_service.dart';
import 'package:promo_viewer/services/saved_deals_service.dart';
import 'package:promo_viewer/services/supabase_service.dart';
import 'package:promo_viewer/services/user_prefs_service.dart';
import 'package:promo_viewer/utils/deal_feed_feedback.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/reliable_offer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const account = '11111111-1111-4111-8111-111111111111';
  const profile = '22222222-2222-4222-8222-222222222222';
  final events = <Map<String, dynamic>>[];
  final saves = <(String, Map<String, dynamic>)>[];
  Completer<http.Response>? pendingSave;

  String token() {
    String part(Object data) =>
        base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
    return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': account, 'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.test-signature';
  }

  Future<void> waitUntil(bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue);
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path == '/auth/v1/signup') {
        return http.Response(
          jsonEncode({
            'access_token': token(),
            'refresh_token': 'mock-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': account,
              'aud': 'authenticated',
              'email': 'beta@example.test',
              'app_metadata': {'provider': 'email'},
              'user_metadata': {},
              'created_at': '2026-10-01T12:00:00Z',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      if (request.method == 'GET' && path == '/rest/v1/users') {
        return http.Response(
          jsonEncode([
            {'id': profile, 'radius_miles': 5},
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      if (request.method == 'GET' && path == '/rest/v1/user_preferences') {
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      if (path == '/rest/v1/user_interactions') {
        events.add(Map<String, dynamic>.from(jsonDecode(request.body)));
      }
      if (path == '/rest/v1/saved_deals') {
        if (request.method == 'PATCH') {
          expect(request.url.queryParameters['user_id'], 'eq.$profile');
        }
        saves.add((
          request.method,
          Map<String, dynamic>.from(jsonDecode(request.body)),
        ));
        if (request.method == 'POST' && pendingSave != null) {
          final response = await pendingSave!.future;
          return http.Response(
            response.body,
            response.statusCode,
            request: request,
          );
        }
      }
      return http.Response('', 201, request: request);
    });
    await http.runWithClient(() async {
      await SupabaseService.init();
      expect(SupabaseService.isReady, isTrue);
      await AuthService.signUp(
        email: 'beta@example.test',
        password: 'MockBetaPassword123',
      );
      await UserPrefsService().load();
    }, () => client);
    expect(UserPrefsService().userId, profile);
    await SavedDealsService.init();
    await InteractionService.init();
  });

  tearDownAll(() async {
    await Supabase.instance.dispose();
  });

  test(
    'right swipe emits one positive snapshot and Undo orders saved-row writes',
    () async {
      final offer = Promotion.fromJson(reliableOfferJson({}));
      pendingSave = Completer<http.Response>();
      final undo = await recordDealFeedFeedback(
        offer,
        position: 3,
        rankingMode: 'for_you',
        action: DealFeedAction.save,
        swipeDirection: 'right',
      );
      await waitUntil(
        () =>
            saves.isNotEmpty &&
            events.any((event) => event['event_type'] == 'deal_saved'),
      );
      await undo();
      await waitUntil(
        () => events.any((event) => event['event_type'] == 'deal_unsaved'),
      );
      expect(saves.map((request) => request.$1), ['POST']);
      pendingSave!.complete(http.Response('', 201));
      await waitUntil(() => saves.length == 2);
      expect(saves.map((request) => request.$1), ['POST', 'PATCH']);
      expect(
        saves.every(
          (request) =>
              request.$2['user_id'] == profile || request.$1 == 'PATCH',
        ),
        isTrue,
      );
      expect(saves.last.$2['status'], 'deleted');
      final positive = events
          .where((event) => event['event_type'] == 'deal_saved')
          .single;
      expect(positive['user_id'], profile);
      final metadata = positive['metadata'] as Map;
      expect(metadata['swipe_direction'], 'right');
      expect(metadata['feedback_action'], 'save');
      expect(metadata['feedback_method'], 'swipe');
      expect(metadata['feed_position'], 3);
      expect(metadata['offer_features'], isA<Map>());
      expect(metadata['preference_features'], isA<Map>());
      expect(
        events.where((event) => event['event_type'] == 'not_interested'),
        isEmpty,
      );
    },
  );

  test(
    'left swipe emits a negative snapshot without saving the deal',
    () async {
      final offer = Promotion.fromJson(
        reliableOfferJson({'promotion_title': 'A different offer'}),
      );
      final before = saves.length;
      final undo = await recordDealFeedFeedback(
        offer,
        position: 4,
        rankingMode: 'near_me',
        action: DealFeedAction.dismiss,
        swipeDirection: 'left',
      );
      await waitUntil(
        () => events.any((event) => event['event_type'] == 'not_interested'),
      );
      final negative = events
          .where((event) => event['event_type'] == 'not_interested')
          .single;
      expect(negative['user_id'], profile);
      expect(negative['metadata']['swipe_direction'], 'left');
      expect(negative['metadata']['feedback_action'], 'dismiss');
      expect(negative['metadata']['preference_features'], isA<Map>());
      expect(SavedDealsService().isSaved(offer.id), isFalse);
      await undo();
      await waitUntil(
        () => events.any(
          (event) => event['event_type'] == 'not_interested_undone',
        ),
      );
      expect(saves.length, before);
    },
  );
}
