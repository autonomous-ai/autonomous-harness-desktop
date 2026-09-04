import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/grid/agent_grid.dart';
import 'package:harness/state/app_state.dart';

Agent agentWith(AgentGrid? grid) => Agent(
  id: 'agent-1',
  sessionId: 's1',
  name: 'Agent',
  engine: 'claude',
  engineDisplayName: null,
  engineIconHint: null,
  parentAgentId: null,
  status: 'active',
  terminalAvailable: true,
  terminalUnavailableReason: null,
  grid: grid,
);

const onDeepSeek = AgentGrid(
  baseUrl: 'https://grid.autonomous.ai/grid-abc/relay',
  model: 'DeepSeek-V4-Flash-0731',
);
const onGlm = AgentGrid(
  baseUrl: 'https://grid.autonomous.ai/grid-abc/relay',
  model: 'GLM-4.7-Flash',
);

void main() {
  group('AgentGrid value equality', () {
    // Without this, every comparison is identity, so two parses of the SAME answer look different —
    // which would make the poll below report "changed" on every single tick.
    test('two parses of the same assignment are equal', () {
      const wire = {'baseUrl': 'https://grid.autonomous.ai/grid-abc/relay', 'model': 'GLM-4.7-Flash'};
      expect(AgentGrid.fromJson(wire), equals(onGlm));
      expect(AgentGrid.fromJson(wire).hashCode, equals(onGlm.hashCode));
    });

    test('a different model is a different assignment', () {
      expect(onGlm, isNot(equals(onDeepSeek)));
    });
  });

  group('the background agent poll', () {
    // The regression this file exists for. `_agentsEqual` listed the Agent fields by hand and never
    // grew `grid`, so a refreshed list that differed ONLY by which grid an agent runs on compared
    // equal and was thrown away. An agent moved by anything other than this app's own foreground
    // path then kept its old grid in the UI for as long as the app ran — and the retarget banner
    // went on offering to move an agent that was already exactly where the user had put it.
    test('notices an agent that changed grid and nothing else', () {
      expect(
        AppNotifier.agentsEqual([agentWith(onDeepSeek)], [agentWith(onGlm)]),
        isFalse,
        reason: 'a grid-only change must count as a change',
      );
    });

    test('notices an agent that gained or lost a grid', () {
      expect(AppNotifier.agentsEqual([agentWith(null)], [agentWith(onGlm)]), isFalse);
      expect(AppNotifier.agentsEqual([agentWith(onGlm)], [agentWith(null)]), isFalse);
    });

    // The other half: it must still say "equal" for a genuinely identical list, or the poll would
    // replace the agent list and rebuild the tree every tick.
    test('stays quiet when nothing changed', () {
      expect(AppNotifier.agentsEqual([agentWith(onGlm)], [agentWith(onGlm)]), isTrue);
      expect(AppNotifier.agentsEqual([agentWith(null)], [agentWith(null)]), isTrue);
    });
  });
}
