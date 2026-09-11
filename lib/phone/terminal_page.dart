import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../shared/theme/app_theme.dart';
import '../shared/widgets/app_icon_button.dart';
import '../state/app_state.dart';
import '../widgets/engine_identity.dart';
import '../widgets/rename_agent_dialog.dart';
import '../widgets/terminal_panel.dart';
import 'agent_hero.dart';
import 'phone_header.dart';
import 'phone_sheet.dart';
import 'phone_status.dart';
import 'status_pill.dart';
import 'terminal_key_bar.dart';

/// One agent's terminal, filling the phone. The header says whose it is and whether it is live;
/// everything below it is the same [TerminalPanel] a desktop tile draws, minus that tile's own
/// header — plus the key row a software keyboard cannot provide.
///
/// A pushed page, so the tab bar is covered: the bottom of this screen belongs to the composer and
/// the keys, and a nav bar under them would put three rows of chrome in the thumb's way.
class TerminalPage extends StatefulWidget {
  const TerminalPage({
    super.key,
    required this.notifier,
    required this.machineId,
    required this.agentId,
    required this.heroSource,
  });

  final AppNotifier notifier;
  final String machineId;
  final String agentId;

  /// Which list opened this page — one half of the engine mark's Hero tag, so the flight pairs with
  /// the row it came from rather than an identical row in the other mounted tab.
  final AgentHeroSource heroSource;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  /// Whether this page's pane ever existed.
  ///
  /// ⚠️ Load-bearing, and the reason this page is stateful at all. The page is pushed BEFORE the
  /// attach — that is what lets it say "Attaching…" — so a null pane means two opposite things
  /// depending on when it is seen: not yet (wait) or no longer (leave).
  ///
  /// Without the distinction, the second case renders as a spinner that never resolves. It is
  /// reachable in normal use now that two tabs can each open a terminal: `openAgent` keeps exactly
  /// one pane, so opening an agent from the Machines tab closes the pane belonging to a
  /// TerminalPage still sitting in the Agents tab's stack.
  bool _hadPane = false;

  @override
  Widget build(BuildContext context) {
    // Clear of the home indicator — except while the keyboard is up, which already is.
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    return ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, _) {
        AppTheme.watch(context);
        final pane = widget.notifier.panes
            .where(
              (p) =>
                  p.machineId == widget.machineId &&
                  p.agentId == widget.agentId,
            )
            .firstOrNull;
        if (pane != null) {
          _hadPane = true;
        } else if (_hadPane) {
          // The pane this page was showing is gone — another tab opened a different agent, or the
          // agent was deleted. Leave rather than spin: there is nothing here to come back.
          _leave();
        }
        final session = pane?.session;
        final machine = widget.notifier.stateOf(widget.machineId);
        final agent = machine?.agents
            .where((a) => a.id == widget.agentId)
            .firstOrNull;
        final status = phoneSessionSummary(session);
        return Scaffold(
          backgroundColor: AppPalette.windowBg,
          body: SafeArea(
            bottom: !keyboardUp,
            child: Column(
              children: [
                // The header alone carries the flight — see [AgentHeroHeader]. Only once the agent
                // is known: the row's end of the flight is built from the agent, and a flight begun
                // against a placeholder would land on content that then changes under it.
                AgentHeroHeader(
                  tag: agent == null
                      ? null
                      : agentHeroTag(
                          machineId: widget.machineId,
                          agentId: widget.agentId,
                          source: widget.heroSource,
                        ),
                  child: PhoneHeader(
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
                    trailing: [
                      // Null while the agent is not loaded: there is nothing to act on yet, and a
                      // menu of actions that all fail is worse than no menu.
                      if (agent != null)
                        AppIconButton(
                          icon: LucideIcons.ellipsis300,
                          size: 20,
                          tooltip: 'Agent actions',
                          color: AppPalette.textSecondary,
                          onPressed: () => _showActions(
                            machineName: machine?.machine.displayName ?? '',
                            agentName: agent.name,
                          ),
                        ),
                    ],
                  ),
                ),
                // Everything under the header arrives after the flight lands, rising a little into
                // place — see [AgentBodyReveal]. Drawn full-screen from the first frame it would be
                // a second layer crossing the header still in flight, which is what made the old
                // whole-page version flash.
                Expanded(
                  child: AgentBodyReveal(
                    child: Column(
                      children: [
                        Divider(height: 1, color: AppGlass.hair),
                        Expanded(
                          child: pane == null || session == null
                              ? const _Attaching()
                              : TerminalPanel(
                                  key: ValueKey(pane.id),
                                  notifier: widget.notifier,
                                  session: session,
                                  focused: true,
                                  showHeader: false,
                                  composerVisible: pane.composerVisible,
                                  onToggleComposer: () =>
                                      widget.notifier.toggleComposer(pane.id),
                                ),
                        ),
                        if (session != null) ...[
                          Divider(height: 1, color: AppGlass.hair),
                          TerminalKeyBar(
                            // Read from the session on every build rather than captured: a resync
                            // replaces the session's `terminal` outright, and a row holding the old
                            // one would send its keys into a detached buffer nobody is looking at.
                            terminal: session.terminal,
                            enabled: session.acceptsInput,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Pops after the frame: this runs from inside a build, where popping a route synchronously is
  /// not allowed.
  void _leave() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.pop();
    });
  }

  void _showActions({required String machineName, required String agentName}) {
    showPhoneSheet(
      context,
      title: '$agentName · $machineName',
      actions: [
        PhoneSheetAction(
          icon: LucideIcons.pencil300,
          label: 'Rename agent…',
          onTap: () => showAgentRenameDialog(
            context,
            widget.notifier,
            widget.machineId,
            widget.agentId,
            agentName,
          ),
        ),
        PhoneSheetAction(
          icon: LucideIcons.refreshCw300,
          label: 'Restart agent',
          onTap: () => unawaited(_restart()),
        ),
      ],
    );
  }

  /// Restarting is a round trip that can fail, and the phone has no status rail to fail into — so
  /// the answer lands as a snackbar, which is the one surface a pushed page here always has.
  Future<void> _restart() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await widget.notifier.restartAgent(
      widget.machineId,
      widget.agentId,
    );
    final error = result.error;
    if (error == null || messenger == null || !mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(error)));
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
