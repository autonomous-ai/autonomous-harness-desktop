import '../state/app_state.dart';
import 'agent_grid.dart';
import 'grid_agent_override.dart';
import 'grid_selection_store.dart';

/// Moving agents that are already running onto the grid the user just picked.
///
/// Picking a grid cannot reach a live agent on its own: a process's environment is fixed when it is
/// exec'd, so the CLI has to replace the process to change where it sends inference. That is a real
/// restart — the conversation comes back through `--resume`, a turn in flight does not — which is why
/// nothing in here runs by itself. The app finds the agents that are behind, says so, and waits.

/// One running agent that the current selection has left behind.
class StaleAgent {
  const StaleAgent({
    required this.machineId,
    required this.agentId,
    required this.name,
  });

  final String machineId;
  final String agentId;
  final String name;
}

/// Every running agent that is not already on [selection], across every machine.
///
/// Skips engines that cannot be pointed at a grid at all — offering to move a Codex agent would be
/// offering something the CLI is going to refuse, and the New agent dialog already explains why.
/// Skips agents with no live terminal, or none running, for the same reason: moving an agent means
/// re-execing the process it already has, and one that is not running has no process to replace.
List<StaleAgent> agentsNeedingRetarget(
  AppNotifier notifier,
  GridSelection selection,
) {
  final networkId = selection.networkId;
  if (networkId == null || networkId.isEmpty) return const [];
  final stale = <StaleAgent>[];
  for (final entry in notifier.machineStates.entries) {
    for (final agent in entry.value.agents) {
      if (agent.status != 'active') continue;
      if (!agent.terminalAvailable) continue;
      if (!kGridCapableEngines.contains(agent.engine)) continue;
      if (!needsRetarget(agent.grid, networkId, selection.model)) continue;
      stale.add(
        StaleAgent(machineId: entry.key, agentId: agent.id, name: agent.name),
      );
    }
  }
  return stale;
}

/// What happened to one agent.
class RetargetOutcome {
  const RetargetOutcome({required this.name, this.error});

  final String name;

  /// Null when it moved. Otherwise the CLI's own sentence, already readable.
  final String? error;

  bool get moved => error == null;
}

/// Move every agent in [stale] onto [selection], one at a time.
///
/// Sequential on purpose. Each move respawns a pane and then makes the CLI re-read its process table;
/// firing them together would have several agents restarting into the same discovery pass, and a
/// failure would be much harder to attribute to the agent that caused it.
///
/// The relay key is minted ONCE for the batch rather than per agent: it is the same grid for all of
/// them, and a key per agent would be a burst of control-plane calls for no gain.
Future<List<RetargetOutcome>> retargetAgents({
  required AppNotifier notifier,
  required List<StaleAgent> stale,
  required GridSelection selection,
  GridAgentOverride? override,
}) async {
  if (stale.isEmpty) return const [];
  final GridAgentOverride? grid;
  try {
    grid = override ?? await resolveGridAgentOverride(selection: selection);
  } catch (error) {
    // One failure to mint stops the whole batch: without a key there is nothing to move anyone onto,
    // and reporting it once beats reporting it per agent.
    return [
      for (final agent in stale)
        RetargetOutcome(
          name: agent.name,
          error: 'Could not get a key for ${selection.label}: $error',
        ),
    ];
  }
  if (grid == null) return const [];
  final outcomes = <RetargetOutcome>[];
  for (final agent in stale) {
    final error = await notifier.moveAgentToGrid(
      agent.machineId,
      agent.agentId,
      grid,
    );
    // Gone before we reached it — the list refresh below removes the row, and there is nothing here
    // for the user to do about it. Not counted as moved either: it wasn't.
    if (error == AppNotifier.agentVanished) continue;
    outcomes.add(RetargetOutcome(name: agent.name, error: error));
  }
  return outcomes;
}
