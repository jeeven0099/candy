class FastRedemption {
  final bool eligible;
  final String actionType;
  final String buttonLabel;
  final String? primaryValue;
  final String? primaryUrl;
  final String? appDeepLink;
  final String? webFallbackUrl;
  final List<String> stepsAfterClick;
  final List<String> eliminatesSteps;
  final String effortLevel;
  final double confidence;

  const FastRedemption({
    required this.eligible,
    required this.actionType,
    required this.buttonLabel,
    this.primaryValue,
    this.primaryUrl,
    this.appDeepLink,
    this.webFallbackUrl,
    this.stepsAfterClick = const [],
    this.eliminatesSteps = const [],
    this.effortLevel = 'high',
    this.confidence = 0.0,
  });

  factory FastRedemption.fromJson(Map<String, dynamic> j) => FastRedemption(
        eligible: j['eligible'] as bool? ?? false,
        actionType: j['action_type'] as String? ?? 'not_supported',
        buttonLabel: j['button_label'] as String? ?? '',
        primaryValue: j['primary_value'] as String?,
        primaryUrl: j['primary_url'] as String?,
        appDeepLink: j['app_deep_link'] as String?,
        webFallbackUrl: j['web_fallback_url'] as String?,
        stepsAfterClick:
            (j['steps_after_click'] as List<dynamic>?)?.cast<String>() ?? [],
        eliminatesSteps:
            (j['eliminates_steps'] as List<dynamic>?)?.cast<String>() ?? [],
        effortLevel: j['effort_level'] as String? ?? 'high',
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0.0,
      );

  bool get isLowEffort => effortLevel == 'low';
}
