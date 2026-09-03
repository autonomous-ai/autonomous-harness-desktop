import 'grid_api_client.dart';
import 'grid_selection_store.dart';

/// Engines the harness CLI can point at a grid, mirroring `GRID_ENGINE_ENV` in
/// `autonomous-harness/cli/src/lib/gridLaunch.ts`.
///
/// Display only. The CLI is the enforcement point — it refuses every other engine rather than
/// quietly launching it on its own login — so a stale list here costs a warning that did not
/// appear, never a launch that should have worked. Keep both in sync anyway.
const Set<String> kGridCapableEngines = {'claude'};

/// Where a newly created agent should send its inference, when the user has
/// picked a grid.
///
/// This travels as `payload.grid` on the `agent_create` frame. The harness CLI
/// (the `autonomous-harness` repo, not this one) is what actually launches the
/// engine, so it is the CLI that reads this and hands the new tmux session the
/// engine's own environment — see `cli/src/lib/gridLaunch.ts` there.
///
/// **Claude Code is the only engine that can be pointed at a grid**
/// (`ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN`/`ANTHROPIC_MODEL`). The CLI
/// **refuses** every other one with `GRID_ENGINE_UNSUPPORTED` rather than
/// starting it on its own login: the Codex CLI and its peers are configured by
/// a config file, not the environment, and writing another tool's config on a
/// user's behalf outlives the agent. [kGridCapableEngines] mirrors that list so
/// the New agent dialog can say so before the click.
///
/// The field is only ever added to the payload when a grid is selected, so a
/// build with no selection sends exactly the frame it sent before this existed.
class GridAgentOverride {
  const GridAgentOverride({
    required this.networkId,
    required this.networkName,
    required this.baseUrl,
    required this.apiKey,
    this.model,
  });

  final String networkId;
  final String networkName;

  /// The OpenAI-compatible relay root for this grid.
  final String baseUrl;

  /// Minted for this launch — see [GridCredentials]. Short-lived on purpose.
  final String apiKey;

  /// Null means "let the grid choose", which is the relay's own default.
  final String? model;

  Map<String, dynamic> toJson() => {
    'networkId': networkId,
    'networkName': networkName,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    if (model != null) 'model': model,
  };
}

/// Turns the saved [GridSelection] into an override, minting a relay key for
/// it.
///
/// Null when no grid is picked — the caller then creates the agent exactly the
/// way it always did. Throws when a grid IS picked and the key cannot be
/// minted, because launching against the engine's own login instead would be a
/// silent substitution of the thing the user asked for.
Future<GridAgentOverride?> resolveGridAgentOverride({
  GridApiClient? client,
  GridSelection? selection,
}) async {
  final chosen = selection ?? gridSelectionStore.value;
  final networkId = chosen.networkId;
  if (networkId == null || networkId.isEmpty) return null;
  final credentials = await (client ?? GridApiClient()).credentials(networkId);
  return GridAgentOverride(
    networkId: networkId,
    networkName: chosen.label,
    baseUrl: credentials.baseUrl,
    apiKey: credentials.apiKey,
    model: chosen.model,
  );
}
