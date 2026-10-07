import 'dart:async';

import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

class DealImpressionTracker extends StatefulWidget {
  final String trackingKey;
  final bool active;
  final Future<bool> Function() onImpression;
  final Widget child;

  const DealImpressionTracker({
    super.key,
    required this.trackingKey,
    required this.active,
    required this.onImpression,
    required this.child,
  });

  @override
  State<DealImpressionTracker> createState() => _DealImpressionTrackerState();
}

class _DealImpressionTrackerState extends State<DealImpressionTracker>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _visible = false;
  bool _recorded = false;
  bool _writing = false;
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _resumed = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didUpdateWidget(covariant DealImpressionTracker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackingKey != widget.trackingKey) {
      _timer?.cancel();
      _visible = false;
      _recorded = false;
    }
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _schedule();
  }

  void _schedule() {
    if (!_visible || !widget.active || !_resumed) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_recorded || _writing || (_timer?.isActive ?? false)) return;
    final key = widget.trackingKey;
    _timer = Timer(const Duration(seconds: 1), () async {
      _timer = null;
      if (!mounted ||
          !_visible ||
          !widget.active ||
          !_resumed ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      _writing = true;
      try {
        final recorded = await widget.onImpression();
        if (mounted && widget.trackingKey == key) _recorded = recorded;
      } catch (_) {
        // Telemetry must not interrupt scrolling or deal actions.
      } finally {
        _writing = false;
        if (mounted && widget.trackingKey != key) _schedule();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VisibilityDetector(
    key: ValueKey(widget.trackingKey),
    onVisibilityChanged: (info) {
      if (info.key != ValueKey(widget.trackingKey)) return;
      _visible = info.visibleFraction >= 0.5;
      _schedule();
    },
    child: widget.child,
  );
}
