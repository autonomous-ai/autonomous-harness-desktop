import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';

void main() {
  test('uses explicit terminal availability from a new CLI', () {
    final dormantPane = Agent.fromJson({
      'id': 'agent-1',
      'name': 'Agent',
      'status': 'offline',
      'terminal': {
        'available': true,
        'runtimes': [
          {'backend': 'tmux', 'paneId': '%1'},
        ],
      },
    });
    final stalePane = Agent.fromJson({
      'id': 'agent-2',
      'name': 'Stale',
      'terminal': {
        'available': false,
        'runtimes': [
          {'backend': 'tmux', 'paneId': '%2'},
        ],
      },
    });

    expect(dormantPane.terminalAvailable, isTrue);
    expect(stalePane.terminalAvailable, isFalse);
  });

  test('falls back to tmux runtime presence for an older CLI', () {
    final agent = Agent.fromJson({
      'id': 'agent-1',
      'name': 'Legacy',
      'terminal': {
        'runtimes': [
          {'backend': 'tmux', 'paneId': '%1'},
        ],
      },
    });

    expect(agent.terminalAvailable, isTrue);
  });
}
