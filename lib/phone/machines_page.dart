import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart';
import '../shared/widgets/empty_state.dart';
import '../state/app_state.dart';
import 'account_button.dart';
import 'machine_tile.dart';
import 'phone_card.dart';
import 'phone_header.dart';
import 'phone_navigation.dart';

/// The phone's first screen after sign-in: every machine on the account, and which of them this
/// phone can open. Choosing one is the first thing anybody does here — each machine is linked
/// with its own password, so there is no sensible machine to open on for them.
class MachinesPage extends StatelessWidget {
  const MachinesPage({super.key, required this.notifier});

  final AppNotifier notifier;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: notifier,
    builder: (context, _) {
      AppTheme.watch(context);
      final error = notifier.lastError;
      return Scaffold(
        backgroundColor: AppPalette.windowBg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              PhoneHeader(
                large: true,
                title: 'Machines',
                subtitle: Text(
                  notifier.currentUser?.email ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppPalette.textSecondary,
                    fontSize: 14,
                  ),
                ),
                trailing: [AccountButton(notifier: notifier)],
              ),
              if (error != null)
                _ErrorStrip(message: error, notifier: notifier),
              Expanded(child: _MachinesBody(notifier: notifier)),
            ],
          ),
        ),
      );
    },
  );
}

class _MachinesBody extends StatelessWidget {
  const _MachinesBody({required this.notifier});

  final AppNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final machines = notifier.machines;
    if (machines.isEmpty && notifier.machinesLoading) {
      return const PhoneListSkeleton();
    }
    if (machines.isEmpty) {
      return const EmptyState(
        icon: Icons.computer_rounded,
        title: 'No machines yet',
        message:
            'Run Harness on a computer signed in to this account and it will '
            'appear here.',
      );
    }
    return PhoneCardList(
      onRefresh: notifier.retryMachines,
      itemCount: machines.length,
      itemBuilder: (context, index) {
        final machineId = machines[index].machineId;
        final machine = notifier.stateOf(machineId);
        if (machine == null) return const SizedBox.shrink();
        return MachineTile(
          machine: machine,
          onTap: () => openMachine(context, notifier, machineId),
        );
      },
    );
  }
}

class _ErrorStrip extends StatelessWidget {
  const _ErrorStrip({required this.message, required this.notifier});

  final String message;
  final AppNotifier notifier;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
    child: Row(
      children: [
        Icon(Icons.error_outline_rounded, size: 18, color: AppPalette.warn),
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
