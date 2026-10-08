import 'dart:math' as math;
import 'dart:typed_data';

import 'preference_features.dart';

/// Inference-only representation compiled from CatBoost's numeric JSON export.
/// No categorical CTRs, training code, or native iOS dependency is shipped.
class CatBoostPreferenceModel {
  final String version;
  final double prior;
  final List<Map<String, dynamic>> _trees;

  CatBoostPreferenceModel._(this.version, this.prior, this._trees);

  static CatBoostPreferenceModel? parse(Map<String, dynamic> artifact) {
    try {
      if (artifact['schema_version'] != preferenceFeatureVersion ||
          artifact['validated'] != true ||
          artifact['format'] != 'catboost_numeric_v1') {
        return null;
      }
      final names = artifact['feature_names'] as List;
      if (names.length != preferenceFeatureNames.length) return null;
      for (var i = 0; i < names.length; i++) {
        if (names[i] != preferenceFeatureNames[i]) return null;
      }
      final version = artifact['version'] as String;
      final prior = (artifact['prior'] as num).toDouble();
      if (version.isEmpty ||
          version.length > 100 ||
          !prior.isFinite ||
          prior <= 0 ||
          prior >= 1) {
        return null;
      }
      final trees = (artifact['trees'] as List)
          .map((t) => Map<String, dynamic>.from(t as Map))
          .toList();
      if (trees.isEmpty || trees.length > 300) return null;
      for (final tree in trees) {
        final splits = tree['splits'] as List;
        final leaves = tree['leaves'] as List;
        if (splits.length > 6 || leaves.length != 1 << splits.length) {
          return null;
        }
        for (final split in splits) {
          final index = split['feature'];
          final border = split['border'];
          if (index is! int ||
              index < 0 ||
              index >= names.length ||
              border is! num ||
              !border.isFinite) {
            return null;
          }
        }
        if (leaves.any((n) => n is! num || !n.isFinite)) return null;
      }
      return CatBoostPreferenceModel._(version, prior, trees);
    } catch (_) {
      return null;
    }
  }

  double probability(Map<String, double> features) {
    final values = Float32List(preferenceFeatureNames.length);
    for (var i = 0; i < values.length; i++) {
      final value = features[preferenceFeatureNames[i]];
      if (value == null || !value.isFinite) return prior;
      values[i] = value;
    }
    double score = 0;
    for (final tree in _trees) {
      var leaf = 0;
      final splits = tree['splits'] as List;
      for (var bit = 0; bit < splits.length; bit++) {
        final split = splits[bit];
        final value = values[split['feature'] as int];
        if (value > (split['border'] as num).toDouble()) leaf |= 1 << bit;
      }
      score += (tree['leaves'][leaf] as num).toDouble();
    }
    return 1 / (1 + math.exp(-score.clamp(-40, 40)));
  }

  double adjustment(Map<String, double> features) {
    // Shrink sparse-user adjustments; quality gates remain outside the model.
    final evidence = ((features['total_evidence'] ?? 0) * 2).clamp(0.0, 1.0);
    return ((probability(features) - prior) * 12 * evidence).clamp(-6.0, 6.0);
  }
}
