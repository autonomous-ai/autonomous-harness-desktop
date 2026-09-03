import 'grid_api_client.dart';
import 'grid_selection_store.dart';

/// Where a newly created agent should send its inference, when the user has
/// picked a grid.
///
/// ⚠️ TODO(BE): THE CLI HAS TO HONOUR THIS, AND TODAY IT DOES NOT.
///
/// This travels as `payload.grid` on the `agent_create` frame. The harness CLI
/// (the `autonomous-harness` repo, not this one) is what actually launches the
/// engine, so it is the CLI that must read this and export the engine's own
/// environment before spawning it — `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN`
/// /`ANTHROPIC_MODEL` for Claude Code, `OPENAI_BASE_URL`/`OPENAI_API_KEY` for
/// Codex, and so on. The relay is OpenAI-compatible, which is what makes that
/// possible at all.
///
/// Until that lands, picking a grid changes what the app SHOWS and nothing
/// about how an engine actually runs. The field is only ever added to the
/// payload when a grid is selected, so a build with no selection sends exactly
/// the frame it sent before this existed.
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
