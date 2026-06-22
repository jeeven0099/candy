import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class TimezoneService {
  static bool _initialized = false;
  static String _deviceTzName = 'America/New_York';

  static Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    if (!kIsWeb) {
      try {
        final tzInfo = await FlutterTimezone.getLocalTimezone();
        _deviceTzName = tzInfo.identifier;
      } catch (_) {}
    }
    try {
      tz.setLocalLocation(tz.getLocation(_deviceTzName));
    } catch (_) {}
    _initialized = true;
  }

  static String get deviceTimezoneName => _deviceTzName;

  /// Convert a "HH:mm" time string from [fromTz] to the device's local timezone.
  /// Returns the converted time string, or the original if conversion fails.
  static String convertTime(String time24, String fromTzName) {
    if (!_initialized) return time24;
    try {
      final parts = time24.split(':');
      if (parts.length < 2) return time24;
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      final fromTz = tz.getLocation(fromTzName);
      final deviceTz = tz.getLocation(_deviceTzName);

      final now = tz.TZDateTime.now(fromTz);
      final inSourceTz = tz.TZDateTime(fromTz, now.year, now.month, now.day, hour, minute);
      final inDeviceTz = tz.TZDateTime.from(inSourceTz, deviceTz);

      final h = inDeviceTz.hour.toString().padLeft(2, '0');
      final m = inDeviceTz.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return time24;
    }
  }

  /// Format "HH:mm" as "9:00 AM" style.
  static String formatTime(String time24) {
    try {
      final parts = time24.split(':');
      var hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;
      return '$hour:${minute.toString().padLeft(2, '0')} $period';
    } catch (_) {
      return time24;
    }
  }

  /// Short timezone abbreviation for display (e.g. "ET", "CT", "PT").
  static String tzAbbr(String ianaName) {
    const map = {
      'America/New_York':    'ET',
      'America/Chicago':     'CT',
      'America/Denver':      'MT',
      'America/Phoenix':     'MT',
      'America/Los_Angeles': 'PT',
      'America/Anchorage':   'AKT',
      'Pacific/Honolulu':    'HT',
    };
    return map[ianaName] ?? ianaName.split('/').last.replaceAll('_', ' ');
  }
}
