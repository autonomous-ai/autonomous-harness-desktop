import '../core/models.dart';
import '../state/app_state.dart';
import '../terminal/terminal_session.dart';

/// How a phone status line is coloured. The widgets turn this into a palette colour, so the
/// rules below stay testable without a theme.
enum PhoneTone { good, busy, attention, bad, quiet }

/// A status line: what it says, and how it is coloured.
typedef PhoneSummary = ({String label, PhoneTone tone});

/// What a machine's row says, and so where a tap on it goes.
enum PhoneMachineStatus {
  /// Reachable, but this device holds no link to it yet. A tap asks for THAT machine's remote
  /// password — every machine sets its own.
  needsPassword,

  /// Harness is not running there, so none of its agents can be reached until it is.
  offline,

  /// The socket is still coming up, or its agent list has not answered yet.
  connecting,

  /// Linked and answering: a tap lists its agents.
  ready,
}

PhoneMachineStatus phoneMachineStatusOf(MachineState machine) {
  if (machine.needsLink) return PhoneMachineStatus.needsPassword;
  if (machine.nodeOnline == false) return PhoneMachineStatus.offline;
  final answering =
      machine.connectionStatus == ConnectionStatus.connected &&
      machine.agentLoadStatus != AgentLoadStatus.loading;
  return answering ? PhoneMachineStatus.ready : PhoneMachineStatus.connecting;
}

PhoneSummary phoneMachineSummary(MachineState machine) =>
    switch (phoneMachineStatusOf(machine)) {
      PhoneMachineStatus.needsPassword => (
        label: 'Needs its password',
        tone: PhoneTone.attention,
      ),
      PhoneMachineStatus.offline => (label: 'Offline', tone: PhoneTone.bad),
      PhoneMachineStatus.connecting => (
        label: 'Connecting…',
        tone: PhoneTone.busy,
      ),
      PhoneMachineStatus.ready => (
        label: _agentCount(machine.agents.length),
        tone: PhoneTone.good,
      ),
    };

String _agentCount(int count) => switch (count) {
  0 => 'No agents yet',
  1 => '1 agent',
  _ => '$count agents',
};

/// What an agent is doing, as its row says it. Waiting on the person outranks working, which
/// outranks everything else: it is the one state somebody has to act on.
PhoneSummary phoneAgentSummary(MachineState machine, Agent agent) {
  if (machine.blockedAgents.containsKey(agent.id)) {
    return (label: 'Waiting for you', tone: PhoneTone.attention);
  }
  if (machine.processingAgentIds.contains(agent.id)) {
    return (label: 'Working…', tone: PhoneTone.busy);
  }
  if (!agent.terminalAvailable) {
    return (
      label: agent.terminalUnavailableReason ?? 'No terminal',
      tone: PhoneTone.quiet,
    );
  }
  return (
    label: agent.engineDisplayName ?? agent.engine ?? 'Agent',
    tone: PhoneTone.quiet,
  );
}

/// The terminal's own state, for the header over it. No session yet reads as attaching: the
/// page opens before the pane has one.
PhoneSummary phoneSessionSummary(
  TerminalSession? session,
) => switch (session?.status) {
  null ||
  TerminalSessionStatus.opening => (label: 'Attaching…', tone: PhoneTone.busy),
  TerminalSessionStatus.resyncing => (
    label: 'Resyncing…',
    tone: PhoneTone.busy,
  ),
  TerminalSessionStatus.controlling => (label: 'Live', tone: PhoneTone.good),
  TerminalSessionStatus.takenOver => (
    label: 'Taken over',
    tone: PhoneTone.attention,
  ),
  TerminalSessionStatus.error => (label: 'Disconnected', tone: PhoneTone.bad),
  TerminalSessionStatus.closed => (label: 'Closed', tone: PhoneTone.quiet),
};
