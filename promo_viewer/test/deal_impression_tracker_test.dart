import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:promo_viewer/widgets/deal_impression_tracker.dart';

void main() {
  setUp(
    () => VisibilityDetectorController.instance.updateInterval = Duration.zero,
  );

  Widget fixture({
    required Future<bool> Function() record,
    bool active = true,
    String trackingKey = 'user|for_you|email|deal',
  }) => MaterialApp(
    home: Scaffold(
      body: DealImpressionTracker(
        trackingKey: trackingKey,
        active: active,
        onImpression: record,
        child: const SizedBox(width: 200, height: 100, child: Text('Offer')),
      ),
    ),
  );

  testWidgets('records only after one second and only once', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      fixture(
        record: () async {
          calls++;
          return true;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('inactive tab does not count as viewed', (tester) async {
    var calls = 0;
    Future<bool> record() async {
      calls++;
      return true;
    }

    await tester.pumpWidget(fixture(record: record, active: false));
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 0);
    await tester.pumpWidget(fixture(record: record));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving before the dwell threshold cancels the view', (
    tester,
  ) async {
    var calls = 0;
    Future<bool> record() async {
      calls++;
      return true;
    }

    await tester.pumpWidget(fixture(record: record));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(fixture(record: record, active: false));
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a changed user/deal gets its own exposure', (tester) async {
    var calls = 0;
    Future<bool> record() async {
      calls++;
      return true;
    }

    await tester.pumpWidget(fixture(record: record));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(calls, 1);
    await tester.pumpWidget(
      fixture(record: record, trackingKey: 'other-user|deal'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed write can retry on a later appearance', (tester) async {
    var calls = 0;
    Future<bool> record() async {
      calls++;
      return calls > 1;
    }

    await tester.pumpWidget(fixture(record: record));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(calls, 1);
    await tester.pumpWidget(fixture(record: record, active: false));
    await tester.pumpWidget(fixture(record: record));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('backgrounding cancels the view until the app resumes', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      fixture(
        record: () async {
          calls++;
          return true;
        },
      ),
    );
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a covered feed does not record a pending view', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      fixture(
        record: () async {
          calls++;
          return true;
        },
      ),
    );
    await tester.pump();
    final context = tester.element(find.text('Offer'));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Detail')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
