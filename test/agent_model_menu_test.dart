// What this control says IS what the user knows about where their tokens go, so the three states it
// can be in are the feature from where they sit.
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/grid/agent_grid.dart';
import 'package:harness/widgets/agent_model_menu.dart';

const kRelay = 'https://grid.autonomous.ai/grid-abc/relay';

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
}
