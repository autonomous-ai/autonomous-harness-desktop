import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart';
import '../state/app_state.dart';
import '../widgets/engine_identity.dart';
import '../widgets/terminal_panel.dart';
import 'phone_header.dart';
import 'phone_status.dart';
import 'status_pill.dart';

/// One agent's terminal, filling the phone. The header says whose it is and whether it is live;
/// everything below it is the same [TerminalPanel] a desktop tile draws, minus that tile's own
/// header.
class TerminalPage extends StatelessWidget {
  const TerminalPage({
    super.key,
    required this.notifier,
    required this.machineId,
    required this.agentId,
  });

  final AppNotifier notifier;
  final String machineId;
  final String agentId;

  @override
  Widget build(BuildContext context) {
    // Clear of the home indicator — except while the keyboard is up, which already is.
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) {
        AppTheme.watch(context);
        final pane = notifier.panes
            .where((p) => p.machineId == machineId && p.agentId == agentId)
            .firstOrNull;
        final session = pane?.session;
        final machine = notifier.stateOf(machineId);
        final agent = machine?.agents.where((a) => a.id == agentId).firstOrNull;
        final status = phoneSessionSummary(session);
        return Scaffold(
          backgroundColor: AppPalette.windowBg,
          body: SafeArea(
            bottom: !keyboardUp,
            child: Column(
              children: [
                PhoneHeader(
                  title: agent?.name ?? 'Agent',
                  leading: EngineMark(
                    engine: agent?.engine,
                    displayName: agent?.engineDisplayName,
                    size: 22,
                  ),
                  subtitle: StatusPill(
                    fontSize: 12,
                    summary: (
                      label:
                          '${machine?.machine.displayName ?? ''} · ${status.label}',
                      tone: status.tone,
                    ),
                  ),
                ),
                Divider(height: 1, color: AppGlass.hair),
                Expanded(
                  child: pane == null || session == null
                      ? const _Attaching()
                      : TerminalPanel(
                          key: ValueKey(pane.id),
                          notifier: notifier,
                          session: session,
                          focused: true,
                          showHeader: false,
                          composerVisible: pane.composerVisible,
                          onToggleComposer: () =>
                              notifier.toggleComposer(pane.id),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Attaching extends StatelessWidget {
  const _Attaching();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppPalette.accent,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Attaching to the agent…',
          style: TextStyle(color: AppPalette.textSecondary, fontSize: 14),
        ),
      ],
    ),
  );
}
