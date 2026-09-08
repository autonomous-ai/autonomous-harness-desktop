// The agent funnel: opening the New agent dialog, finishing it, and actually
// speaking to what came out. Three separate events on purpose — the interesting
// numbers are the DROPS between them, and one event per step is the only way to
// see a drop at all.
//
// What is pinned here is the part that is easy to get subtly wrong: which door
// a dialog says it was opened by, the difference between Auto and the engine's
// own login (both reach the notifier as a null override), and that a first
// message is reported once, for agents this app made, and never with any of
// what was typed.
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

import 'support/fake_grid_api.dart';

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
                  gridApiClient: FakeGridApi(),
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
                  gridApiClient: FakeGridApi(),
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

    testWidgets('carries the engine, and Auto as a grid with no model', (
      tester,
    ) async {
      gridSelectionStore.value = const GridSelection(
        networkId: 'grid-3378218621364f16',
        networkName: 'autonomous.ai',
      );
      await create(tester);

      final params = tracked.paramsOf('agent_created');
      expect(params['engine'], 'claude');
      expect(params['on_grid'], isTrue);
      expect(params['network_id'], 'grid-3378218621364f16');
      // Auto: on a grid, with the grid choosing. Null here MEANS Auto, which is
      // why `on_grid` has to be read beside it.
      expect(params['model'], isNull);
      expect(params['bypass_permission'], isFalse);
    });

    testWidgets('own login is a null model that is NOT on a grid', (
      tester,
    ) async {
      // The distinction the notifier cannot see — both arrive there as a null
      // override — and the reason this event is sent from the dialog.
      gridSelectionStore.value = GridSelection.none;
      await create(tester);

      final params = tracked.paramsOf('agent_created');
      expect(params['on_grid'], isFalse);
      expect(params['model'], isNull);
      expect(params['network_id'], isNull);
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

  group('agent_first_message', () {
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

    Future<void> turnStarted(AppNotifier notifier, String agentId) =>
        notifier.handleEventForTest('machine-1', {
          'type': 'turn_started',
          'agentId': agentId,
        });

    test(
      'the first turn of an agent we made reports how long it took',
      () async {
        final notifier = notifierWithMachine();
        notifier.armAgentFirstMessageForTest(
          'machine-1',
          'agent-1',
          engine: 'claude',
          onGrid: true,
          model: 'DeepSeek-V4-Flash-0731',
        );

        await turnStarted(notifier, 'agent-1');

        final params = tracked.paramsOf('agent_first_message');
        expect(params['engine'], 'claude');
        expect(params['model'], 'DeepSeek-V4-Flash-0731');
        expect(params['on_grid'], isTrue);
        expect(params['seconds_since_created'], isA<int>());
      },
    );

    test('only the FIRST turn reports, not every turn after it', () async {
      final notifier = notifierWithMachine();
      notifier.armAgentFirstMessageForTest(
        'machine-1',
        'agent-1',
        engine: 'codex',
      );

      await turnStarted(notifier, 'agent-1');
      await turnStarted(notifier, 'agent-1');
      await turnStarted(notifier, 'agent-1');

      expect(tracked.count('agent_first_message'), 1);
    });

    test('an agent this app did not make reports nothing', () async {
      // An adopted session may have been running for days; calling its next
      // turn a "first message" would be a straight lie.
      final notifier = notifierWithMachine();

      await turnStarted(notifier, 'adopted-agent');

      expect(tracked.count('agent_first_message'), 0);
    });
  });
}
