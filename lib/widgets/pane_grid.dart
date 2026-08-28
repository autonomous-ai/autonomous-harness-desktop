import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shortcuts/app_shortcuts.dart';
import '../state/app_state.dart';
import '../state/terminal_pane.dart';
import '../theme/app_theme.dart';
import 'agent_drag.dart';
import 'harness_join_guide_screen.dart';
import 'terminal_panel.dart';

/// The terminals, as up to four tiles.
///
/// Fixed shapes rather than a splittable tree. A binary layout tree is what
/// tmux and herdr give you, and it earns its complexity — drag handles, sibling
/// ordering, a serialised shape — only once the count is open-ended. Capped at
/// four, every arrangement anyone would build by hand is already one of the
/// four below, and none of that machinery has to exist or be maintained.
class PaneGrid extends StatelessWidget {
  const PaneGrid({super.key, required this.notifier});

  final AppNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AgentDragRef?>(
      valueListenable: agentDrag,
      builder: (context, dragging, _) {
        final panes = notifier.panes;
        if (panes.isEmpty) {
          return _DropZone(
            notifier: notifier,
            paneId: null,
            dragging: dragging,
            child: const _EmptyGrid(),
          );
        }
        final cells = <Widget>[
          for (final pane in panes)
            _PaneCell(
              key: ValueKey(pane.id),
              notifier: notifier,
              pane: pane,
              dragging: dragging,
            ),
          // Revealed only mid-drag: a permanent "add a tile" cell would halve a
          // single terminal for the whole session to advertise itself.
          if (dragging != null && notifier.canAddPane)
            _DropZone(
              notifier: notifier,
              paneId: null,
              dragging: dragging,
              child: const _AddSlot(),
            ),
        ];
        return _arrange(cells);
      },
    );
  }

  /// Row-major, and the odd count spans rather than leaving a hole: three tiles
  /// are two over one, not two over one-and-a-gap.
  static Widget _arrange(List<Widget> cells) {
    switch (cells.length) {
      case 1:
        return cells[0];
      case 2:
        return LayoutBuilder(
          builder: (context, constraints) {
            // Split the longer side, so two tiles on a wide window are columns
            // and two on a tall one are rows. A terminal's usable size is its
            // column count first, and halving the short axis protects that.
            final side = constraints.maxWidth >= constraints.maxHeight
                ? Axis.horizontal
                : Axis.vertical;
            return side == Axis.horizontal
                ? Row(
                    children: [
                      Expanded(child: cells[0]),
                      Expanded(child: cells[1]),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: cells[0]),
                      Expanded(child: cells[1]),
                    ],
                  );
          },
        );
      case 3:
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: cells[0]),
                  Expanded(child: cells[1]),
                ],
              ),
            ),
            Expanded(child: cells[2]),
          ],
        );
      default:
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: cells[0]),
                  Expanded(child: cells[1]),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: cells[2]),
                  Expanded(child: cells[3]),
                ],
              ),
            ),
          ],
        );
    }
  }
}

class _PaneCell extends StatelessWidget {
  const _PaneCell({
    super.key,
    required this.notifier,
    required this.pane,
    required this.dragging,
  });

  final AppNotifier notifier;
  final TerminalPane pane;
  final AgentDragRef? dragging;

  bool get _single => notifier.panes.length == 1;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final focused = notifier.isPaneFocused(pane.id);
    return Listener(
      // Translucent so the press still reaches the renderer underneath: on
      // macOS the terminal is a WebView and AppKit gives it first responder on
      // its own, so this only has to keep the app's idea of the current tile in
      // step with the one the keyboard already went to.
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => notifier.focusPane(pane.id),
      child: Container(
        decoration: BoxDecoration(
          color: grid.AppPalette.windowBg,
          border: Border.all(
            // Only meaningful with company. A ring around the only tile would
            // be decoration, since there is nowhere else focus could be.
            color: _single
                ? Colors.transparent
                : focused
                ? AppColors.accent
                : AppColors.border,
            width: 1,
          ),
        ),
        child: _DropZone(
          notifier: notifier,
          paneId: pane.id,
          dragging: dragging,
          child: _PaneContent(notifier: notifier, pane: pane, single: _single),
        ),
      ),
    );
  }
}

/// Everything a tile can be, decided per tile.
///
/// This chain used to live in HomeScreen and decide the WHOLE content area from
/// the one selected machine. That is wrong the moment tiles can come from
/// different machines: one machine needing a link would blank three working
/// terminals belonging to two other machines.
class _PaneContent extends StatelessWidget {
  const _PaneContent({
    required this.notifier,
    required this.pane,
    required this.single,
  });

  final AppNotifier notifier;
  final TerminalPane pane;
  final bool single;

  @override
  Widget build(BuildContext context) {
    final machine = notifier.stateOf(pane.machineId);
    void close() => notifier.closePane(pane.id);

    final wantedAgentId = pane.agentId;

    if (machine == null) {
      // The ordinary state of a restored tile for the first moments of a launch,
      // and of a tile whose machine is briefly out of the list.
      return _PaneStatus(
        title: wantedAgentId ?? pane.machineId,
        icon: Icons.hourglass_empty,
        message: 'Waiting for this machine to answer…',
        onClose: single ? null : close,
        busy: true,
      );
    }

    final agentName = wantedAgentId == null
        ? null
        : machine.agents
              .where((agent) => agent.id == wantedAgentId)
              .map((agent) => agent.name)
              .firstOrNull;

    // Deliberately NOT gated on isLinkPromptDismissed: dismissing only suppresses the popup (see
    // showLinkMachineScreenDialog / HomeScreen._maybeShowLinkDialog) — the tile's own status stays
    // honest about the machine actually being unlinked regardless.
    final needsLink =
        machine.isRemote && !machine.isLocalMachine && machine.needsLink;
    if (needsLink) {
      return _PaneStatus(
        title: agentName ?? machine.machine.displayName,
        icon: Icons.link_off,
        message:
            '${machine.machine.displayName} is not linked to this computer yet.',
        onClose: single ? null : close,
      );
    }

    final offline =
        machine.nodeOnline == false ||
        (machine.isLocalMachine && !machine.usesLocalTransport);
    if (offline) {
      return _Guide(
        single: single,
        onClose: close,
        title: agentName ?? machine.machine.displayName,
        compactMessage: machine.isLocalMachine
            ? 'Harness is not running on this computer.'
            : 'Harness is not running on ${machine.machine.displayName}.',
        compactIcon: Icons.cloud_off,
        full: HarnessJoinGuideScreen(
          notifier: notifier,
          machineState: machine,
          agentName: agentName ?? 'selected agent',
        ),
      );
    }

    // A machine tile that has nothing left to report. It arrived to carry a
    // link prompt or a setup form; once those are answered it has said all it
    // has to say, and the person can drag an agent into it.
    if (wantedAgentId == null) {
      return _PaneStatus(
        title: machine.machine.displayName,
        icon: Icons.check_circle_outline,
        message: 'This machine is ready. Drag an agent here to open it.',
        onClose: close,
      );
    }

    if (agentName == null) {
      return _PaneStatus(
        title: wantedAgentId,
        icon: Icons.help_outline,
        message: 'This agent is no longer on ${machine.machine.displayName}.',
        onClose: close,
      );
    }

    final session = pane.session;
    if (session == null) {
      return _PaneStatus(
        title: agentName,
        icon: Icons.hourglass_empty,
        message: 'Attaching…',
        onClose: single ? null : close,
        busy: true,
      );
    }

    return TerminalPanel(
      notifier: notifier,
      session: session,
      focused: notifier.isPaneFocused(pane.id),
      composerVisible: pane.composerVisible,
      onToggleComposer: () => notifier.toggleComposer(pane.id),
      onClose: single ? null : close,
      onRendererFocus: () => notifier.focusPane(pane.id),
    );
  }
}

/// A full-screen guide, but only where one fits.
///
/// The link and join screens are fixed-width cards written for the whole
/// window. In a quarter tile they would overflow rather than shrink, so a tile
/// too small to hold one says the same thing in a sentence. Measured, not
/// counted: a small window has the same problem with a single tile.
class _Guide extends StatelessWidget {
  const _Guide({
    required this.single,
    required this.onClose,
    required this.title,
    required this.compactMessage,
    required this.compactIcon,
    required this.full,
  });

  final bool single;
  final VoidCallback onClose;
  final String title;
  final String compactMessage;
  final IconData compactIcon;
  final Widget full;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final roomForCard =
            constraints.maxWidth >= 520 && constraints.maxHeight >= 430;
        if (roomForCard) {
          if (single) return full;
          return Column(
            children: [
              _PaneHeader(title: title, onClose: onClose),
              Expanded(child: full),
            ],
          );
        }
        return _PaneStatus(
          title: title,
          icon: compactIcon,
          message: compactMessage,
          onClose: single ? null : onClose,
        );
      },
    );
  }
}

/// The same 46pt strip TerminalPanel draws, for the tiles that have no terminal
/// to draw one — so the close button never moves between states.
class _PaneHeader extends StatelessWidget {
  const _PaneHeader({required this.title, this.onClose});

  final String title;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return SizedBox(
      height: 46,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.text,
                  fontFamily: AppFonts.sans,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (onClose != null) PaneCloseButton(onPressed: onClose!),
          ],
        ),
      ),
    );
  }
}

class _PaneStatus extends StatelessWidget {
  const _PaneStatus({
    required this.title,
    required this.icon,
    required this.message,
    this.onClose,
    this.busy = false,
  });

  final String title;
  final IconData icon;
  final String message;
  final VoidCallback? onClose;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Column(
      children: [
        _PaneHeader(title: title, onClose: onClose),
        Divider(height: 1, color: AppColors.border),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(icon, size: 26, color: AppColors.mutedStrong),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.mutedStrong,
                      fontFamily: AppFonts.sans,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Where a dragged rail row can land.
///
/// [paneId] null means "make a new tile"; otherwise the drop replaces what that
/// tile is showing. Hit-testable only while a drag is actually in flight, so an
/// ordinary click still reaches the terminal underneath.
class _DropZone extends StatelessWidget {
  const _DropZone({
    required this.notifier,
    required this.paneId,
    required this.dragging,
    required this.child,
  });

  final AppNotifier notifier;
  final int? paneId;
  final AgentDragRef? dragging;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: dragging == null,
            child: DragTarget<AgentDragRef>(
              onAcceptWithDetails: (details) => notifier.assignAgentToPane(
                paneId,
                details.data.machineId,
                details.data.agentId,
              ),
              builder: (context, candidate, _) => candidate.isEmpty
                  ? const SizedBox.expand()
                  : Container(
                      color: AppColors.accent.withValues(alpha: 0.16),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: grid.AppPalette.panelBg,
                            border: Border.all(color: AppColors.accent),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            paneId == null
                                ? 'Open ${candidate.first?.name ?? 'agent'} here'
                                : 'Show ${candidate.first?.name ?? 'agent'} in this pane',
                            style: TextStyle(
                              color: AppColors.text,
                              fontFamily: AppFonts.sans,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddSlot extends StatelessWidget {
  const _AddSlot();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: grid.AppPalette.windowBg,
        border: Border.all(color: AppColors.border),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 24, color: AppColors.mutedStrong),
            const SizedBox(height: 8),
            Text(
              'Drop here for a new pane',
              style: TextStyle(
                color: AppColors.mutedStrong,
                fontFamily: AppFonts.sans,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyGrid extends StatelessWidget {
  const _EmptyGrid();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ColoredBox(
      color: grid.AppPalette.windowBg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select an agent, or drag one in from the left.',
              style: TextStyle(
                color: AppColors.mutedStrong,
                fontFamily: AppFonts.sans,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            // The empty pane is the one screen a new user is guaranteed to
            // look at, and it is doing nothing else. A sheet behind a key
            // nobody has been told about is a sheet nobody opens.
            Text(
              'Press ${shortcutHintFor(ShortcutAction.showShortcuts)} for '
              'keyboard shortcuts',
              style: TextStyle(
                color: grid.AppPalette.textFaint,
                fontFamily: AppFonts.sans,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
