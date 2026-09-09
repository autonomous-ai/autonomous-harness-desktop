import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../theme/app_theme.dart';
import '../usage/usage_controller.dart';
import '../widgets/layout_palette.dart';
import '../widgets/link_machine_screen.dart';
import '../widgets/agent_model_menu.dart';
import '../widgets/machine_rail.dart';
import '../widgets/machine_rail_mini.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_section.dart';
import '../shortcuts/app_shortcuts.dart';
import '../widgets/new_agent_dialog.dart';
import '../widgets/task_palette.dart';
import '../widgets/pane_grid.dart';
import '../widgets/shortcuts_sheet.dart';
import '../widgets/status_rail/grid_status_rail.dart';
import '../widgets/usage_limit_notice.dart';
import '../widgets/window_chrome.dart';

class HomeScreen extends StatefulWidget {
  final AppNotifier notifier;
  const HomeScreen({super.key, required this.notifier});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// What the agent accounts on this machine have spent.
  ///
  /// Owned HERE rather than by the status rail that draws it, because it now
  /// has two readers: the rail's figures and [UsageLimitNotice] above it. Two
  /// controllers would be two pollers hitting the same two vendors a minute
  /// apart, and a card that could name a percentage the rail underneath it
  /// disagreed with.
  final UsageController _usage = UsageController();

  @override
  void dispose() {
    // The shell made it, so the shell cancels its timer. The rail is handed it
    // and deliberately does not dispose what it did not create.
    _usage.dispose();
    super.dispose();
  }

  // User-dragged override. null until the resize handle is used, so the
  // window-relative default below keeps applying on its own.
  double? _railWidth;
  bool _collapsed = false;

  // Guards against opening a second popup for the same machine while one is already up — showDialog
  // itself has no such de-dup, and this rebuilds on every notifier change while the popup is open.
  String? _linkDialogMachineId;

  /// Pops open the link popup for whichever machine was most recently SELECTED (not
  /// `activeMachineState`, which prefers whatever pane currently has a terminal focused — clicking
  /// "link required" for a machine that needs linking must not get shadowed by an unrelated
  /// terminal the user already has open elsewhere). Both entry points (machine_rail.dart's "link
  /// required" rows and its "Remote into this machine…" menu item) already set `selectedMachineId`
  /// via `selectMachineForSetup`/`showMachinePane`, so neither needs to know about this popup
  /// directly; this is the one place that turns "the selected machine needs linking" into "show
  /// the popup," for however that state was reached (a click, or a connection attempt that only
  /// discovers NO_PEER_LINK after the fact).
  void _maybeShowLinkDialog(AppNotifier notifier) {
    final selectedId = notifier.selectedMachineId;
    final active = selectedId == null ? null : notifier.stateOf(selectedId);
    final show =
        active != null &&
        active.isRemote &&
        !active.isLocalMachine &&
        active.needsLink &&
        !notifier.isLinkPromptDismissed(active.machine.machineId);
    if (!show || _linkDialogMachineId == active.machine.machineId) return;
    final machineId = active.machine.machineId;
    _linkDialogMachineId = machineId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showLinkMachineScreenDialog(context, notifier, machineId);
      if (!mounted) return;
      _linkDialogMachineId = null;
    });
  }

  /// Every agent the rail is currently showing, in the order it shows them.
  ///
  /// Built from the same two lists the rail walks, so ⌘3 lands on the third row
  /// the user can see rather than the third row of some internal order.
  List<({String machineId, String agentId})> _visibleAgents() {
    final notifier = widget.notifier;
    final result = <({String machineId, String agentId})>[];
    for (final machine in notifier.machines) {
      final state = notifier.machineStates[machine.machineId];
      if (state == null) continue;
      if (!notifier.expandedMachines.contains(machine.machineId)) continue;
      for (final agent in state.agents) {
        result.add((machineId: machine.machineId, agentId: agent.id));
      }
    }
    return result;
  }

  void _stepAgent(int delta) {
    final agents = _visibleAgents();
    if (agents.isEmpty) return;
    final pane = widget.notifier.focusedPane;
    final current = pane?.agentId == null
        ? -1
        : agents.indexWhere(
            (a) => a.machineId == pane!.machineId && a.agentId == pane.agentId,
          );
    // Wraps, and starts at the top when nothing is open — the list is a ring,
    // and a first press that does nothing reads as a broken key.
    final next = current < 0
        ? (delta > 0 ? 0 : agents.length - 1)
        : (current + delta) % agents.length;
    final target = agents[next];
    unawaited(widget.notifier.selectAgent(target.machineId, target.agentId));
  }

  void _closeFocusedPane() {
    final pane = widget.notifier.focusedPane;
    // No pane to close: leave ⌘W alone so macOS closes the window with it, the
    // way it does in every other app.
    if (pane == null) return;
    unawaited(widget.notifier.closePane(pane.id));
  }

  /// ⌘⇧M — the pane header's Model pill, without the mouse.
  ///
  /// The pill is the same call (`pickAgentModel`), so the refusals, the mint,
  /// the restart and the Recent entry are one implementation. The engine comes
  /// from the agent the pane is showing, not from the pane: a pane is an
  /// intent, and it can be sitting on a machine that has not answered yet.
  void _changeModel() {
    final pane = widget.notifier.focusedPane;
    // A pane is an INTENT: it exists before its machine has answered, and a
    // tile with no agent yet has no model to change.
    final agentId = pane?.agentId;
    if (pane == null || agentId == null) return;
    final engine = widget.notifier
        .stateOf(pane.machineId)
        ?.agents
        .where((agent) => agent.id == agentId)
        .map((agent) => agent.engine)
        .firstOrNull;
    if (engine == null) return;
    unawaited(
      pickAgentModel(
        context,
        widget.notifier,
        machineId: pane.machineId,
        agentId: agentId,
        engine: engine,
      ),
    );
  }

  void _newAgent() {
    final machineId =
        widget.notifier.focusedPane?.machineId ??
        widget.notifier.selectedMachineId;
    if (machineId == null) return;
    unawaited(
      showNewAgentDialog(
        context,
        widget.notifier,
        machineId,
        source: 'shortcut',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifier = widget.notifier;
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) {
        _maybeShowLinkDialog(notifier);
        return CallbackShortcuts(
          bindings: buildShortcutBindings(
            handlers: {
              ShortcutAction.toggleRail: () =>
                  setState(() => _collapsed = !_collapsed),
              ShortcutAction.nextAgent: () => _stepAgent(1),
              ShortcutAction.previousAgent: () => _stepAgent(-1),
              ShortcutAction.focusNextPane: () => notifier.focusPaneBy(1),
              ShortcutAction.focusPreviousPane: () => notifier.focusPaneBy(-1),
              ShortcutAction.focusPaneAbove: () =>
                  notifier.focusPaneVertically(-1),
              ShortcutAction.focusPaneBelow: () =>
                  notifier.focusPaneVertically(1),
              ShortcutAction.movePaneForward: () => notifier.movePaneBy(1),
              ShortcutAction.movePaneBackward: () => notifier.movePaneBy(-1),

              ShortcutAction.closePane: _closeFocusedPane,
              ShortcutAction.newAgent: _newAgent,
              ShortcutAction.changeModel: _changeModel,
              ShortcutAction.routeTask: () =>
                  unawaited(showTaskPalette(context, notifier)),
              ShortcutAction.reload: () => unawaited(notifier.retryMachines()),
              ShortcutAction.pinPane: () {
                final id = notifier.focusedPaneId;
                if (id != null && notifier.panes.length > 1) {
                  notifier.togglePinPane(id);
                }
              },
              ShortcutAction.showLayout: () =>
                  unawaited(showLayoutPalette(context, notifier)),
              ShortcutAction.showShortcuts: () =>
                  unawaited(showShortcutsSheet(context)),
              // Bound whether or not this build has the screen: an unlisted
              // action is simply never in the bindings (see appShortcuts()),
              // so the handler costs nothing where the key does not exist.
              ShortcutAction.showDebug: () => unawaited(
                showSettingsScreen(
                  context,
                  notifier,
                  initialSection: SettingsSection.debug,
                ),
              ),
            },
            onSelectPaneIndex: notifier.focusPaneByIndex,
          ),
          child: Focus(
            // This is only a shortcuts scope. If it owns keyboard focus after
            // an agent-list refresh, the focused terminal can no longer open
            // its native TextInput connection, which makes the whole terminal
            // look locked even though its stream is still healthy.
            canRequestFocus: false,
            child: Scaffold(
              // Not the theme's: that one is still the old terminal palette, and it
              // is what showed through the seam above.
              backgroundColor: grid.AppPalette.windowBg,
              body: Column(
                children: [
                  // The window's own strip, above the rail AND the grid. It
                  // exists so the content below it starts clear of the
                  // transparent title bar — see HarnessTopBar, which explains
                  // why anything drawn up there cannot be dragged by Flutter.
                  const HarnessTopBar(),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final defaultWidth = (constraints.maxWidth * 0.18)
                                  .clamp(252.0, 300.0)
                                  .toDouble();
                              final minWidth = 220.0;
                              final maxWidth = (constraints.maxWidth * 0.5)
                                  .clamp(minWidth, 520.0)
                                  .toDouble();
                              final railWidth = (_railWidth ?? defaultWidth)
                                  .clamp(minWidth, maxWidth);
                              return Row(
                                children: [
                                  _RailFold(
                                    notifier: notifier,
                                    collapsed: _collapsed,
                                    wideWidth: railWidth,
                                    onCollapse: () =>
                                        setState(() => _collapsed = true),
                                    onExpand: () =>
                                        setState(() => _collapsed = false),
                                  ),
                                  // Only the full rail can be dragged wider. Folded, the
                                  // width is the fold's to decide, and a handle there
                                  // would offer a resize that snaps back.
                                  if (_collapsed)
                                    const _RailSeam()
                                  else
                                    _ResizeHandle(
                                      onDrag: (dx) => setState(() {
                                        // Accumulate against the STATE field, not the
                                        // `railWidth` local above: that local is a
                                        // snapshot from the last completed rebuild, and
                                        // several drag-update events can fire before
                                        // Flutter gets around to rebuilding (routine
                                        // under fast mouse movement). Basing each step
                                        // on the same stale snapshot silently drops all
                                        // but the last delta in that batch, which is
                                        // exactly the lag/drift this fixes.
                                        final current =
                                            _railWidth ?? defaultWidth;
                                        _railWidth = (current + dx).clamp(
                                          minWidth,
                                          maxWidth,
                                        );
                                      }),
                                    ),
                                  Expanded(child: PaneGrid(notifier: notifier)),
                                ],
                              );
                            },
                          ),
                        ),
                        // Floating, not a row in the Column: taking layout
                        // here would resize every pane — a real SIGWINCH to
                        // every pty on screen — to deliver a message. Bottom
                        // left, so it sits directly over the usage figure it
                        // is about.
                        Positioned(
                          left: UsageLimitNotice.inset,
                          bottom: UsageLimitNotice.inset,
                          child: UsageLimitNotice(
                            notifier: notifier,
                            usage: _usage,
                          ),
                        ),
                        if (notifier.lastError != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: _ErrorStrip(
                              message: notifier.lastError!,
                              retryable: notifier.lastErrorRetryable,
                              onRetry: notifier.retryMachines,
                              onDismiss: notifier.dismissError,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // What this grid is made of, along the very bottom. Outside
                  // the Expanded above so it is full-bleed under the machine
                  // rail as well as the panes — a strip that started after the
                  // rail would put a step in the window's bottom edge.
                  GridStatusRail(
                    // Two things need it, for one reason: the rail holds no
                    // `AppNotifier` and both of these open Settings.
                    notifier: notifier,
                    // The shell's, shared with the card above — see [_usage].
                    usage: _usage,
                    // The node dashboard's empty state offers to put THIS
                    // computer on the grid, and the screen that does it is a
                    // Settings pane — which needs the notifier the shell holds
                    // and the rail does not.
                    onShareIntelligence: () => unawaited(
                      showSettingsScreen(
                        context,
                        notifier,
                        initialSection: SettingsSection.shareIntelligence,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A draggable divider between the machine rail and the terminal pane. Wider
/// than the 1px line it draws so the hit target is actually grabbable.
/// The rail, and the fold between its two widths.
///
/// It owns the rail's SURFACE while the two rails own only what is drawn on it.
/// That split is what makes the fold one moving edge instead of two: during the
/// crossfade both rails are mounted at partial opacity, and two fills stacked
/// over the window would darken the whole rail for the length of the animation.
///
/// Neither rail animates its own contents. The wide one stays laid out at its
/// full width and is clipped by the shrinking box, because its rows are written
/// for that width — reflowing the machine tree through every width between 284
/// and 72 would be sixty frames of text rewrapping, and it would look like it.
class _RailFold extends StatelessWidget {
  const _RailFold({
    required this.notifier,
    required this.collapsed,
    required this.wideWidth,
    required this.onCollapse,
    required this.onExpand,
  });

  final AppNotifier notifier;

  final bool collapsed;
  final double wideWidth;
  final VoidCallback onCollapse;
  final VoidCallback onExpand;

  /// How far each rail drifts sideways as it leaves.
  ///
  /// A hint, not a journey. Sliding the wide rail out by its whole width would
  /// drag every label across the screen and — coming back — deliver the labels
  /// before their own icons. Twelve pixels reads as "this went away" while the
  /// width itself carries the movement.
  static const double _drift = 12;

  /// One rail's share of the crossfade. Each is alone for the first and last
  /// quarter and they trade over the middle half, so neither is ever the only
  /// thing on screen at half strength.
  static double _fade(double t) => ((t - 0.25) / 0.5).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return TweenAnimationBuilder<double>(
      // No `begin`: a window that opens folded should BE folded, not unfold
      // itself while the user watches.
      tween: Tween(end: collapsed ? 0.0 : 1.0),
      duration: grid.AppMotion.fold,
      // Fast off the mark, settling at the end — the rail arrives at its new
      // width rather than drifting there.
      curve: grid.AppMotion.curve,
      builder: (context, open, _) {
        final wide = _fade(open);
        final mini = _fade(1 - open);
        return SizedBox(
          width: lerpDouble(MachineRailMini.width, wideWidth, open),
          child: ColoredBox(
            color: grid.AppGlass.sidebarFill,
            child: ClipRect(
              child: Stack(
                children: [
                  // Both hang off the LEFT edge — the edge that doesn't move.
                  // Pinning the wide one right would slide its icons out of
                  // view first and leave a column of orphaned labels.
                  //
                  // Unmounted at zero opacity rather than merely invisible: the
                  // wide rail carries the whole machine tree, and a folded rail
                  // should not be paying for it.
                  if (wide > 0)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: wideWidth,
                      child: Opacity(
                        opacity: wide,
                        child: Transform.translate(
                          offset: Offset(-_drift * (1 - open), 0),
                          child: MachineRail(
                            notifier: notifier,
                            onCollapse: onCollapse,
                          ),
                        ),
                      ),
                    ),
                  if (mini > 0)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: MachineRailMini.width,
                      child: Opacity(
                        opacity: mini,
                        child: Transform.translate(
                          offset: Offset(-_drift * open, 0),
                          child: MachineRailMini(
                            notifier: notifier,
                            onExpand: onExpand,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The seam, with nothing to drag.
///
/// Same painting as [_ResizeHandle] so folding the rail does not change the
/// line between it and the pane — only whether that line can be grabbed.
class _RailSeam extends StatelessWidget {
  const _RailSeam();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: grid.AppPalette.windowBg,
        border: Border(left: BorderSide(color: grid.AppPalette.divider)),
      ),
      child: const SizedBox(width: 7, height: double.infinity),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  final ValueChanged<double> onDrag;
  const _ResizeHandle({required this.onDrag});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        // Painted, and painted in the PANE's colour. It used to be a bare
        // 7px box with a rule down the middle, which let the scaffold show
        // through — a strip darker than the rail on one side and the pane on
        // the other, reading as a gap between them rather than as a seam.
        //
        // The hairline sits on the LEFT edge, against the rail, so the eye
        // reads rail → line → pane with nothing in between. Down the middle it
        // would leave 3px of pane stranded on the rail's side of the line.
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: grid.AppPalette.windowBg,
            border: Border(left: BorderSide(color: grid.AppPalette.divider)),
          ),
          child: const SizedBox(width: 7, height: double.infinity),
        ),
      ),
    );
  }
}

class _ErrorStrip extends StatelessWidget {
  final String message;
  final bool retryable;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  const _ErrorStrip({
    required this.message,
    required this.retryable,
    required this.onRetry,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    // Pinned to the window's top edge, where the traffic lights float — so
    // the text starts past them, and the strip drags the window like the rest
    // of that edge.
    return WindowDragArea(
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        color: const Color(0xff26131b),
        padding: EdgeInsets.fromLTRB(12 + trafficLightClearance, 7, 12, 7),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 15, color: AppColors.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textSoft, fontSize: 10),
              ),
            ),
            // A failure already finished (an agent's launch) has nothing left
            // for a retry to redo — reloading the machine list will not
            // install the engine that just failed to. Offer to dismiss it
            // instead of a button that only looks like it did something.
            if (retryable)
              TextButton(onPressed: onRetry, child: const Text('RETRY'))
            else
              TextButton(onPressed: onDismiss, child: const Text('CLOSE')),
          ],
        ),
      ),
    );
  }
}
