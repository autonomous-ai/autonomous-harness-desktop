import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart';
import '../shared/widgets/empty_state.dart';
import '../state/app_state.dart';
import 'agent_tile.dart';
import 'link_page.dart';
import 'phone_card.dart';
import 'phone_header.dart';
import 'phone_navigation.dart';
import 'phone_status.dart';
import 'status_pill.dart';

/// One machine's agents. A tap opens that agent full screen, and it is the only one open.
class AgentsPage extends StatelessWidget {
  const AgentsPage({
    super.key,
    required this.notifier,
    required this.machineId,
  });

  final AppNotifier notifier;
  final String machineId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: notifier,
    builder: (context, _) {
      AppTheme.watch(context);
      final machine = notifier.stateOf(machineId);
      return Scaffold(
        backgroundColor: AppPalette.windowBg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              PhoneHeader(
                title: machine?.machine.displayName ?? 'Machine',
                subtitle: machine == null
                    ? null
                    : StatusPill(summary: phoneMachineSummary(machine)),
              ),
              if (machine != null)
                Expanded(
                  child: _AgentsBody(notifier: notifier, machine: machine),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _AgentsBody extends StatelessWidget {
  const _AgentsBody({required this.notifier, required this.machine});

  final AppNotifier notifier;
  final MachineState machine;

  String get _machineId => machine.machine.machineId;

  @override
  Widget build(BuildContext context) {
    final agents = machine.agents;
    final status = phoneMachineStatusOf(machine);
    if (status == PhoneMachineStatus.needsPassword) {
      return EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'This machine needs its password',
        message: 'Every machine has its own. Enter it once to link this phone.',
        action: FilledButton(
          onPressed: () => Navigator.of(context).pushReplacement(
            phoneRoute(
              (_) => LinkPage(notifier: notifier, machineId: _machineId),
            ),
          ),
          child: const Text('Enter password'),
        ),
      );
    }
    if (status == PhoneMachineStatus.offline) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: "Harness isn't running there",
        message:
            'Start Harness on ${machine.machine.displayName} and its agents '
            'will show up here.',
      );
    }
    if (agents.isEmpty && status == PhoneMachineStatus.connecting) {
      return const PhoneListSkeleton();
    }
    final loadError = machine.agentsLoadError;
    if (agents.isEmpty && loadError != null) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: "Couldn't load its agents",
        message: loadError,
        action: FilledButton(
          onPressed: () => notifier.reloadMachineData(_machineId),
          child: const Text('Try again'),
        ),
      );
    }
    if (agents.isEmpty) {
      return const EmptyState(
        icon: Icons.smart_toy_outlined,
        title: 'No agents yet',
        message:
            'Start one from Harness on that machine and it will appear here.',
      );
    }
    return PhoneCardList(
      onRefresh: () => notifier.reloadMachineData(_machineId),
      itemCount: agents.length,
      itemBuilder: (context, index) => AgentTile(
        machine: machine,
        agent: agents[index],
        onTap: () => openAgent(context, notifier, _machineId, agents[index].id),
      ),
    );
  }
}
