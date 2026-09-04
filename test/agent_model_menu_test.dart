// What this control says IS what the user knows about where their tokens go, so the three states it
// can be in are the feature from where they sit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/grid/agent_grid.dart';
import 'package:harness/grid/grid_models_controller.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/agent_model_menu.dart';

const kRelay = 'https://grid.autonomous.ai/grid-abc/relay';
const kNetworkId = 'grid-live';

void main() {
  test('an agent with no grid is on its own login', () {
    expect(agentModelLabel(null), 'Own login');
  });

  test('a grid with no model left the choice to the grid', () {
    expect(agentModelLabel(const AgentGrid(baseUrl: kRelay)), 'Auto');
  });

  test('a pinned model is named', () {
    expect(
      agentModelLabel(const AgentGrid(baseUrl: kRelay, model: 'GLM-4.7-Flash')),
      'GLM-4.7-Flash',
    );
  });

  group('an already-open menu', () {
    // Fix-round regression: a PopupMenuButton's itemBuilder is a one-shot snapshot handed to
    // showMenu() before the tap that triggers a load even finishes — so a menu opened on an
    // unloaded network showed only "Own login"/"Auto" until closed and reopened, and could show a
    // PREVIOUSLY-selected grid's models under the new grid's name. AgentModelMenu is now built on
    // MenuAnchor + a ListenableBuilder on gridModelsController specifically so the OPEN panel
    // updates live as the controller moves Loading -> Ready — this test drives that same
    // transition with GridModelsController.debugSetState (a test-only seam) rather than a real,
    // non-deterministic network round trip, and would fail against the old PopupMenuButton
    // implementation: nothing there re-invoked itemBuilder once the route was already showing.
    final beforeSelection = gridSelectionStore.value;

    setUp(() {
      gridSelectionStore.value = const GridSelection(
        networkId: kNetworkId,
        networkName: 'Live Grid',
      );
      gridModelsController.debugSetState(kNetworkId, const GridModelsLoading());
    });

    tearDown(() {
      gridSelectionStore.value = beforeSelection;
      gridModelsController.debugSetState(kNetworkId, const GridModelsIdle());
    });

    testWidgets(
      'picks up the grid\'s models as they load, with no close/reopen',
      (tester) async {
        final notifier = AppNotifier(
          config: AppConfig.dev,
          authSession: AuthSession(),
          configStore: null,
        );
        addTearDown(notifier.dispose);
        // A model pinned so the trigger's own label ("Pinned-Model") cannot collide with either
        // menu row this test looks for.
        notifier.machineStates['m1'] = MachineState(
          const Machine(
            machineId: 'm1',
            apiKey: '',
            authMode: MachineAuthMode.remote,
            name: 'm1',
            status: 'online',
          ),
        )..agents = [
          const Agent(
            id: 'a1',
            name: 'a1',
            engine: 'claude',
            status: 'active',
            terminalAvailable: true,
            grid: AgentGrid(baseUrl: kRelay, model: 'Pinned-Model'),
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AgentModelMenu(
                notifier: notifier,
                machineId: 'm1',
                agentId: 'a1',
                engine: 'claude',
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Pinned-Model'));
        await tester.pumpAndSettle();

        // Opened while gridModelsController is still Loading for this network.
        expect(find.text('Loading models…'), findsOneWidget);
        expect(find.text('GLM-4.7-Flash'), findsNothing);

        // The load finishes — WITHOUT closing the menu.
        gridModelsController.debugSetState(
          kNetworkId,
          const GridModelsReady(['GLM-4.7-Flash']),
        );
        await tester.pump();

        expect(
          find.text('Loading models…'),
          findsNothing,
          reason: 'the open panel must drop the loading row once models arrive',
        );
        expect(
          find.text('GLM-4.7-Flash'),
          findsOneWidget,
          reason: 'the open panel must show the newly-loaded model without a reopen',
        );
      },
    );
  });
}
