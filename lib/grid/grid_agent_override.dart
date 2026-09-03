import 'grid_api_client.dart';
import 'grid_selection_store.dart';

/// Engines the harness CLI can point at a grid, mirroring `GRID_ENGINE_CONTRACTS` in
/// `autonomous-harness/cli/src/lib/gridLaunch.ts`.
///
/// Every one of these has a documented vendor knob for its endpoint — an environment variable, or
/// for Codex a `-c model_providers.*` argument. The engines missing from this list are missing for
/// a reason the CLI states per engine when it refuses: some talk only to their own service (Cursor,
/// Amp, Devin), some need a provider block written into a dotfile this app will not edit (Pi, Kilo),
/// and Antigravity speaks a dialect the relay does not serve.
///
/// Display only. The CLI is the enforcement point — it refuses everything else rather than quietly
/// launching it on its own login — so a stale list here costs a warning that did not appear, never
/// a launch that should have worked. Keep both in sync anyway.
const Set<String> kGridCapableEngines = {
  'claude',
  'codex',
  'copilot',
  'grok',
  'hermes',
  'opencode',
};

/// Where a newly created agent should send its inference, when the user has
/// picked a grid.
///
/// This travels as `payload.grid` on the `agent_create` frame. The harness CLI
/// (the `autonomous-harness` repo, not this one) is what actually launches the
/// engine, so it is the CLI that reads this and hands the new tmux session the
/// engine's own environment — see `cli/src/lib/gridLaunch.ts` there.
///
/// Each engine is pointed at the grid through its own documented knob — see
/// [kGridCapableEngines]. The CLI **refuses** the rest with
/// `GRID_ENGINE_UNSUPPORTED` rather than starting them on their own login, and
/// names the reason for that particular engine.
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
