class SourceEvidence {
  final int? schemaVersion;
  final String? validator;
  final String? status;
  final String? sourceUrl;
  final String? checkedAt;
  final String? excerpt;
  final Map<String, dynamic> offer;

  SourceEvidence.fromJson(Map<String, dynamic> json)
    : schemaVersion = json['schema_version'] is int
          ? json['schema_version'] as int
          : null,
      validator = json['validator'] is String
          ? json['validator'] as String
          : null,
      status = json['status'] is String ? json['status'] as String : null,
      sourceUrl = json['source_url'] is String
          ? json['source_url'] as String
          : null,
      checkedAt = json['checked_at'] is String
          ? json['checked_at'] as String
          : null,
      excerpt = json['excerpt'] is String ? json['excerpt'] as String : null,
      offer = json['offer'] is Map<String, dynamic>
          ? Map.unmodifiable(json['offer'] as Map<String, dynamic>)
          : const {};

  bool matchesOffer(Map<String, dynamic> snapshot) => snapshot.entries.every((
    entry,
  ) {
    if (!offer.containsKey(entry.key)) return false;
    final value = offer[entry.key];
    if (value is List && entry.value is List) {
      final expected = entry.value as List;
      return value.length == expected.length &&
          Iterable.generate(value.length).every((i) => value[i] == expected[i]);
    }
    return value == entry.value;
  });
}
