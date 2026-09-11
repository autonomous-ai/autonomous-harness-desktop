import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/phone/agents_page.dart';
import 'package:harness/phone/link_page.dart';
import 'package:harness/phone/phone_navigation.dart';
import 'package:harness/phone/phone_shell.dart';
import 'package:harness/state/app_state.dart';

AppNotifier _notifier() => AppNotifier(
  config: AppConfig.dev,
  authSession: AuthSession(),
  configStore: null,
);

Agent _agent(String id) => Agent.fromJson({
  'id': id,
  'name': id,
  'engine': 'claude',
  'terminal': {
    'runtimes': [
      {'backend': 'tmux', 'paneId': '%1'},
    ],
  },
});

/// A machine past every check the phone makes. [online] false also keeps a pane's attach from
/// dialling out, which is what lets a test open an agent without a socket.
MachineState _machine(
  AppNotifier app,
  String id, {
  bool linked = true,
  bool online = true,
  List<String> agents = const [],
}) {
  final machine = Machine(
    machineId: id,
    apiKey: '',
    authMode: MachineAuthMode.remote,
    name: id,
    status: 'online',
  );
  final state = MachineState(machine)
    ..needsLink = !linked
    ..nodeOnline = online
    ..connectionStatus = ConnectionStatus.connected
    ..agentLoadStatus = AgentLoadStatus.loaded
    ..agents = [for (final agent in agents) _agent(agent)];
  app.machines = [...app.machines, machine];
  app.machineStates[id] = state;
  return state;
}

Future<void> _pumpPhone(WidgetTester tester, AppNotifier app) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: PhoneShell(notifier: app)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'the first screen lists the machines, and says which need a password',
    (tester) async {
      final app = _notifier();
      _machine(app, 'desk', agents: ['a1', 'a2']);
      _machine(app, 'box', linked: false);
      await _pumpPhone(tester, app);

      expect(find.text('Machines'), findsOneWidget);
      expect(find.text('desk'), findsOneWidget);
      expect(find.text('2 agents'), findsOneWidget);
      expect(find.text('box'), findsOneWidget);
      expect(find.text('Needs its password'), findsOneWidget);
    },
  );

  testWidgets('a machine with no link opens on its own password form', (
    tester,
  ) async {
    final app = _notifier();
    _machine(app, 'box', linked: false);
    await _pumpPhone(tester, app);

    await tester.tap(find.text('box'));
    await tester.pumpAndSettle();

    expect(find.byType(LinkPage), findsOneWidget);
    expect(
      find.byKey(const Key('remote-password-connect-field')),
      findsOneWidget,
    );
  });

  testWidgets('a linked machine opens on its agents', (tester) async {
    final app = _notifier();
    _machine(app, 'desk', agents: ['planner', 'reviewer']);
    await _pumpPhone(tester, app);

    await tester.tap(find.text('desk'));
    await tester.pumpAndSettle();

    expect(find.byType(AgentsPage), findsOneWidget);
    expect(find.text('planner'), findsOneWidget);
    expect(find.text('reviewer'), findsOneWidget);
  });

  testWidgets('opening an agent leaves it the only one open', (tester) async {
    final app = _notifier();
    _machine(app, 'desk', online: false, agents: ['a1', 'a2']);
    await app.assignAgentToPane(null, 'desk', 'a1');
    await app.assignAgentToPane(null, 'desk', 'a2');
    expect(app.panes, hasLength(2));

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (built) {
            context = built;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    openAgent(context, app, 'desk', 'a1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(app.panes, hasLength(1));
    expect(app.panes.single.agentId, 'a1');
    // An offline machine's pane starts its periodic reconnect poll, which only dispose() stops;
    // the workspace snapshot debounces for 5s, so let that fire rather than leave it pending.
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
    await tester.pump(const Duration(seconds: 6));
  });
}
