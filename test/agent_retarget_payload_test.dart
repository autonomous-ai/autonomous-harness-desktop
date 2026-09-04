// The `agent_retarget` wire payload — re-homed from the deleted test/grid_retarget_test.dart, whose
// other groups covered grid_retarget.dart (also deleted) but whose last group covered
// AppNotifier.retargetPayload, which survives under moveAgentToGrid and is still @visibleForTesting.
//
// `grid` and `clearGrid` are mutually exclusive on the wire — the CLI's parser reads an absent
// `grid` and an explicit `grid: null` the same way, so "own login" has to say so in its own field.
// This is the one constraint the whole per-agent-model wire change exists to protect.
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/grid/grid_agent_override.dart';
import 'package:harness/state/app_state.dart';

const kNetworkId = 'grid-3378218621364f16';
const kRelay = 'https://grid.autonomous.ai/$kNetworkId/relay';

void main() {
  group('AppNotifier.retargetPayload', () {
    const override = GridAgentOverride(
      networkId: kNetworkId,
      networkName: 'autonomous.ai',
      baseUrl: kRelay,
      apiKey: 'relay-key',
      model: 'GLM-4.7-Flash',
    );

    test('a null grid clears, and carries no grid key', () {
      final payload = AppNotifier.retargetPayload('a1', null);
      expect(payload['agentId'], 'a1');
      expect(payload['clearGrid'], isTrue);
      expect(payload.containsKey('grid'), isFalse);
    });

    test('a grid moves, and carries no clearGrid key', () {
      final payload = AppNotifier.retargetPayload('a1', override);
      expect(payload['agentId'], 'a1');
      expect(payload['grid'], override.toJson());
      expect(payload.containsKey('clearGrid'), isFalse);
    });
  });
}
