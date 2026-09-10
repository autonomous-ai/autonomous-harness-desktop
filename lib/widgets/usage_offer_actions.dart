/// Turning a nearly-spent rate-limit window into something the app can do.
///
/// The seam between two halves that must not know about each other: the pure
/// model in `usage/usage_offer.dart`, which decides *whether* there is an offer
/// and what it says, and the two surfaces that draw it — the strip above the
/// status rail and the rail's own hover panel. Both call these, so an offer
/// cannot mean one thing in one place and something else in the other.
library;

import 'package:flutter/material.dart';

import '../analytics/analytics.dart';
import '../grid/grid_selection_store.dart';
import '../grid/grid_surface.dart';
import '../grid/model_picker_options.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_section.dart';
import '../state/app_state.dart';
import '../usage/usage_offer.dart';
import '../usage/usage_pressure.dart';
import '../usage/usage_window.dart';
import 'agent_model_menu.dart';

/// How many of [provider]'s agents are running on its own subscription here,
/// and how many of those could be moved right now.
UsageAgentTally usageTallyFor(AppNotifier notifier, UsageProvider provider) =>
    tallyUsageAgents(provider.engineId, [
      for (final machine in notifier.machineStates.values)
        for (final agent in machine.agents)
          (
            engine: agent.engine,
            // An agent already on a provider is not spending the subscription
            // this window belongs to, so it is neither a candidate nor a
            // problem — moving it would change nothing about the figure.
            onProvider: agent.grid != null,
            busy: machine.processingAgentIds.contains(agent.id),
          ),
    ]);

/// The offer for [alert], or null when there is nothing worth pressing.
///
/// [gridSurface] and [selection] are injection points, defaulted to what the
/// app actually reads. They are NOT `@visibleForTesting`: the notice forwards
/// its own injected stores through here, and a production caller passing a
/// store it was handed is the ordinary case rather than the exception.
({UsageOffer? offer, UsageOfferBlocked? blocked}) usageOfferOf(
  AppNotifier notifier,
  UsageAlert alert, {
  bool gridSurface = kGridSurfaceEnabled,
  GridSelectionStore? selection,
}) => resolveUsageOffer(
  alert: alert,
  providerName: (selection ?? gridSelectionStore).value.networkName,
  tally: usageTallyFor(notifier, alert.provider),
  gridSurface: gridSurface,
);

/// Do what [offer] says it will.
///
/// One function for both surfaces, for the reason `pickAgentModel` is one
/// function for the pill and ⇧⌘M: two copies of a move are two places for its
/// refusals to drift apart.
Future<void> runUsageOffer(
  BuildContext context,
  AppNotifier notifier,
  UsageOffer offer, {
  GridSelectionStore? selection,
}) async {
  analytics.usageLimitOffer(
    provider: offer.alert.provider.name,
    action: offer.action.name,
    agents: offer.tally.movable,
  );
  if (offer.action == UsageOfferAction.chooseProvider) {
    await showSettingsScreen(
      context,
      notifier,
      initialSection: SettingsSection.grid,
    );
    return;
  }
  await moveAgentsToDefaultProvider(
    context,
    notifier,
    offer.alert.provider,
    selection: selection,
  );
}

/// Move every idle agent of [provider] onto the provider new agents already
/// launch against.
///
/// Sequential rather than a `Future.wait`, and deliberately: each move restarts
/// an engine on the machine it lives on, and firing four at once at one CLI
/// gives the daemon four respawns to interleave for no gain — nobody is waiting
/// on the fourth pane before they can read the first.
///
/// ⚠️ The list is snapshotted BEFORE the first move. `applyAgentModel` reloads
/// the machine's agents on success, so iterating the live collection would walk
/// a list that is being rebuilt underneath it.
Future<void> moveAgentsToDefaultProvider(
  BuildContext context,
  AppNotifier notifier,
  UsageProvider provider, {
  GridSelectionStore? selection,
}) async {
  final target = (selection ?? gridSelectionStore).value;
  if (!target.hasGrid) return;
  final choice = ModelChoice(
    networkId: target.networkId,
    networkName: target.networkName ?? '',
    // Auto: the provider routes for itself. A move made to get past a spent
    // subscription is not the moment to also pin a model the user did not ask
    // for — and Auto is what every new agent launches on anyway.
  );
  final moving = <({String machineId, String agentId})>[
    for (final machine in notifier.machineStates.values)
      for (final agent in machine.agents)
        if (agent.engine == provider.engineId &&
            agent.grid == null &&
            !machine.processingAgentIds.contains(agent.id))
          (machineId: machine.machine.machineId, agentId: agent.id),
  ];
  for (final agent in moving) {
    if (!context.mounted) return;
    await applyAgentModel(
      context,
      notifier,
      machineId: agent.machineId,
      agentId: agent.agentId,
      choice: choice,
    );
  }
}
