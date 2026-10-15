import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:promo_viewer/config.dart';
import 'package:promo_viewer/services/remote_data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const server = 'https://example.com/catalog';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = Directory.systemTemp.createTempSync('candy-beta-cache-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    await RemoteDataService.clearServerUrl();
  });

  tearDown(() async {
    await RemoteDataService.clearServerUrl();
    directory.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  test(
    'upgrade ignores the old catalog and broken server URL caches',
    () async {
      final legacy = Directory('${directory.path}/rds_cache')..createSync();
      File('${legacy.path}/all_promotions.json').writeAsStringSync('legacy');
      File(
        '${legacy.path}/all_promotions.json.ts',
      ).writeAsStringSync('${DateTime.now().millisecondsSinceEpoch}');
      SharedPreferences.setMockInitialValues({
        '_rds_server_url': 'https://example.com/broken-main',
        '_rds_server_url_ts': DateTime.now().millisecondsSinceEpoch,
      });
      final requests = <Uri>[];
      final result = await http.runWithClient(
        () => RemoteDataService.load('all_promotions.json'),
        () => MockClient((request) async {
          requests.add(request.url);
          return request.url.toString() == kConfigUrl
              ? http.Response(jsonEncode({'server_url': server}), 200)
              : http.Response('current', 200);
        }),
      );
      expect(result, 'current');
      expect(requests.map((uri) => uri.toString()), [
        kConfigUrl,
        '$server/all_promotions.json',
      ]);
    },
  );

  test('force refresh bypasses a fresh catalog cache', () async {
    var downloads = 0;
    await http.runWithClient(
      () async {
        expect(
          await RemoteDataService.load('all_promotions.json'),
          'catalog-1',
        );
        expect(
          await RemoteDataService.load('all_promotions.json'),
          'catalog-1',
        );
        expect(
          await RemoteDataService.load(
            'all_promotions.json',
            forceRefresh: true,
          ),
          'catalog-2',
        );
      },
      () => MockClient((request) async {
        if (request.url.toString() == kConfigUrl) {
          return http.Response(jsonEncode({'server_url': server}), 200);
        }
        return http.Response('catalog-${++downloads}', 200);
      }),
    );
    expect(downloads, 2);
  });

  test(
    'fresh install falls back to bundled data if bootstrap is unavailable',
    () async {
      final result = await http.runWithClient(
        () => RemoteDataService.load('all_promotions.json'),
        () => MockClient((_) async => http.Response('', 404)),
      );
      final data = jsonDecode(result) as Map<String, dynamic>;
      expect(data['promotions'], isNotEmpty);
      expect(
        (data['promotions'] as List).every(
          (row) => row['source_evidence'] is Map,
        ),
        isTrue,
      );
    },
  );
}
