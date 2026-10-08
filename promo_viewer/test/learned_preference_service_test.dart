import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/models/promotion.dart';
import 'package:promo_viewer/services/learned_preference_service.dart';
import 'package:promo_viewer/utils/preference_features.dart';

void main() {
  final p = Promotion.fromJson({
    'brand': 'Example',
    'category': 'retail',
    'promotion_title': 'new',
  });
  Map<String, dynamic> feedback(int sequence) => {
    'promotion_id': 'old_$sequence',
    'event_type': 'not_interested',
    'brand': 'Example',
    'category': 'retail',
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'metadata': {'event_sequence': sequence},
  };
  Map<String, dynamic> artifact() => {
    'schema_version': 1,
    'format': 'catboost_numeric_v1',
    'validated': true,
    'version': 'test_only',
    'prior': 0.5,
    'feature_names': preferenceFeatureNames,
    'trees': [
      {
        'splits': [],
        'leaves': [-2.0],
      },
    ],
  };

  test(
    'missing backend model falls back without discarding feedback',
    () async {
      final service = LearnedPreferenceService.forTesting(
        currentAccount: () => 'a',
        feedbackLoader: (_) async => [feedback(1)],
        modelLoader: () async => null,
      );
      await service.loadForCurrentUser('db-a');
      expect(service.modelVersion, isNull);
      expect(service.features(p)['brand_preference'], isNegative);
      expect(service.adjustment(p), 0);
    },
  );
  test(
    'a validated model applies after feedback and responds to new actions',
    () async {
      final service = LearnedPreferenceService.forTesting(
        currentAccount: () => 'a',
        feedbackLoader: (_) async => [feedback(1)],
        modelLoader: () async => artifact(),
      );
      await service.loadForCurrentUser('db-a');
      expect(service.modelVersion, 'test_only');
      final before = service.adjustment(p);
      service.record(feedback(2));
      expect(service.adjustment(p), lessThan(before));
    },
  );
  test('feedback during loading is merged and never counted twice', () async {
    final pending = Completer<List<Map<String, dynamic>>>();
    final service = LearnedPreferenceService.forTesting(
      currentAccount: () => 'a',
      feedbackLoader: (_) => pending.future,
      modelLoader: () async => artifact(),
    );
    final loading = service.loadForCurrentUser('db-a');
    final e = feedback(1);
    service.record(e);
    pending.complete([e]);
    await loading;
    expect(service.features(p)['brand_evidence'], closeTo(0.05, 0.001));
  });
  test(
    'switching accounts immediately removes previous learned state',
    () async {
      String? owner = 'a';
      final service = LearnedPreferenceService.forTesting(
        currentAccount: () => owner,
        feedbackLoader: (_) async => [feedback(1)],
        modelLoader: () async => artifact(),
      );
      await service.loadForCurrentUser('db-a');
      owner = 'b';
      expect(service.modelVersion, isNull);
      expect(service.adjustment(p), 0);
      expect(service.features(p)['total_evidence'], 0);
      owner = null;
      await service.loadForCurrentUser(null);
      expect(service.features(p)['total_evidence'], 0);
    },
  );
  test('stale account load cannot overwrite the new account model', () async {
    String? owner = 'a';
    final pending = Completer<List<Map<String, dynamic>>>();
    final service = LearnedPreferenceService.forTesting(
      currentAccount: () => owner,
      feedbackLoader: (uid) =>
          uid == 'db-a' ? pending.future : Future.value([]),
      modelLoader: () async => {...artifact(), 'version': 'b_model'},
    );
    final oldLoad = service.loadForCurrentUser('db-a');
    owner = 'b';
    await service.loadForCurrentUser('db-b');
    pending.complete([feedback(1)]);
    await oldLoad;
    expect(service.modelVersion, 'b_model');
    expect(service.features(p)['total_evidence'], 0);
  });
  test('backend failures cannot prevent an ordinary feed score', () async {
    final service = LearnedPreferenceService.forTesting(
      currentAccount: () => 'a',
      feedbackLoader: (_) async => throw StateError('offline'),
      modelLoader: () async => throw StateError('missing migration'),
    );
    await service.loadForCurrentUser('db-a');
    expect(service.adjustment(p), 0);
  });
}
