import 'grid_session.dart';

/// The control plane's web-tools MCP mount.
///
/// ⚠️ Hand-duplicated across three repositories with no import path between
/// them: grid-apis' `grid_networks/web_mcp.MOUNT_PATH`, the Grid CLI's
/// `cli/mcp_config.py`, and here. The Grid CLI pins its half with
/// `tests/test_web_mcp_lockstep.py`; ours is `test/grid_web_mcp_test.dart`.
/// A path that drifts answers a bare 404, which a harness reports as a server
/// it cannot reach — in the user's terminal, long after the deploy.
const kGridWebMcpMountPath = '/v1/grid/web-mcp';

/// Where an agent launched on a grid finds that grid's web tools.
///
/// The **control plane**, not the relay, and grid ADR 0041 D-a is emphatic
/// about why: a relay is per-grid, is a machine that can be asleep, and for a
/// self-hosted grid is a LAN address the harness may never reach. Attribution
/// survives the move because `network_id` is a claim inside the token.
///
/// Built from the session's own [GridSession.apiBaseUrl] rather than the
/// constant, so a developer whose `grid` is signed into staging points their
/// agents at staging's web tools instead of sending a staging token to
/// production — the same reason `GridApiClient` reads that field per request.
///
/// ⚠️ The trailing slash is load-bearing: without it the mount answers **307**,
/// and not every client follows a redirect for a POST.
String gridWebMcpUrl({GridSessionStore? session}) {
  final base = (session ?? gridSessionStore).value?.apiBaseUrl;
  final root = (base == null || base.isEmpty) ? kGridApiBaseUrl : base;
  return '${root.replaceAll(RegExp(r'/+$'), '')}$kGridWebMcpMountPath/';
}
