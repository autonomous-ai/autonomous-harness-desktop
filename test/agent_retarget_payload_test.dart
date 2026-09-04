// The `agent_retarget` wire payload, and the sentence a refusal turns into — re-homed from the
// deleted test/grid_retarget_test.dart, whose
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

  // Reached ONLY from `moveAgentToGrid`'s `on WsRequestFailure` catch: a CLI refusal arrives as a
  // throw, not as a returned map. The mapping used to sit behind an `if (result['error'] is String)`
  // on a reply that had already thrown, so none of these sentences could ever reach the screen.
  group('AppNotifier.retargetMessage', () {
    test('a busy agent names the way out, not the code', () {
      expect(
        AppNotifier.retargetMessage('AGENT_BUSY', null),
        'It is running a turn. Move it when the turn finishes.',
      );
    });

    test('an agent that vanished is the sentinel, not a sentence', () {
      expect(
        AppNotifier.retargetMessage('AGENT_NOT_FOUND', null),
        AppNotifier.agentVanished,
      );
    });

    // A CLI that predates agent_retarget does not refuse the move — it does not know the FRAME, and
    // backendSocket's default case answers a bare UNSUPPORTED. That is what a stock release still
    // sends, so it has to read as "update", not as a failure the user could retry.
    test('both flavours of "this CLI cannot" ask for the same update', () {
      const update =
          'Update the harness CLI on this machine to move running agents.';
      expect(AppNotifier.retargetMessage('UNSUPPORTED', null), update);
      expect(AppNotifier.retargetMessage('UNSUPPORTED_ON_REMOTE', null), update);
    });

    // A CLI old enough to know agent_retarget but not `clearGrid` sees "own login" — no `grid` key
    // on the wire — as a forgotten field and answers INVALID_GRID with exactly this detail (see
    // backendSocket.ts's pre-clearGrid shape). That is a mixed-deployment failure, not something the
    // user did wrong, so it gets the same update sentence rather than the raw wire text.
    test('own login against a CLI that predates clearGrid asks for the same update', () {
      expect(
        AppNotifier.retargetMessage('INVALID_GRID', 'grid is required'),
        'Update the harness CLI on this machine to move running agents.',
      );
    });

    // Any OTHER INVALID_GRID is a real refusal — a malformed grid, or this app sending both `grid`
    // and `clearGrid` at once — and must keep reading as the CLI's own detail, not get swallowed by
    // the update sentence above.
    test('any other INVALID_GRID detail is shown as-is', () {
      expect(
        AppNotifier.retargetMessage('INVALID_GRID', 'clearGrid and grid are mutually exclusive'),
        'clearGrid and grid are mutually exclusive',
      );
    });

    test('an unknown code prefers the CLI\'s own detail to its wire name', () {
      expect(
        AppNotifier.retargetMessage('SPAWN_FAILED', 'tmux: no server running'),
        'tmux: no server running',
      );
      expect(
        AppNotifier.retargetMessage('SPAWN_FAILED', null),
        'Move failed: SPAWN_FAILED',
      );
    });
  });
}
