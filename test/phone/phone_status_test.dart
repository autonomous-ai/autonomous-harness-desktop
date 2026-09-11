import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/phone/phone_status.dart';
import 'package:harness/state/app_state.dart';

MachineState _machine({
  bool needsLink = false,
  bool? nodeOnline = true,
  ConnectionStatus connection = ConnectionStatus.connected,
  AgentLoadStatus load = AgentLoadStatus.loaded,
  int agents = 0,
}) =>
    MachineState(
        const Machine(
          machineId: 'm1',
          apiKey: '',
          authMode: MachineAuthMode.remote,
          name: 'box',
        ),
      )
      ..needsLink = needsLink
      ..nodeOnline = nodeOnline
      ..connectionStatus = connection
      ..agentLoadStatus = load
      ..agents = [for (var i = 0; i < agents; i++) _agent('a$i')];

Agent _agent(String id) => Agent.fromJson({
  'id': id,
  'name': id,
  'engine': 'claude',
  'terminal': {
    'runtimes': [
      {'backend': 'tmux', 'paneId': '%1'},
    ],
  },
});

void main() {
  group('a machine row', () {
    test('asks for the password before anything else — even offline', () {
      final machine = _machine(needsLink: true, nodeOnline: false);
      expect(phoneMachineStatusOf(machine), PhoneMachineStatus.needsPassword);
      expect(phoneMachineSummary(machine).tone, PhoneTone.attention);
    });

    test('says offline when Harness is not running there', () {
      final machine = _machine(nodeOnline: false);
      expect(phoneMachineStatusOf(machine), PhoneMachineStatus.offline);
      expect(phoneMachineSummary(machine), (
        label: 'Offline',
        tone: PhoneTone.bad,
      ));
    });

    test(
      'is connecting until the socket is up and the agent list has answered',
      () {
        expect(
          phoneMachineStatusOf(
            _machine(connection: ConnectionStatus.connecting),
          ),
          PhoneMachineStatus.connecting,
        );
        expect(
          phoneMachineStatusOf(_machine(load: AgentLoadStatus.loading)),
          PhoneMachineStatus.connecting,
        );
      },
    );

    test('counts its agents once it is ready', () {
      expect(phoneMachineSummary(_machine()).label, 'No agents yet');
      expect(phoneMachineSummary(_machine(agents: 1)).label, '1 agent');
      expect(phoneMachineSummary(_machine(agents: 3)), (
        label: '3 agents',
        tone: PhoneTone.good,
      ));
    });
  });

  test('an agent at work says so; an idle one names its engine quietly', () {
    final machine = _machine(agents: 2);
    machine.processingAgentIds.add('a0');
    expect(phoneAgentSummary(machine, machine.agents[0]), (
      label: 'Working…',
      tone: PhoneTone.busy,
    ));
    expect(phoneAgentSummary(machine, machine.agents[1]).tone, PhoneTone.quiet);
  });

  test('a page with no session yet reads as attaching', () {
    expect(phoneSessionSummary(null), (
      label: 'Attaching…',
      tone: PhoneTone.busy,
    ));
  });
}
