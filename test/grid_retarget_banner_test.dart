// The banner is the only thing that ever tells a user their running agents were left behind by a
// grid they just picked, so what it shows — and just as importantly, when it says nothing — is the
// whole feature from where they sit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/grid/agent_grid.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/grid_retarget_banner.dart';

const kNetworkId = 'grid-3378218621364f16';
const kRelay = 'https://grid.autonomous.ai/$kNetworkId/relay';

const kOnGrid = GridSelection(
  networkId: kNetworkId,
  networkName: 'autonomous.ai',
  model: 'GLM-4.7-Flash',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The banner reads the app-wide singleton; a test that left a grid behind would change what every
  // later test sees.
  final before = gridSelectionStore.value;
  tearDown(() => gridSelectionStore.value = before);

  AppNotifier notifierWith(List<Agent> agents) {
    final notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
    );
    addTearDown(notifier.dispose);
    const machine = Machine(
      machineId: 'm1',
      apiKey: '',
      authMode: MachineAuthMode.remote,
      name: 'prod-mac',
      status: 'online',
    );
    notifier.machineStates['m1'] = MachineState(machine)..agents = agents;
    return notifier;
  }

  Future<void> pump(WidgetTester tester, AppNotifier notifier) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: grid.buildAppTheme(brightness: Brightness.light),
        home: Builder(
          builder: (context) {
            grid.AppTheme.brightness.value = Brightness.light;
            return grid.BrightnessScope(
              child: Scaffold(body: GridRetargetBanner(notifier: notifier)),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final action = find.byKey(const Key('grid-retarget-action'));
  final dismiss = find.byKey(const Key('grid-retarget-dismiss'));

  testWidgets('says nothing when no grid is picked', (tester) async {
    gridSelectionStore.value = GridSelection.none;
    await pump(
      tester,
      notifierWith([
        const Agent(
          id: 'a1',
          name: 'Claude Code',
          engine: 'claude',
          terminalAvailable: true,
        ),
      ]),
    );
    expect(action, findsNothing);
  });

  testWidgets('says nothing when every agent is already there', (tester) async {
    gridSelectionStore.value = kOnGrid;
    await pump(
      tester,
      notifierWith([
        Agent(
          id: 'a1',
          name: 'Claude Code',
          engine: 'claude',
          terminalAvailable: true,
          grid: AgentGrid(baseUrl: kRelay, model: 'GLM-4.7-Flash'),
        ),
      ]),
    );
    expect(action, findsNothing);
  });

  testWidgets('counts the agents left behind and names the grid', (
    tester,
  ) async {
    gridSelectionStore.value = kOnGrid;
    await pump(
      tester,
      notifierWith([
        const Agent(
          id: 'a1',
          name: 'One',
          engine: 'claude',
          terminalAvailable: true,
        ),
        const Agent(
          id: 'a2',
          name: 'Two',
          engine: 'claude',
          terminalAvailable: true,
        ),
      ]),
    );
    expect(action, findsOneWidget);
    expect(find.textContaining('2 running agents'), findsOneWidget);
    expect(find.textContaining('autonomous.ai'), findsOneWidget);
    // The restart is the cost of the button, so it has to be on the button's own card.
    expect(find.textContaining('restarts'), findsOneWidget);
  });

  testWidgets('reads as singular for one agent', (tester) async {
    gridSelectionStore.value = kOnGrid;
    await pump(
      tester,
      notifierWith([
        const Agent(
          id: 'a1',
          name: 'One',
          engine: 'claude',
          terminalAvailable: true,
        ),
      ]),
    );
    expect(find.textContaining('1 running agent is'), findsOneWidget);
  });

  testWidgets('dismissing stops it nagging about that choice', (tester) async {
    gridSelectionStore.value = kOnGrid;
    final notifier = notifierWith([
      const Agent(
        id: 'a1',
        name: 'One',
        engine: 'claude',
        terminalAvailable: true,
      ),
    ]);
    await pump(tester, notifier);
    expect(action, findsOneWidget);

    await tester.tap(dismiss);
    await tester.pumpAndSettle();
    expect(action, findsNothing);

    // A DIFFERENT choice is a live question again — the dismissal was about the old one.
    gridSelectionStore.value = const GridSelection(
      networkId: kNetworkId,
      networkName: 'autonomous.ai',
      model: 'DeepSeek-V4-Flash-0731',
    );
    await tester.pumpAndSettle();
    expect(action, findsOneWidget);
  });
}
