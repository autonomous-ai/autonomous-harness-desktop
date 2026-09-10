import 'usage_pressure.dart';

/// What the app can actually offer to do about a nearly-spent window.
///
/// Two, and both are things it can *do* — never a third that merely says the
/// limit is close. A warning with nothing to press is a warning the reader can
/// only agree with, and the amber figure on the rail already says that much for
/// free.
enum UsageOfferAction {
  /// Move the agents that are running on this engine's own subscription onto
  /// the provider this computer already defaults to.
  moveAgents,

  /// There is no default provider yet, so the offer is to pick one.
  chooseProvider,
}

/// One agent, as far as this offer is concerned.
///
/// A record rather than the app's `Agent`: what an offer needs to know is three
/// booleans, and taking the model would drag `AppNotifier` into a file that
/// exists to be tested without one.
typedef UsageAgentRow = ({String? engine, bool onProvider, bool busy});

/// How many agents on one engine this offer could actually move.
class UsageAgentTally {
  const UsageAgentTally({
    required this.present,
    required this.candidates,
    required this.movable,
  });

  static const none = UsageAgentTally(present: 0, candidates: 0, movable: 0);

  /// Agents on this engine at all, whatever they are pointed at.
  ///
  /// Evidence that this computer *uses* the engine, which is a different fact
  /// from whether it is spending the subscription right now — and it is the one
  /// that matters when no provider has been chosen, because the next agent
  /// started here launches on that subscription.
  final int present;

  /// Of those, the ones running on the engine's own subscription — the agents
  /// actually spending the window that is about to run out.
  final int candidates;

  /// Of those, the ones not in the middle of a turn.
  ///
  /// The CLI refuses `agent_retarget` for a busy agent (`AGENT_BUSY`), so an
  /// offer counting them would name a number it cannot deliver.
  final int movable;
}

/// Counts [rows] against [engineId].
UsageAgentTally tallyUsageAgents(
  String engineId,
  Iterable<UsageAgentRow> rows,
) {
  var present = 0;
  var candidates = 0;
  var movable = 0;
  for (final row in rows) {
    if (row.engine != engineId) continue;
    present++;
    if (row.onProvider) continue;
    candidates++;
    if (!row.busy) movable++;
  }
  return UsageAgentTally(
    present: present,
    candidates: candidates,
    movable: movable,
  );
}

/// A nearly-spent window, and the one thing worth pressing about it.
class UsageOffer {
  const UsageOffer({
    required this.alert,
    required this.action,
    required this.providerName,
    required this.tally,
  });

  final UsageAlert alert;
  final UsageOfferAction action;

  /// The provider new agents already launch against, or null when there is
  /// none — which is exactly what makes the action [UsageOfferAction.chooseProvider].
  final String? providerName;

  final UsageAgentTally tally;

  /// What is happening, in the reader's terms rather than the API's.
  String get headline =>
      '${alert.provider.label} is ${alert.window.usedPercent.round()}% '
      'through its ${alert.window.label} limit';

  /// Why it is worth doing something about, and by when.
  ///
  /// The countdown leads when there is one: "how long have I got" is the
  /// question a reader asks before "what do I do", and a window with no reset
  /// time simply drops that clause rather than inventing one.
  String get detail {
    final resetsIn = alert.window.resetsInLabel();
    final when = resetsIn == null ? '' : 'It resets in $resetsIn. ';
    return switch (action) {
      UsageOfferAction.moveAgents =>
        '${when}Keep working by moving ${_agents(tally.movable)} to '
            '$providerName.',
      UsageOfferAction.chooseProvider =>
        '${when}Choose a provider and your agents can keep working when it '
            'runs out.',
    };
  }

  /// The button. Says what it will do and to how much, because it does it
  /// immediately — the count is the only warning there is.
  String get actionLabel => switch (action) {
    UsageOfferAction.moveAgents => 'Move ${_agents(tally.movable)}',
    UsageOfferAction.chooseProvider => 'Choose a provider',
  };

  static String _agents(int count) => '$count agent${count == 1 ? '' : 's'}';
}

/// Why there is no offer, when there is none.
///
/// An enum rather than a bare null because "the card is not showing" is
/// otherwise unanswerable from outside: three unrelated facts about the machine
/// produce the identical silence, and they are fixed in three completely
/// different places. A red figure on the rail with nothing beside it reads as a
/// broken feature unless the app can say which of the three it is.
enum UsageOfferBlocked {
  /// This build has no providers at all ([kGridSurfaceEnabled] off), so every
  /// offer would point at a door that is not there.
  noProviders,

  /// No agent here runs on that subscription — whatever is spending it is
  /// somewhere this app cannot reach, and moving nothing would not help.
  noAgents,

  /// A provider is chosen and every candidate is mid-turn, so the one button
  /// worth drawing would be refused by the CLI the moment it was pressed.
  allBusy,
}

/// The offer for [alert], or the reason there is none.
///
/// The rail's amber figure covers every silence here: the reader is told, and
/// is not interrupted to be told something they cannot act on.
({UsageOffer? offer, UsageOfferBlocked? blocked}) resolveUsageOffer({
  required UsageAlert alert,
  required String? providerName,
  required UsageAgentTally tally,
  required bool gridSurface,
}) {
  if (!gridSurface) {
    return (offer: null, blocked: UsageOfferBlocked.noProviders);
  }
  final hasProvider = (providerName ?? '').isNotEmpty;
  // ⚠️ The two offers ask DIFFERENT questions of the tally, and reading both
  // off `candidates` was a real hole: a computer whose only Codex agent had
  // been moved onto a provider by hand watched that account climb to 97% and
  // was offered nothing — while `New agent` would have launched the next one
  // straight onto the spent subscription, because no DEFAULT had been picked.
  // Moving asks "what is on that subscription now"; choosing a default asks
  // "does this computer use that engine at all", and an agent parked on a
  // provider answers yes.
  final enough = hasProvider ? tally.candidates : tally.present;
  if (enough == 0) return (offer: null, blocked: UsageOfferBlocked.noAgents);
  if (hasProvider && tally.movable == 0) {
    return (offer: null, blocked: UsageOfferBlocked.allBusy);
  }
  return (
    offer: UsageOffer(
      alert: alert,
      action: hasProvider
          ? UsageOfferAction.moveAgents
          : UsageOfferAction.chooseProvider,
      providerName: hasProvider ? providerName : null,
      tally: tally,
    ),
    blocked: null,
  );
}
