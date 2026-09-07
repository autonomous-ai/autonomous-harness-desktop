import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'analytics.dart';
import 'analytics_client.dart';
import 'analytics_config.dart';
import 'analytics_event.dart';
import 'analytics_identity.dart';

/// Who is signed in, asked fresh at track time — a session that starts signed
/// out and ends signed in must not report the whole visit as anonymous.
typedef AnalyticsUserLookup = ({String? id, String? email}) Function();

/// [Analytics] that queues in memory and sends serially, with retry.
///
/// Autonomous Analytics takes one event per request, so this is a queue with a
/// worker rather than a batcher. The order of the three failure paths is the
/// point: a **transport** failure keeps the event and backs off, a **refusal**
/// drops it (resending changes nothing), and a queue that grows past
/// `AnalyticsLimits.queueCap` drops its oldest — the newest events are the ones
/// that describe what is happening now.
///
/// Not persisted across launches: a machine quit while offline loses what was
/// still queued. That is a deliberate limit, not an oversight — the alternative
/// is a spool file that outlives an uninstall.
///
/// Ported from Grid, less its `AnalyticsLog` recorder: that exists to feed
/// Grid's Tracking tab, and this app has no such screen to feed.
class QueuedAnalytics implements Analytics {
  QueuedAnalytics({
    required this.client,
    required this.identityStore,
    required this.contextFuture,
    required this.userLookup,
    this.clock = DateTime.now,
  });

  /// The collaborators, public because they arrive through the constructor and
  /// a test that swaps one has no reason to reach past the door it came in by.
  /// Named apart from the locals they produce (`context`, the account) so a
  /// method body cannot quietly shadow one of them.
  final AnalyticsClient client;
  final AnalyticsIdentityStore identityStore;
  final Future<AnalyticsContext> contextFuture;
  final AnalyticsUserLookup userLookup;
  final DateTime Function() clock;

  final Queue<AnalyticsEvent> _queue = Queue<AnalyticsEvent>();

  AnalyticsContext? _resolvedContext;
  Future<void>? _draining;
  Timer? _retryTimer;
  Duration _retryDelay = AnalyticsLimits.retryDelay;
  bool _warnedFull = false;
  bool _closed = false;

  /// How many events are waiting to go out. Test seam, and the one honest
  /// answer to "did that call actually queue anything".
  @visibleForTesting
  int get pending => _queue.length;

  @override
  void track(String name, {Map<String, Object?> params = const {}}) {
    if (_closed) return;
    final now = clock();
    if (!analyticsEventNamePattern.hasMatch(name)) {
      debugPrint(
        'analytics: ignored event "$name" — '
        'names must be snake_case, 3-64 characters',
      );
      return;
    }
    try {
      final ids = identityStore.touch(now);
      final account = userLookup();
      _queue.add(
        AnalyticsEvent(
          name: name,
          params: params,
          at: now,
          identity: AnalyticsIdentity(
            pseudoId: ids.pseudoId,
            sessionId: ids.sessionId,
            userId: account.id,
            userEmail: account.email,
          ),
        ),
      );
      _trim();
      unawaited(_pump());
    } on Object catch (error) {
      debugPrint('analytics: dropped event "$name" — $error');
    }
  }

  @override
  Future<void> flush() {
    _cancelRetry();
    return _pump();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _cancelRetry();
    await _pump().timeout(AnalyticsLimits.closeDeadline, onTimeout: () {});
    _closed = true;
    client.dispose();
  }

  /// Drops the oldest events once the queue is over its cap, warning once per
  /// outage so a plane ride doesn't fill the log with the same line.
  void _trim() {
    if (_queue.length <= AnalyticsLimits.queueCap) return;
    while (_queue.length > AnalyticsLimits.queueCap) {
      _queue.removeFirst();
    }
    if (_warnedFull) return;
    _warnedFull = true;
    debugPrint(
      'analytics: event queue full (${AnalyticsLimits.queueCap}) — dropping '
      'the oldest; the endpoint has been unreachable for a while',
    );
  }

  /// One drain at a time: concurrent callers share the in-flight future rather
  /// than starting a second worker on the same queue.
  Future<void> _pump() {
    if (_closed || _queue.isEmpty) return Future.value();
    return _draining ??= _drain().whenComplete(() => _draining = null);
  }

  Future<void> _drain() async {
    final context = _resolvedContext ??= await contextFuture.catchError(
      (Object _) => AnalyticsContext.unknown,
    );
    while (_queue.isNotEmpty && !_closed) {
      final event = _queue.first;
      final AnalyticsSendResult result;
      try {
        result = await client.send(analyticsPayload(event, context));
      } on Object catch (error) {
        // The client's contract says it never throws; if it ever does, the
        // queue must not be left spinning on the same event forever.
        _queue.removeFirst();
        debugPrint('analytics: send failed for "${event.name}" — $error');
        continue;
      }
      switch (result) {
        case AnalyticsSendResult.sent:
          _queue.removeFirst();
          _retryDelay = AnalyticsLimits.retryDelay;
          _warnedFull = false;
        case AnalyticsSendResult.rejected:
          _queue.removeFirst();
          debugPrint(
            'analytics: server refused "${event.name}" — the event was dropped',
          );
        case AnalyticsSendResult.retry:
          _scheduleRetry();
          return;
      }
    }
  }

  void _scheduleRetry() {
    if (_retryTimer != null || _closed) return;
    _retryTimer = Timer(_retryDelay, () {
      _retryTimer = null;
      unawaited(_pump());
    });
    final doubled = _retryDelay * 2;
    _retryDelay = doubled > AnalyticsLimits.retryDelayMax
        ? AnalyticsLimits.retryDelayMax
        : doubled;
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}
