import 'dart:convert';
import 'dart:io';

import 'package:promo_viewer/models/promotion.dart';
import 'package:promo_viewer/utils/deal_reliability.dart';
import 'package:timezone/data/latest.dart' as tz;

void main(List<String> args) {
  if (args.length != 1 ||
      (!Directory(args.single).existsSync() &&
          !File(args.single).existsSync())) {
    stderr.writeln(
      'Usage: dart run tool/audit_deal_reliability.dart <catalog-file-or-directory>',
    );
    exitCode = 64;
    return;
  }
  tz.initializeTimeZones();
  final now = DateTime.now().toUtc();
  final reasons = <String, int>{};
  var total = 0;
  var supported = 0;
  var eligible = 0;
  var activeEligible = 0;
  var malformed = 0;
  final files = File(args.single).existsSync()
      ? [File(args.single)]
      : Directory(args.single).listSync().whereType<File>();
  for (final file in files) {
    if (!file.path.endsWith('.json')) continue;
    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final row in data['promotions'] as List) {
        total++;
        try {
          final offer = Promotion.fromJson(row as Map<String, dynamic>);
          if (offer.sourceEvidence?.status == 'supported') supported++;
          final assessment = assessDealReliability(offer, now: now);
          if (assessment.eligible) {
            eligible++;
            if (offer.isActive) activeEligible++;
          }
          for (final reason in assessment.reasons) {
            reasons.update(reason, (count) => count + 1, ifAbsent: () => 1);
          }
        } on TypeError {
          malformed++;
        } on FormatException {
          malformed++;
        }
      }
    } on TypeError {
      malformed++;
    } on FormatException {
      malformed++;
    } on FileSystemException {
      malformed++;
    }
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'checked_at': now.toIso8601String(),
      'offers': total,
      'source_supported': supported,
      'reliability_eligible': eligible,
      'active_and_reliability_eligible': activeEligible,
      'malformed_records_or_files': malformed,
      'exclusion_reasons': reasons,
    }),
  );
  if (total == 0 ||
      malformed > 0 ||
      reasons.containsKey('source_evidence_mismatch')) {
    exitCode = 1;
  }
}
