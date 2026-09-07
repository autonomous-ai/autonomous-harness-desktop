import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/analytics/analytics.dart';
import 'package:harness/analytics/analytics_client.dart';
import 'package:harness/analytics/analytics_config.dart';
import 'package:harness/analytics/analytics_event.dart';
import 'package:harness/analytics/analytics_identity.dart';
import 'package:harness/analytics/analytics_service.dart';

/// Records what it was asked to send and answers with a scripted result, so
/// every branch of the queue is reachable without a socket.
class FakeAnalyticsClient implements AnalyticsClient {
  FakeAnalyticsClient([this.answer = AnalyticsSendResult.sent]);

  AnalyticsSendResult answer;
  final List<Map<String, Object?>> sent = [];
  int disposed = 0;

  @override
  Future<AnalyticsSendResult> send(Map<String, Object?> payload) async {
    sent.add(payload);
    return answer;
  }

  @override
  void dispose() => disposed++;
}

/// The params list of a captured payload, flattened back to a map.
Map<String, Object?> paramsOf(Map<String, Object?> payload) {
  final data = payload['data']! as Map<String, Object?>;
  final entries = data['event_params']! as List<Map<String, Object?>>;
  return {for (final entry in entries) entry['key']! as String: entry['value']};
}

void main() {
  late Directory scratch;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('harness-analytics-test-');
  });

  tearDown(() async {
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  AnalyticsIdentityStore storeIn(Directory dir, {String? computerId}) {
    final computerIdFile = File('${dir.path}/computer-id');
    if (computerId != null) computerIdFile.writeAsStringSync('$computerId\n');
    return AnalyticsIdentityStore(
      file: File('${dir.path}/analytics.json'),
      computerIdFile: computerIdFile,
      random: Random(7),
    );
  }

  QueuedAnalytics queueOn(
    FakeAnalyticsClient client, {
    AnalyticsIdentityStore? identity,
    ({String? id, String? email}) user = (id: null, email: null),
    DateTime Function()? clock,
  }) => QueuedAnalytics(
    client: client,
    identityStore: identity ?? storeIn(scratch),
    contextFuture: Future.value(AnalyticsContext.unknown),
    userLookup: () => user,
    clock: clock ?? DateTime.now,
  );

  // --- the wire ------------------------------------------------------------

  test('the payload is the web client shape, and says which app sent it', () {
    final event = AnalyticsEvent(
      name: 'grid_picked',
      params: const {'source': 'pill', 'has_grid': true},
      at: DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      identity: const AnalyticsIdentity(
        pseudoId: 'device-1',
        sessionId: 'visit-1',
        userId: 'user-1',
        userEmail: 'someone@example.test',
      ),
    );

    final payload = analyticsPayload(event, AnalyticsContext.unknown);
    final data = payload['data']! as Map<String, Object?>;
    final params = paramsOf(payload);

    expect(payload['event_name'], 'grid_picked');
    // Seconds, not milliseconds — the web client's unit.
    expect(payload['event_timestamp'], 1700000000);
    expect(data['session_id'], 'visit-1');
    expect(data['user_pseudo_id'], 'device-1');
    // In BOTH places, as on the web: most queries read the params table.
    expect(data['user_id'], 'user-1');
    expect(params['user_id'], 'user-1');
    expect(params['user_email'], 'someone@example.test');
    expect(params['source'], 'pill');
    expect(params['has_grid'], true);
    // Without this every stream in the shared project looks like one app.
    expect(params['category'], 'harness-desktop');
  });

  test('params drop nothing meaningful and carry nothing unbounded', () {
    final long = 'x' * (AnalyticsLimits.paramsMaxStringLength + 50);
    final params = analyticsParams({
      'kept': 'value',
      'zero': 0,
      'off': false,
      'null_goes': null,
      'empty_goes': '',
      'nested': {'a': 1},
      'long': long,
    });
    final byKey = {
      for (final entry in params) entry['key']! as String: entry['value'],
    };

    expect(byKey.containsKey('null_goes'), isFalse);
    expect(byKey.containsKey('empty_goes'), isFalse);
    // A zero and a false are measurements, not absences.
    expect(byKey['zero'], 0);
    expect(byKey['off'], false);
    expect(byKey['nested'], '{"a":1}');
    expect(
      (byKey['long']! as String).length,
      AnalyticsLimits.paramsMaxStringLength,
    );
  });

  test('more params than the cap are cut, not sent for the server to drop', () {
    final params = analyticsParams({
      for (var i = 0; i < AnalyticsLimits.paramsMaxKeys + 10; i++) 'k$i': i,
    });

    expect(params, hasLength(AnalyticsLimits.paramsMaxKeys));
  });

  // --- the queue -----------------------------------------------------------

  test(
    'a name that is not snake_case is refused before it is queued',
    () async {
      final client = FakeAnalyticsClient();
      final analytics = queueOn(client);

      analytics.track('Grid Picked');
      analytics.track('no');
      await analytics.flush();

      expect(client.sent, isEmpty);
      expect(analytics.pending, 0);
    },
  );

  test('a sent event leaves the queue; a refused one is dropped', () async {
    final client = FakeAnalyticsClient();
    final analytics = queueOn(client);

    analytics.track('grid_picked');
    await analytics.flush();
    expect(client.sent, hasLength(1));
    expect(analytics.pending, 0);

    client.answer = AnalyticsSendResult.rejected;
    analytics.track('grid_picked');
    await analytics.flush();
    // Sending it again would fail identically, so it goes.
    expect(analytics.pending, 0);
  });

  test('a transport failure keeps the event for the next attempt', () async {
    final client = FakeAnalyticsClient(AnalyticsSendResult.retry);
    final analytics = queueOn(client);

    analytics.track('grid_picked');
    await analytics.flush();

    expect(analytics.pending, 1, reason: 'a 5xx must not lose the event');

    client.answer = AnalyticsSendResult.sent;
    await analytics.flush();
    expect(analytics.pending, 0);
  });

  test('a full queue drops its OLDEST, keeping what describes now', () async {
    final client = FakeAnalyticsClient(AnalyticsSendResult.retry);
    final analytics = queueOn(client);

    for (var i = 0; i < AnalyticsLimits.queueCap + 5; i++) {
      analytics.track('signed_in');
    }
    await analytics.flush();

    expect(analytics.pending, AnalyticsLimits.queueCap);
  });

  test('the account is read per event, not per launch', () async {
    final client = FakeAnalyticsClient();
    var user = (id: null, email: null) as ({String? id, String? email});
    final analytics = QueuedAnalytics(
      client: client,
      identityStore: storeIn(scratch),
      contextFuture: Future.value(AnalyticsContext.unknown),
      userLookup: () => user,
    );

    analytics.track('app_opened');
    user = (id: 'user-9', email: 'someone@example.test');
    analytics.track('signed_in');
    await analytics.flush();

    expect(paramsOf(client.sent[0])['user_id'], isNull);
    expect(paramsOf(client.sent[1])['user_id'], 'user-9');
  });

  test('close drains once, then the sink is spent', () async {
    final client = FakeAnalyticsClient();
    final analytics = queueOn(client);

    analytics.track('app_closed');
    await analytics.close();
    analytics.track('app_opened');

    expect(client.sent, hasLength(1));
    expect(client.disposed, 1);
  });

  // --- identity ------------------------------------------------------------

  test('the device id is this machine\'s Harness id when it has one', () {
    final store = storeIn(scratch, computerId: 'computer-abc');

    expect(store.peek().pseudoId, 'computer-abc');
  });

  test('with no computer-id it mints a v4 UUID and keeps it', () {
    final store = storeIn(scratch);
    final first = store.touch(DateTime.now()).pseudoId;

    expect(
      first,
      matches(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ),
    );
    // A second store over the same file reads the id back rather than minting.
    expect(storeIn(scratch).peek().pseudoId, first);
  });

  test('the visit rotates after quiet and holds through activity', () {
    final store = storeIn(scratch, computerId: 'computer-abc');
    final start = DateTime.utc(2026, 1, 1, 9);

    final first = store.touch(start).sessionId;
    final same = store.touch(start.add(const Duration(minutes: 5))).sessionId;
    final after = store
        .touch(start.add(AnalyticsLimits.sessionIdle * 2))
        .sessionId;

    expect(first, isNotEmpty);
    expect(same, first);
    expect(after, isNot(first));
  });

  test('an opt-out is honoured and survives every write', () {
    final file = File('${scratch.path}/analytics.json')
      ..writeAsStringSync(jsonEncode({'enabled': false}));
    final store = AnalyticsIdentityStore(
      file: file,
      computerIdFile: File('${scratch.path}/computer-id'),
    );

    expect(store.optedOut, isTrue);

    store.touch(DateTime.utc(2026, 1, 1, 9));
    final written = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(
      written['enabled'],
      false,
      reason: 'turning tracking off has to stay off across a write',
    );
  });

  test('a corrupt file starts over rather than failing the launch', () {
    File('${scratch.path}/analytics.json').writeAsStringSync('not json {');
    final store = storeIn(scratch, computerId: 'computer-abc');

    expect(store.peek().pseudoId, 'computer-abc');
    expect(store.optedOut, isFalse);
  });

  // --- the switch ----------------------------------------------------------

  test('a test run is muted, and says why', () {
    final config = AnalyticsConfig.resolve();

    expect(config.enabled, isFalse);
    expect(config.offReason, isNotNull);
    // The sink every test gets: no socket, no queue, no Harness home.
    expect(analytics, isA<NoopAnalytics>());
  });
}
