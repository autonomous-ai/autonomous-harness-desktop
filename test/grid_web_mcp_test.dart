// Where an agent launched on a grid finds that grid's web tools.
//
// The path is hand-duplicated into grid-apis and the Grid CLI (which pins its
// own half in `tests/test_web_mcp_lockstep.py`), and the trailing slash is the
// difference between a working POST and a 307 — so both are asserted here
// rather than left to be discovered in somebody's terminal.
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/grid/grid_session.dart';
import 'package:harness/grid/grid_web_mcp.dart';

/// A store standing in for a signed-in machine, without touching `~/.grid`.
class _FixedSession extends GridSessionStore {
  _FixedSession(GridSession? session) {
    value = session;
  }
}

void main() {
  test('the mount path is the one the control plane serves', () {
    // ↔ grid-apis `grid_networks/web_mcp.MOUNT_PATH` and the Grid CLI's
    // `cli/mcp_config.py`. Written out rather than read from the constant: a
    // pin that compares a constant to itself checks nothing.
    expect(kGridWebMcpMountPath, '/v1/grid/web-mcp');
  });

  test('a machine with no Grid session still gets the default control plane', () {
    // The agent's own launch does not depend on this app being signed in —
    // the key comes from the payload, not from a local session.
    expect(
      gridWebMcpUrl(session: _FixedSession(null)),
      'https://api-grid.autonomous.ai/v1/grid/web-mcp/',
    );
  });

  test('a CLI pointed at staging sends its agents to staging', () {
    expect(
      gridWebMcpUrl(
        session: _FixedSession(
          const GridSession(token: 't', apiBaseUrl: 'https://api-dev.example'),
        ),
      ),
      'https://api-dev.example/v1/grid/web-mcp/',
    );
  });

  test('the trailing slash survives a base that brought its own', () {
    // Without it the mount answers 307, and not every client follows one.
    expect(
      gridWebMcpUrl(
        session: _FixedSession(
          const GridSession(token: 't', apiBaseUrl: 'https://api-dev.example//'),
        ),
      ),
      'https://api-dev.example/v1/grid/web-mcp/',
    );
  });
}
