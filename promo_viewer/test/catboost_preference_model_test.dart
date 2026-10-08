import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/utils/catboost_preference_model.dart';
import 'package:promo_viewer/utils/preference_features.dart';

Map<String, dynamic> testModel() => {
  'schema_version': 1,
  'format': 'catboost_numeric_v1',
  'validated': true,
  'version': 'test_only',
  'prior': 0.5,
  'feature_names': preferenceFeatureNames,
  'trees': [
    {
      'splits': [
        {'feature': 15, 'border': 0},
      ],
      'leaves': [-2.0, 2.0],
    },
  ],
};

void main() {
  test('CatBoost float splits add a bounded learned preference adjustment', () {
    final model = CatBoostPreferenceModel.parse(testModel())!;
    final features = {for (final f in preferenceFeatureNames) f: 0.0};
    features['total_evidence'] = 1;
    features['brand_preference'] = 0.4;
    expect(model.adjustment(features), greaterThan(0));
    expect(model.adjustment(features).abs(), lessThanOrEqualTo(6));
    features['brand_preference'] = -0.4;
    expect(model.adjustment(features), lessThan(0));
  });
  test('new users get zero adjustment and sparse users get a smaller one', () {
    final model = CatBoostPreferenceModel.parse(testModel())!;
    final features = {for (final f in preferenceFeatureNames) f: 0.0};
    expect(model.adjustment(features), 0);
    features['total_evidence'] = 0.05;
    final sparse = model.adjustment(features).abs();
    features['total_evidence'] = 1;
    expect(sparse, lessThan(model.adjustment(features).abs()));
  });
  test('rejects unvalidated, incompatible, malformed, or oversized trees', () {
    expect(
      CatBoostPreferenceModel.parse({...testModel(), 'validated': false}),
      isNull,
    );
    expect(
      CatBoostPreferenceModel.parse({...testModel(), 'schema_version': 2}),
      isNull,
    );
    expect(
      CatBoostPreferenceModel.parse({
        ...testModel(),
        'feature_names': ['bad'],
      }),
      isNull,
    );
    expect(
      CatBoostPreferenceModel.parse({...testModel(), 'trees': []}),
      isNull,
    );
    expect(
      CatBoostPreferenceModel.parse({
        ...testModel(),
        'trees': [
          {
            'splits': [],
            'leaves': [double.nan],
          },
        ],
      }),
      isNull,
    );
    expect(
      CatBoostPreferenceModel.parse({
        ...testModel(),
        'trees': [
          {
            'splits': [
              {'feature': 100, 'border': 0},
            ],
            'leaves': [0, 1],
          },
        ],
      }),
      isNull,
    );
  });
  test('missing inputs fall back to the model prior, not a guessed branch', () {
    final model = CatBoostPreferenceModel.parse(testModel())!;
    expect(model.probability({}), model.prior);
  });
  test('mobile inference matches an actual CatBoost-generated fixture', () {
    final fixture = jsonDecode(
      File('test/fixtures/catboost_numeric.json').readAsStringSync(),
    );
    final model = CatBoostPreferenceModel.parse(
      Map<String, dynamic>.from(fixture['artifact']),
    )!;
    for (final sample in fixture['samples']) {
      final features = (sample['features'] as Map).map(
        (key, value) => MapEntry(key as String, (value as num).toDouble()),
      );
      expect(
        model.probability(features),
        closeTo(sample['probability'] as double, 1e-6),
      );
    }
  });
}
