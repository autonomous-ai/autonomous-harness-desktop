// The funnel: opening the New agent dialog, finishing it, and — once per
// signed-in session — actually saying something. Separate events on purpose:
// the interesting numbers are the DROPS between them, and one event per step is
// the only way to see a drop at all.
//
// What is pinned here is the part that is easy to get subtly wrong: which door
// a dialog says it was opened by, the difference between Auto and the engine's
// own login (both reach the notifier as a null override), and that the first
// message is reported once per SESSION rather than per agent, and never with
// any of what was typed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/analytics/analytics.dart';
import 'package:harness/analytics/analytics_sink.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/grid/grid_agent_override.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/new_agent_dialog.dart';

/// Keeps every tracked event, so a test can assert on the name AND the params
/// — a stream is only as good as what its params carry.
class RecordingAnalytics implements Analytics {
  final List<({String name, Map<String, Object?> params})> events = [];

  Map<String, Object?> paramsOf(String name) =>
      events.firstWhere((event) => event.name == name).params;

  int count(String name) => events.where((e) => e.name == name).length;

  @override
  void track(String name, {Map<String, Object?> params = const {}}) =>
      events.add((name: name, params: params));

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

/// Stands in for the CLI round trip, so a test can drive a real Create click.
class FakeCreateAgentNotifier extends AppNotifier {
  FakeCreateAgentNotifier()
    : super(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      );

  @override
  Future<Map<String, dynamic>> listRemoteFolder(
    String machineId,
    String? path,
  ) async => {'path': '/tmp/agent-folder', 'entries': <dynamic>[]};

  @override
  Future<String?> createAgent(
    String machineId, {
    required String engine,
    required String folder,
    bool bypassPermission = false,
    GridAgentOverride? grid,
    String? codexHome,
  }) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingAnalytics tracked;

  setUp(() {
    tracked = RecordingAnalytics();
    setAnalyticsForTest(tracked);
  });

  // Put back, or every later test in the run reports into this list.
  tearDown(() => setAnalyticsForTest(null));

  const machine = Machine(
    machineId: 'machine-1',
    authMode: MachineAuthMode.remote,
    name: 'Mac mini M4',
  );

  group('new_agent_opened', () {
    Future<void> openFrom(WidgetTester tester, String source) async {
      final notifier = FakeCreateAgentNotifier();
      addTearDown(notifier.dispose);
      notifier.machineStates['machine-1'] = MachineState(machine)
        ..localOnly = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showNewAgentDialog(
                  context,
                  notifier,
                  'machine-1',
                  source: source,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('names the door it was opened by', (tester) async {
      await openFrom(tester, 'rail_empty');

      expect(tracked.paramsOf('new_agent_opened'), {'source': 'rail_empty'});
    });

    testWidgets('every door reports, because the dialog reports for them', (
      tester,
    ) async {
      // The point of tracking inside `showNewAgentDialog` rather than at each
      // call site: a door added later cannot forget.
      for (final source in ['machine_row', 'pane_empty', 'shortcut']) {
        await openFrom(tester, source);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }

      expect(tracked.count('new_agent_opened'), 3);
      expect(tracked.events.map((e) => e.params['source']), [
        'machine_row',
        'pane_empty',
        'shortcut',
      ]);
    });
  });

  group('agent_created', () {
    // The store is still set by these tests — not because the dialog reads it
    // (it no longer does), but because the ONE thing worth asserting now is
    // that it does not: a default provider sitting in the store must not turn
    // up in this event.
    final before = gridSelectionStore.value;
    tearDown(() => gridSelectionStore.value = before);

    Future<void> create(WidgetTester tester) async {
      final notifier = FakeCreateAgentNotifier();
      addTearDown(notifier.dispose);
      notifier.machineStates['machine-1'] = MachineState(machine);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showNewAgentDialog(
                  context,
                  notifier,
                  'machine-1',
                  source: 'machine_row',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Create stays dead until a folder is chosen. This machine is not
      // `thisComputer`, so Browse… opens the in-app remote picker rather than
      // a native panel this harness has no plugin for.
      await tester.tap(find.text('Browse…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Select this folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create agent'));
      await tester.pumpAndSettle();
    }

    testWidgets('carries the engine, and never a grid', (tester) async {
      await create(tester);

      final params = tracked.paramsOf('agent_created');
      expect(params['engine'], 'claude');
      // A create is always the engine's own login now, so this is the one
      // shape the event ever has from this door. Grid launches are reported
      // from the agent view's model menu instead.
      expect(params['on_grid'], isFalse);
      expect(params['network_id'], isNull);
      expect(params['model'], isNull);
      expect(params['bypass_permission'], isFalse);
    });

    testWidgets('a default provider does not leak into the event', (
      tester,
    ) async {
      // The regression this whole change is about, stated as an assertion: a
      // grid sitting in the store as the default provider used to BE the
      // launch target, and this event named it. It must now be invisible from
      // here — if this ever goes back to reading the store, this is the test
      // that says so rather than a user finding their agent on the wrong
      // account.
      gridSelectionStore.value = const GridSelection(
        networkId: 'grid-3378218621364f16',
        networkName: 'autonomous.ai',
      );
      await create(tester);

      final params = tracked.paramsOf('agent_created');
      expect(params['on_grid'], isFalse);
      expect(params['network_id'], isNull);
      expect(params['model'], isNull);
      expect(
        params.values.join(' '),
        isNot(contains('autonomous.ai')),
        reason: 'the default provider is not what this agent launched on',
      );
    });

    testWidgets('the working folder is never sent', (tester) async {
      gridSelectionStore.value = GridSelection.none;
      await create(tester);

      // An absolute path names the person as surely as their email does.
      expect(
        tracked.paramsOf('agent_created').values.join(' '),
        isNot(contains('/tmp/agent-folder')),
      );
    });
  });

  group('app_first_message', () {
    AppNotifier notifierWithMachine() {
      final notifier = AppNotifier(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      );
      addTearDown(notifier.dispose);
      notifier.machineStates['machine-1'] = MachineState(machine);
      return notifier;
    }

    Future<void> turn(AppNotifier notifier, String type, String agentId) =>
        notifier.handleEventForTest('machine-1', {
          'type': type,
          'agentId': agentId,
        });

    Future<void> turnStarted(AppNotifier notifier, String agentId) =>
        turn(notifier, 'turn_started', agentId);

    test('reports the wait, and what started the clock', () async {
      final notifier = notifierWithMachine();
      notifier.armFirstMessageForTest('sign_in');

      await turnStarted(notifier, 'agent-1');

      final params = tracked.paramsOf('app_first_message');
      expect(params['from'], 'sign_in');
      expect(params['seconds_since_login'], isA<int>());
      // Not per agent: nothing here may name the agent, its engine or its
      // machine. Which agent it was is `agent_created`'s question.
      expect(params.keys, unorderedEquals(['from', 'seconds_since_login']));
    });

    test('once per session, however many agents are spoken to', () async {
      final notifier = notifierWithMachine();
      notifier.armFirstMessageForTest('launch');

      await turnStarted(notifier, 'agent-1');
      await turnStarted(notifier, 'agent-1');
      await turnStarted(notifier, 'agent-2');

      expect(tracked.count('app_first_message'), 1);
      expect(tracked.paramsOf('app_first_message')['from'], 'launch');
    });

    test('a heartbeat is not a message', () async {
      // The trap this closes: a returning user whose agent was already mid-turn
      // when the app reconnected gets heartbeats, not a turn start. Counting
      // one would report a near-zero wait for somebody who has not said a word.
      final notifier = notifierWithMachine();
      notifier.armFirstMessageForTest('launch');

      await turn(notifier, 'turn_heartbeat', 'agent-1');
      expect(tracked.count('app_first_message'), 0);

      // And the real first message still lands afterwards.
      await turnStarted(notifier, 'agent-1');
      expect(tracked.count('app_first_message'), 1);
    });

    test('a turn with nobody signed in reports nothing', () async {
      // Nothing started the clock, so there is no wait to measure — and an
      // event with no login behind it is a number attached to nobody.
      final notifier = notifierWithMachine();

      await turnStarted(notifier, 'agent-1');

      expect(tracked.count('app_first_message'), 0);
    });
  });
}
