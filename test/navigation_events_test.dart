// Which DOOR was used — for Settings' panes, and for the model picker.
//
// Both surfaces are reachable several ways, and a bare count of either answers
// almost nothing: Settings ▸ Providers is opened from the account menu, from
// either provider pill's `Provider settings…`, from the subscription-limit
// card's `Choose a provider`, and from the settings rail itself. The last two
// are quite different visits — one arrives from somebody who has just been told
// they are nearly out of quota.
//
// What is pinned here is the part a refactor breaks silently: that every door
// says which one it is, and that the model picker reports the REFUSALS as well
// as the opens (a mid-turn agent bounces the keyboard door with no tooltip to
// have read first).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/analytics/analytics.dart';
import 'package:harness/analytics/analytics_sink.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/settings/settings_screen.dart';
import 'package:harness/settings/settings_section.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/agent_model_menu.dart';

import 'support/fake_grid_api.dart';

/// Keeps every tracked event — the same recorder `agent_events_test` uses.
class _Recording implements Analytics {
  final List<({String name, Map<String, Object?> params})> events = [];

  List<Map<String, Object?>> allOf(String name) => [
    for (final event in events)
      if (event.name == name) event.params,
  ];

  @override
  void track(String name, {Map<String, Object?> params = const {}}) =>
      events.add((name: name, params: params));

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Recording tracked;

  setUp(() {
    tracked = _Recording();
    setAnalyticsForTest(tracked);
  });

  // Put back, or every later test in the run reports into this list.
  tearDown(() => setAnalyticsForTest(null));

  group('screen_view carries the door', () {
    Future<void> openSettings(
      WidgetTester tester, {
      required String source,
      SettingsSection? initialSection,
    }) async {
      final notifier = AppNotifier(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      );
      addTearDown(notifier.dispose);
      // Its own, never the singleton: that one holds a real client and would
      // reach for the developer's Grid session.
      final gridNetworks = GridNetworksController(client: FakeGridApi());
      addTearDown(gridNetworks.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSettingsScreen(
                  context,
                  notifier,
                  gridNetworks: gridNetworks,
                  initialSection: initialSection,
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

    testWidgets('the pane Settings opens on names the door that opened it', (
      tester,
    ) async {
      await openSettings(
        tester,
        source: 'usage_offer',
        initialSection: SettingsSection.grid,
      );

      expect(tracked.allOf('screen_view'), [
        {'screen': 'settings_grid', 'source': 'usage_offer'},
      ]);
    });

    testWidgets('moving between panes reports the rail, not the first door', (
      tester,
    ) async {
      await openSettings(
        tester,
        source: 'account_menu',
        initialSection: SettingsSection.appearance,
      );
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      // Two visits, two sources: the door into Settings, then the rail. A
      // second view that inherited `account_menu` would report every pane a
      // reader wandered through as having been opened from the account menu.
      expect(tracked.allOf('screen_view'), [
        {'screen': 'settings_appearance', 'source': 'account_menu'},
        {'screen': 'settings_terminal', 'source': 'rail'},
      ]);
    });
  });

  group('model_change_requested', () {
    /// A notifier holding one machine with one idle `claude` agent.
    AppNotifier notifierWithAgent() {
      final notifier = AppNotifier(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      );
      addTearDown(notifier.dispose);
      notifier.machineStates['m1'] =
          MachineState(
              const Machine(
                machineId: 'm1',
                apiKey: '',
                authMode: MachineAuthMode.remote,
                name: 'm1',
                status: 'online',
              ),
            )
            ..agents = [
              const Agent(
                id: 'a1',
                name: 'a1',
                engine: 'claude',
                status: 'active',
                terminalAvailable: true,
              ),
            ];
      return notifier;
    }

    /// Runs `pickAgentModel` under a real Scaffold — the refusals talk to the
    /// messenger, which needs one.
    Future<void> ask(
      WidgetTester tester,
      AppNotifier notifier, {
      required String engine,
      required String source,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => pickAgentModel(
                  context,
                  notifier,
                  machineId: 'm1',
                  agentId: 'a1',
                  engine: engine,
                  source: source,
                ),
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ask'));
      await tester.pump();
    }

    testWidgets('an engine that cannot use a grid is a refusal, not silence', (
      tester,
    ) async {
      await ask(
        tester,
        notifierWithAgent(),
        engine: 'aider',
        source: 'shortcut',
      );

      expect(tracked.allOf('model_change_requested'), [
        {'source': 'shortcut', 'engine': 'aider', 'outcome': 'unsupported'},
      ]);
    });

    testWidgets('a mid-turn agent reports busy, and opens nothing', (
      tester,
    ) async {
      final notifier = notifierWithAgent();
      await notifier.handleMachineEventForTest('m1', {
        'type': 'turn_started',
        'agentId': 'a1',
      });

      await ask(
        tester,
        notifier,
        engine: 'claude',
        source: 'shortcut',
      );

      // The one refusal people actually meet, and only from the keyboard — the
      // pill draws itself disabled, so ⇧⌘M is the door with no tooltip in front
      // of it. How often it lands is the reason this outcome exists.
      expect(tracked.allOf('model_change_requested'), [
        {'source': 'shortcut', 'engine': 'claude', 'outcome': 'busy'},
      ]);

      // Disarms the turn watchdog, which outlives the widget tree otherwise.
      await notifier.handleMachineEventForTest('m1', {
        'type': 'turn_ended',
        'agentId': 'a1',
      });
      await tester.pump();
    });

    testWidgets('a move already in flight reports restarting', (tester) async {
      retargetingAgents.value = {'m1/a1'};
      addTearDown(() => retargetingAgents.value = const {});

      await ask(
        tester,
        notifierWithAgent(),
        engine: 'claude',
        source: 'pill',
      );

      expect(tracked.allOf('model_change_requested'), [
        {'source': 'pill', 'engine': 'claude', 'outcome': 'restarting'},
      ]);
    });

    testWidgets('a build with no providers reports nothing at all', (
      tester,
    ) async {
      final notifier = notifierWithAgent();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => pickAgentModel(
                  context,
                  notifier,
                  machineId: 'm1',
                  agentId: 'a1',
                  engine: 'claude',
                  source: 'shortcut',
                  gridSurface: false,
                ),
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ask'));
      await tester.pump();

      // There is no pill to click and ⇧⌘M is not bound, so there is no click to
      // report — and a row here would be a door that does not exist.
      expect(tracked.allOf('model_change_requested'), isEmpty);
    });
  });
}
