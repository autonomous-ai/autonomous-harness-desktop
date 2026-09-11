import '../core/models.dart';
import '../state/app_state.dart';
import 'phone_status.dart';

/// One agent, together with the machine it runs on.
///
/// The app's state is keyed by machine — `machineStates[id].agents` — which is the right shape for
/// the desktop's rail, where a machine is a heading with its agents under it. The phone's Agents
/// tab asks the other question: *every* agent on the account, whichever machine it is on. This is
/// that flattening, done in one place so the tab, its filter and its badge cannot disagree.
class AgentEntry {
  const AgentEntry({required this.machine, required this.agent});

  final MachineState machine;
  final Agent agent;

  String get machineId => machine.machine.machineId;
  String get machineName => machine.machine.displayName;

  /// Whether this agent is blocked on an answer from the person holding the phone.
  bool get isWaiting => machine.blockedAgents.containsKey(agent.id);

  bool get isWorking => machine.processingAgentIds.contains(agent.id);

  PhoneSummary get summary => phoneAgentSummary(machine, agent);
}

/// Every agent the account can reach, ordered the way the tab draws them.
///
/// Only machines that are LINKED and answering contribute: an offline machine's agent list is
/// whatever was last seen there, and drawing it beside live ones would offer rows that cannot be
/// opened. Those machines are reachable on the Machines tab instead, which is where the thing to
/// do about them lives.
List<AgentEntry> agentIndex(AppNotifier notifier) {
  final entries = <AgentEntry>[];
  for (final machine in notifier.machines) {
    final state = notifier.stateOf(machine.machineId);
    if (state == null) continue;
    if (phoneMachineStatusOf(state) != PhoneMachineStatus.ready) continue;
    for (final agent in state.agents) {
      entries.add(AgentEntry(machine: state, agent: agent));
    }
  }
  return entries;
}

/// The agents waiting on an answer, across every machine.
///
/// This is what the Agents tab's badge counts and what its first section lists. It is the whole
/// reason the phone app exists: somebody is away from their desk and an agent has stopped to ask
/// them something.
List<AgentEntry> waitingAgents(List<AgentEntry> entries) =>
    entries.where((entry) => entry.isWaiting).toList();

/// The rest, with the busy ones first.
///
/// Sorted rather than left in machine order because "working" is the only remaining state that
/// changes on its own — an idle agent will still be idle in a minute, and a row that is moving is
/// the one worth putting where the eye lands.
List<AgentEntry> otherAgents(List<AgentEntry> entries) {
  final rest = entries.where((entry) => !entry.isWaiting).toList();
  rest.sort((a, b) {
    if (a.isWorking != b.isWorking) return a.isWorking ? -1 : 1;
    // Then agents that can actually be opened, so a row with no terminal never heads the list.
    final aOpen = a.agent.terminalAvailable;
    final bOpen = b.agent.terminalAvailable;
    if (aOpen != bOpen) return aOpen ? -1 : 1;
    return 0;
  });
  return rest;
}

/// The machines the filter chips offer, in the order they are drawn.
///
/// Every machine on the account, not just the ready ones: a chip is also how somebody notices that
/// a machine needs its password. A chip for a machine that cannot be opened is drawn disabled by
/// the widget, from [phoneMachineStatusOf].
///
/// ⚠️ **Ordered by what a chip can DO, not by account order.** The rail is one line on a phone and
/// scrolls horizontally, so whatever lands first is the only part most people ever see — and a chip
/// that cannot be tapped is worth nothing there. Account order put the unusable machines first as
/// often as not, pushing the one machine actually running agents off the right edge.
///
/// [PhoneMachineStatus] already ranks them: `ready` is tappable, `connecting` is about to be, and
/// the last two need something done elsewhere before they mean anything here. Ties keep account
/// order, so the row does not reshuffle itself as machines answer.
List<MachineState> filterableMachines(AppNotifier notifier) {
  final states = [
    for (final machine in notifier.machines)
      ?notifier.stateOf(machine.machineId),
  ];
  // A stable sort, which `List.sort` is not — an unstable one would let two ready machines swap
  // places on an unrelated rebuild, moving a chip out from under a finger already reaching for it.
  final indexed = [for (final (index, state) in states.indexed) (index, state)]
    ..sort((a, b) {
      final rank = _chipRank(a.$2).compareTo(_chipRank(b.$2));
      return rank != 0 ? rank : a.$1.compareTo(b.$1);
    });
  return [for (final (_, state) in indexed) state];
}

/// Where a machine's chip sits: lower sorts first.
int _chipRank(MachineState machine) => switch (phoneMachineStatusOf(machine)) {
  PhoneMachineStatus.ready => 0,
  PhoneMachineStatus.connecting => 1,
  // Both need action somewhere else before a chip here can do anything, but a password is
  // something the person holding the phone can fix right now; a machine that is off is not.
  PhoneMachineStatus.needsPassword => 2,
  PhoneMachineStatus.offline => 3,
};
