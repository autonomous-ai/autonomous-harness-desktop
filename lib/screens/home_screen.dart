import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../core/desktop_window.dart';
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

  /// Spoken tasks from the dial, waiting for a palette. Subscribed here because this is the lowest
  /// place that has both a [BuildContext] to open a dialog on and a lifetime to cancel with.
  StreamSubscription<SpokenTaskRequest>? _spokenTasks;

  /// One palette at a time. Two people cannot speak into one dial at once, but a request can arrive
  /// while the previous one is still open — from a retry, or from a second daemon — and stacking two
  /// dialogs would leave the one underneath answering for words nobody can see.
  bool _spokenPaletteOpen = false;

  // User-dragged override. null until the resize handle is used, so the
  // window-relative default below keeps applying on its own.
  double? _railWidth;
  bool _collapsed = false;

  // Guards against opening a second popup for the same machine while one is already up — showDialog
  // itself has no such de-dup, and this rebuilds on every notifier change while the popup is open.
  String? _linkDialogMachineId;

  @override
  void initState() {
    super.initState();
    _spokenTasks = widget.notifier.spokenTasks.listen(_openSpokenTask);
  }

  @override
  void dispose() {
    unawaited(_spokenTasks?.cancel());
    // The shell made it, so the shell cancels its timer. The rail is handed it
    // and deliberately does not dispose what it did not create.
    _usage.dispose();
    super.dispose();
  }

  /// The dial spoke: raise the window and run the palette on those words.
  ///
  /// The raise is not a nicety. The person is looking at a dial, not at this screen, and the palette may
  /// have a question for them — a route this window is not sure enough about to send in silence. Behind
  /// another app, that question is never asked and the spoken sentence dies on a deadline.
  Future<void> _openSpokenTask(SpokenTaskRequest request) async {
    final spoken = SpokenTask(
      voiceId: request.voiceId,
      text: request.text,
      cmd: request.cmd,
      report: (voiceId, state, agentId) => widget.notifier.reportVoiceRoute(
        request.machineId,
        voiceId,
        state,
        agentId,
      ),
    );
    // Busy: answer immediately rather than let the daemon hold the dial's overlay open for a minute
    // waiting on a palette this window is never going to show.
    if (_spokenPaletteOpen || !mounted) {
      spoken.cancelled();
      return;
    }
    _spokenPaletteOpen = true;
    try {
      await revealWindow();
      if (!mounted) {
        spoken.cancelled();
        return;
      }
      await showTaskPalette(context, widget.notifier, spoken: spoken);
    } finally {
      _spokenPaletteOpen = false;
      // Belt: showTaskPalette answers on every exit of its own, and this is a no-op after any of them.
      spoken.cancelled();
    }
  }

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
        source: 'shortcut',
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
                  source: 'shortcut',
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
              // THE FIELD SPANS THE BODY, so it runs behind the status rail as well as the grid.
              //
              // Wrapped any further in and the gradient stops where the grid stops — which is what
              // made the transparent rail look unchanged: with no fill of its own it simply showed
              // the scaffold's flat colour, a shade off the one it had just given up. The top bar
              // paints its own opaque fill over this, so nothing changes up there.
              body: GridField(
                child: Column(
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
                                final defaultWidth =
                                    (constraints.maxWidth * 0.18)
                                        .clamp(252.0, 300.0)
                                        .toDouble();
                                final minWidth = 220.0;
                                final maxWidth = (constraints.maxWidth * 0.5)
                                    .clamp(minWidth, 520.0)
                                    .toDouble();
                                final railWidth = (_railWidth ?? defaultWidth)
                                    .clamp(minWidth, maxWidth);
                                // THE FIELD RUNS UNDER EVERYTHING, rail included, and one margin
                                // holds the lot. It used to start where the rail ended, so the two
                                // surfaces met along a hard seam that belonged to neither: every tile
                                // floated as a card while the rail alone stayed bolted to the window
                                // with square corners.
                                // The margin only. The field itself is up at the body now, so
                                // one gradient covers the window instead of one per region.
                                return Padding(
                                  padding: const EdgeInsets.all(kPaneGap),
                                  child: Row(
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
                                      // Folded there is nothing to resize and nothing to divide: the
                                      // seam that used to sit here was seven more pixels of chrome beside
                                      // a rail that had just gone to zero, which is most of what folding
                                      // was supposed to give back.
                                      if (!_collapsed)
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
                                      Expanded(
                                        child: PaneGrid(notifier: notifier),
                                      ),
                                    ],
                                  ),
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
                          if (_collapsed)
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              child: _RailReveal(
                                notifier: notifier,
                                onExpand: () =>
                                    setState(() => _collapsed = false),
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
                          source: 'node_dashboard',
                        ),
                      ),
                    ),
                  ],
                ),
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
        return SizedBox(
          // FOLDED IS ZERO NOW, not 72. The folded rail held a fold button and an avatar and nothing
          // else — a column that was empty permanently, which is what made it expensive. Those two
          // controls moved to the edge reveal ([_RailReveal]), so folding gives the whole width back.
          width: lerpDouble(0, wideWidth, open),
          child: DecoratedBox(
            // A CARD, like the tiles beside it: same fill duty, same corners, same hairline. It was
            // the one surface running edge to edge with square corners, which read as the app's
            // chrome rather than as one more thing on the field.
            decoration: BoxDecoration(
              color: grid.AppGlass.sidebarFill,
              borderRadius: BorderRadius.circular(kPaneRadius),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            // Rounded, not square: the rail's own rows run to its edge, and a square clip would let
            // them square off the corners the rim just rounded — the same notch the panes had.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kPaneRadius - 1),
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
/// The folded rail, which is not on screen until you reach for it.
///
/// Folding used to leave a 72px column carrying a fold button and an avatar — permanently, on every
/// window, whether or not anyone was going to touch either. This is the same two controls with the
/// column deleted: a narrow strip along the left edge that costs nothing until the pointer arrives,
/// then slides the real [MachineRailMini] out over the grid on a scrim.
///
/// The cost of hiding a control is that a new user cannot find it, and that is answered here by the
/// keyboard: `toggleRail` is bound and listed in the shortcuts sheet as "Show or hide the sidebar", so
/// the rail is reachable without knowing this strip exists at all.
class _RailReveal extends StatefulWidget {
  const _RailReveal({required this.notifier, required this.onExpand});

  final AppNotifier notifier;
  final VoidCallback onExpand;

  /// How far in from the edge counts as reaching for it. Wide enough to catch a deliberate move to the
  /// edge, narrow enough to sit inside the grid's own margin — so crossing it does not mean crossing
  /// anything a person was aiming at.
  static const double _reach = 12;

  @override
  State<_RailReveal> createState() => _RailRevealState();
}

class _RailRevealState extends State<_RailReveal> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return MouseRegion(
      // NOT opaque, and that is the whole trick: while the strip is hidden this is twelve pixels lying
      // over the first pane, and an opaque region there would quietly eat every click that landed on
      // that edge — a terminal that ignores you along one stripe, with nothing on screen to explain it.
      opaque: false,
      onEnter: (_) => setState(() => _open = true),
      onExit: (_) => setState(() => _open = false),
      child: AnimatedContainer(
        duration: grid.AppMotion.fold,
        curve: grid.AppMotion.curve,
        width: _open ? MachineRailMini.width : _RailReveal._reach,
        child: IgnorePointer(
          // The buttons still hit-test at zero opacity, so they are taken out of the tree's reach
          // rather than merely faded — otherwise the hidden strip would swallow clicks the same way an
          // opaque region would, just less obviously.
          ignoring: !_open,
          child: AnimatedOpacity(
            duration: grid.AppMotion.fold,
            curve: grid.AppMotion.curve,
            opacity: _open ? 1 : 0,
            child: ClipRect(
              child: OverflowBox(
                // Laid out at its full width even while the container is 12px, so the icons inside do
                // not reflow on the way in — they slide out already in their final places.
                alignment: Alignment.centerLeft,
                minWidth: MachineRailMini.width,
                maxWidth: MachineRailMini.width,
                child: DecoratedBox(
                  // A SCRIM, not a panel. The sidebar's own fill would be a solid column landing back
                  // on top of the grid — the same 72px this change was about removing, just appearing
                  // and disappearing. Dark at the edge and gone by the far side, so the controls have
                  // something to sit on while the panes stay visible underneath them.
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0x8C000000), Color(0x00000000)],
                    ),
                  ),
                  child: MachineRailMini(
                    notifier: widget.notifier,
                    onExpand: widget.onExpand,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
        // UNPAINTED, and that is the point: it is the gap between two cards, so what belongs in it is
        // the field, the same as every gap inside the grid.
        //
        // It used to paint the pane's colour with a hairline down its left edge — a seam, drawn back
        // when the rail was chrome butted against the grid and something had to divide them. Two cards
        // do not need dividing; the space already does it. All that survives is the width and the
        // drag, which is all this was ever for.
        child: const SizedBox(width: kPaneGap, height: double.infinity),
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
