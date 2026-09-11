import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../shared/theme/app_theme.dart';
import '../shared/widgets/empty_state.dart';
import '../state/app_state.dart';
import 'agent_hero.dart';
import 'agent_index.dart';
import 'agent_row.dart';
import 'account_button.dart';
import 'machine_filter_bar.dart';
import 'phone_card.dart';
import 'phone_header.dart';
import 'phone_navigation.dart';
import 'phone_status.dart';

/// Every agent on the account, whichever machine it runs on.
///
/// The phone's home, and the direction's whole bet: people remember what an agent is CALLED, not
/// which computer it happens to be on. The machine is still there — as a filter above the list and
/// as a line under each name — it just stops being the thing you have to navigate through first.
class AgentsTab extends StatefulWidget {
  const AgentsTab({super.key, required this.notifier});

  final AppNotifier notifier;

  @override
  State<AgentsTab> createState() => _AgentsTabState();
}

class _AgentsTabState extends State<AgentsTab> {
  /// The machine the list is narrowed to, or null for all of them.
  ///
  /// Held as an id rather than a [MachineState]: the state objects are rebuilt as machines answer,
  /// and a filter holding a stale instance would quietly stop matching anything.
  String? _machineId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.notifier,
    builder: (context, _) {
      AppTheme.watch(context);
      final machines = filterableMachines(widget.notifier);
      // A machine that goes away — unlinked, or dropped from the account — must not leave the list
      // filtered to nothing with no way to see it is.
      final selected = machines.any((m) => m.machine.machineId == _machineId)
          ? _machineId
          : null;
      final all = agentIndex(widget.notifier);
      final shown = selected == null
          ? all
          : all.where((entry) => entry.machineId == selected).toList();
      final error = widget.notifier.lastError;
      return Scaffold(
        backgroundColor: AppPalette.windowBg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              PhoneHeader(
                large: true,
                title: 'Agents',
                trailing: [AccountButton(notifier: widget.notifier)],
              ),
              if (error != null)
                _ErrorStrip(message: error, notifier: widget.notifier),
              if (machines.isNotEmpty)
                MachineFilterBar(
                  machines: machines,
                  selectedId: selected,
                  countFor: (id) =>
                      all.where((entry) => entry.machineId == id).length,
                  totalCount: all.length,
                  onSelect: (id) => setState(() => _machineId = id),
                ),
              Expanded(
                child: _Body(
                  notifier: widget.notifier,
                  entries: shown,
                  machines: machines,
                  filtered: selected != null,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Body extends StatelessWidget {
  const _Body({
    required this.notifier,
    required this.entries,
    required this.machines,
    required this.filtered,
  });

  final AppNotifier notifier;
  final List<AgentEntry> entries;
  final List<MachineState> machines;
  final bool filtered;

  /// Whether anything is still on its way in — a machine connecting, or its agent list not yet
  /// answered. "Loading" and "answered with nothing" must not render the same.
  bool get _stillArriving => machines.any(
    (machine) => switch (phoneMachineStatusOf(machine)) {
      PhoneMachineStatus.connecting => true,
      _ => false,
    },
  );

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      if (notifier.machines.isEmpty && notifier.machinesLoading) {
        return const PhoneListSkeleton();
      }
      if (notifier.machines.isEmpty) {
        return const EmptyState(
          icon: LucideIcons.laptopMinimal300,
          title: 'No machines yet',
          message:
              'Run Harness on a computer signed in to this account and it '
              'will appear here.',
        );
      }
      if (_stillArriving) return const PhoneListSkeleton();
      if (filtered) {
        return const EmptyState(
          icon: LucideIcons.squareTerminal300,
          title: 'No agents on this machine',
          message: 'Start one from Harness there and it will appear here.',
        );
      }
      // Machines exist and have answered, but none of them can be reached — every one needs its
      // password or is offline. The Machines tab is where that is fixed, so say so.
      final reachable = machines.any(
        (machine) => phoneMachineStatusOf(machine) == PhoneMachineStatus.ready,
      );
      if (!reachable) {
        return const EmptyState(
          icon: LucideIcons.lockKeyhole300,
          title: 'No machines are open yet',
          message:
              'Open the Machines tab to enter a machine password, or start '
              'Harness on a computer that is offline.',
        );
      }
      return const EmptyState(
        icon: LucideIcons.squareTerminal300,
        title: 'No agents yet',
        message: 'Start one from Harness on a machine and it will appear here.',
      );
    }

    final waiting = waitingAgents(entries);
    final rest = otherAgents(entries);
    return RefreshIndicator(
      onRefresh: notifier.retryMachines,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: phoneListPadding(context),
        children: [
          if (waiting.isNotEmpty) ...[
            const _SectionLabel('Waiting for you'),
            for (final entry in waiting) _row(context, entry),
            const SizedBox(height: 6),
          ],
          if (rest.isNotEmpty) ...[
            if (waiting.isNotEmpty) const _SectionLabel('All agents'),
            for (final entry in rest) _row(context, entry),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, AgentEntry entry) => Padding(
    padding: const EdgeInsets.only(bottom: kPhoneCardGap),
    child: AgentRow(
      entry: entry,
      onTap: () => openAgent(
        context,
        notifier,
        entry.machineId,
        entry.agent.id,
        heroSource: AgentHeroSource.agents,
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: AppPalette.textFaint,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ErrorStrip extends StatelessWidget {
  const _ErrorStrip({required this.message, required this.notifier});

  final String message;
  final AppNotifier notifier;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
      child: Row(
        children: [
          Icon(LucideIcons.circleAlert300, size: 18, color: AppPalette.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppPalette.textSecondary, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: notifier.retryMachines,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
