// Applying a grid to agents that are ALREADY RUNNING.
//
// A live process cannot be re-pointed — the CLI has to respawn its pane — so the only thing the app
// may do on its own is work out which agents are behind and say so. What it must never do is claim an
// agent is already fine when nobody could check, or offer to move one the CLI is going to refuse.
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/grid/agent_grid.dart';
import 'package:harness/grid/grid_retarget.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/state/app_state.dart';

const kNetworkId = 'grid-3378218621364f16';
const kRelay = 'https://grid.autonomous.ai/$kNetworkId/relay';

Agent agent(
  String id, {
  String engine = 'claude',
  AgentGrid? grid,
  bool terminalAvailable = true,
  String status = 'active',
}) => Agent(
  id: id,
  name: id,
  engine: engine,
  status: status,
  terminalAvailable: terminalAvailable,
  grid: grid,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AgentGrid.fromJson', () {
    test('reads what the CLI reports, and refuses anything else', () {
      final parsed = AgentGrid.fromJson({
        'baseUrl': kRelay,
        'model': 'GLM-4.7-Flash',
      });
      expect(parsed?.baseUrl, kRelay);
      expect(parsed?.model, 'GLM-4.7-Flash');
      expect(AgentGrid.fromJson({'baseUrl': kRelay})?.model, isNull);
      expect(AgentGrid.fromJson(null), isNull);
      expect(AgentGrid.fromJson({'baseUrl': ''}), isNull);
      expect(AgentGrid.fromJson('nope'), isNull);
    });

    test('an agent parsed from a CLI payload carries its grid', () {
      final parsed = Agent.fromJson({
        'id': 'a1',
        'name': 'Claude Code',
        'engine': 'claude',
        'terminal': {'available': true},
        'grid': {'baseUrl': kRelay, 'model': 'GLM-4.7-Flash'},
      });
      expect(parsed.grid?.baseUrl, kRelay);
      // An older CLI sends no such field, and that must not read as "on a grid".
      expect(Agent.fromJson({'id': 'a2', 'name': 'Old'}).grid, isNull);
    });
  });

  group('needsRetarget', () {
    test('an agent on the chosen grid and model is left alone', () {
      final on = AgentGrid(baseUrl: kRelay, model: 'GLM-4.7-Flash');
      expect(needsRetarget(on, kNetworkId, 'GLM-4.7-Flash'), isFalse);
    });

    test('the model is part of the match, not just the grid', () {
      final on = AgentGrid(baseUrl: kRelay, model: 'GLM-4.7-Flash');
      expect(needsRetarget(on, kNetworkId, 'DeepSeek-V4-Flash-0731'), isTrue);
      expect(needsRetarget(on, kNetworkId, null), isTrue);
    });

    test('unknown counts as behind, never as fine', () {
      // The direction matters: a needless move costs a restart, while the opposite error would leave
      // an agent spending the wrong account under a UI that said it was correct.
      expect(needsRetarget(null, kNetworkId, null), isTrue);
      expect(
        needsRetarget(
          AgentGrid(baseUrl: 'https://openrouter.ai/api'),
          kNetworkId,
          null,
        ),
        isTrue,
      );
    });
  });

  group('agentsNeedingRetarget', () {
    late AppNotifier notifier;

    setUp(() {
      notifier = AppNotifier(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      );
    });

    tearDown(() => notifier.dispose());

    void seed(List<Agent> agents) {
      const machine = Machine(
        machineId: 'm1',
        apiKey: '',
        authMode: MachineAuthMode.remote,
        name: 'prod-mac',
        status: 'online',
      );
      notifier.machineStates['m1'] = MachineState(machine)..agents = agents;
    }

    test('is empty when no grid is picked, whatever the agents are on', () {
      seed([agent('a1')]);
      expect(agentsNeedingRetarget(notifier, GridSelection.none), isEmpty);
    });

    test('names exactly the agents that are behind', () {
      seed([
        agent('behind'),
        agent(
          'current',
          grid: AgentGrid(baseUrl: kRelay, model: 'GLM-4.7-Flash'),
        ),
        agent(
          'other-grid',
          grid: AgentGrid(baseUrl: 'https://grid.autonomous.ai/grid-zzz/relay'),
        ),
      ]);
      final stale = agentsNeedingRetarget(
        notifier,
        const GridSelection(
          networkId: kNetworkId,
          networkName: 'autonomous.ai',
          model: 'GLM-4.7-Flash',
        ),
      );
      expect(stale.map((s) => s.agentId), ['behind', 'other-grid']);
      expect(stale.first.machineId, 'm1');
    });

    test('never offers a move the CLI would refuse', () {
      // Cursor Agent talks only to Cursor's own service, so the CLI answers
      // GRID_ENGINE_UNSUPPORTED. The other two have no process to replace: an agent with no live
      // pane, and one that is not running — a row for an agent deleted while the app was
      // reconnecting looks exactly like the latter, and counting it was a real bug.
      seed([
        agent('cursor', engine: 'cursor'),
        agent('dormant', terminalAvailable: false),
        agent('stopped', status: 'offline'),
        agent('movable'),
      ]);
      final stale = agentsNeedingRetarget(
        notifier,
        const GridSelection(
          networkId: kNetworkId,
          networkName: 'autonomous.ai',
        ),
      );
      expect(stale.map((s) => s.agentId), ['movable']);
    });
  });

  group('retargetAgents', () {
    test(
      'does nothing, and mints nothing, when there is nothing to move',
      () async {
        final notifier = AppNotifier(
          config: AppConfig.dev,
          authSession: AuthSession(),
          configStore: null,
        );
        addTearDown(notifier.dispose);
        final outcomes = await retargetAgents(
          notifier: notifier,
          stale: const [],
          selection: const GridSelection(
            networkId: kNetworkId,
            networkName: 'autonomous.ai',
          ),
        );
        expect(outcomes, isEmpty);
      },
    );
  });
}
