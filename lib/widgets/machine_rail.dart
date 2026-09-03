import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../core/models.dart';
import '../shared/layouts/widgets/sidebar_item.dart';
import '../shared/layouts/widgets/sidebar_timeline.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_icon_button.dart';
import '../shared/widgets/app_menu.dart';
import '../shared/widgets/skeleton.dart';
import '../shortcuts/app_shortcuts.dart';
import '../state/app_state.dart';
import 'agent_drag.dart';
import 'rename_agent_dialog.dart';
import 'account_footer.dart';
import 'engine_identity.dart';
import 'grid_selector.dart';
import 'link_machine_dialog.dart';
import 'new_agent_dialog.dart';

/// The machine caption's type.
///
/// A function rather than a constant so its skeleton can borrow the exact
/// metrics: `skeleton_sites_test.dart` measures a placeholder machine row
/// against a real one, and a caption whose type drifts from its placeholder
/// makes the rail resize the moment the list lands.
TextStyle _machineCaptionStyle(Color color) => TextStyle(
  color: color,
  fontFamily: grid.AppFont.sans,
  fontSize: 11,
  fontWeight: grid.AppFont.semibold,
  letterSpacing: 0.3,
);

/// The caption's own box: 18px mark at the rail's gutter, 22px of line, and
/// symmetric padding so the mark lands on [SidebarTimeline]'s trunk break.
/// Shared with the placeholder for the same reason as the type above.
const EdgeInsets _machineCaptionPadding = EdgeInsets.fromLTRB(10, 7, 6, 7);
const double _machineCaptionHeight = 22;
const double _machineMarkSize = 18;

class MachineRail extends StatefulWidget {
  final AppNotifier notifier;

  /// Fold the rail away. Null hides the control — a button that collapses
  /// nothing is worse than no button.
  final VoidCallback? onCollapse;

  const MachineRail({super.key, required this.notifier, this.onCollapse});

  @override
  State<MachineRail> createState() => MachineRailState();
}

/// Public so ⌘F can reach the filter it already draws — the field lives in the
/// rail's head, but the key that opens it has to be bound above the terminal.
class MachineRailState extends State<MachineRail> {
  static const _headerHeight = 46.0;
  String _query = '';
  bool _searching = false;
  final FocusNode _filterFocus = FocusNode();

  /// Opens the filter and puts the caret in it. Already open: just re-focus,
  /// so pressing the key twice never closes what the user just asked for.
  void openFilter() {
    setState(() => _searching = true);
    _filterFocus.requestFocus();
  }

  @override
  void dispose() {
    _filterFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // No fill here. The fold above draws one surface under whichever rail is
    // showing: during the crossfade both are mounted, and two translucent fills
    // stacked over the window would darken the whole rail for the length of the
    // animation.
    return ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, _) {
        final filteredMachines = widget.notifier.machines.where((machine) {
          if (_query.isEmpty) return true;
          final state = widget.notifier.stateOf(machine.machineId);
          return machine.displayName.toLowerCase().contains(_query) ||
              (state?.agents.any(
                    (agent) =>
                        agent.name.toLowerCase().contains(_query) ||
                        (agent.engine?.toLowerCase().contains(_query) ??
                            false) ||
                        (agent.engineDisplayName?.toLowerCase().contains(
                              _query,
                            ) ??
                            false),
                  ) ??
                  false);
        }).toList();
        // Keep the current computer immediately reachable while preserving
        // the backend order for every other machine.
        final machines = <Machine>[
          ...filteredMachines.where(
            (machine) =>
                widget.notifier.stateOf(machine.machineId)?.isLocalMachine ==
                true,
          ),
          ...filteredMachines.where(
            (machine) =>
                widget.notifier.stateOf(machine.machineId)?.isLocalMachine !=
                true,
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The rail opens with the product's name and the two things you
            // do to the whole list. It used to open with MACHINES in tracked
            // capitals over a permanently-bordered search box — a dev-tool
            // caption and a control nobody asked for, costing 80px before the
            // first row.
            // The head is also a window drag handle — the title bar is hidden
            // (see configureDesktopWindow). No rule under it: Grid draws none,
            // and a rule here would sit below the pane header's and read as a
            // mistake.
            //
            // No top inset for the traffic lights any more: HarnessTopBar sits
            // above the whole window and holds that row now, so keeping one
            // here pushed the wordmark down twice.

            DragToMoveArea(
              child: SizedBox(
                // The same 46px strip the terminal panes draw, so the wordmark
                // and a pane's title sit on one baseline.
                height: _headerHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Harness',
                          style: TextStyle(
                            color: grid.AppPalette.textPrimary,
                            fontSize: 17,
                            // Semibold, not bold. A wordmark at 17pt already
                            // out-ranks everything below it by size alone.
                            fontWeight: grid.AppFont.semibold,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                      AppIconButton(
                        icon: _searching
                            ? LucideIcons.searchX300
                            : LucideIcons.search300,
                        size: 18,
                        tooltip: withShortcutHint(
                          'Filter machines and agents',
                          ShortcutAction.filterAgents,
                        ),
                        color: _searching
                            ? grid.AppPalette.accentOnSurface
                            : null,
                        onPressed: () => setState(() {
                          _searching = !_searching;
                          if (!_searching) _query = '';
                        }),
                      ),
                      const SizedBox(width: 2),
                      AppIconButton(
                        icon: LucideIcons.refreshCw300,
                        size: 18,
                        tooltip: withShortcutHint(
                          'Reload machines',
                          ShortcutAction.reload,
                        ),
                        onPressed: widget.notifier.retryMachines,
                      ),
                      if (widget.onCollapse != null) ...[
                        const SizedBox(width: 2),
                        AppIconButton(
                          icon: LucideIcons.panelLeft300,
                          size: 18,
                          tooltip: withShortcutHint(
                            'Collapse sidebar',
                            ShortcutAction.toggleRail,
                          ),
                          onPressed: widget.onCollapse!,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                // No SizedBox and no decoration overrides: the theme now
                // sizes this to AppControl.heightField (36), not a push
                // button's 32. §5.1 makes that split on purpose — a button is
                // sized to be HIT, a field to be TYPED IN and to anchor the
                // column under it, which is why Finder and Mail both give
                // sidebar search more room than a button in the same window.
                child: TextField(
                  focusNode: _filterFocus,
                  style: grid.kFieldTextStyle,
                  decoration: InputDecoration(
                    hintText: 'filter machines / agents',
                    prefixIcon: Icon(
                      LucideIcons.search300,
                      // The field's glyph follows the box it sits in, not the
                      // button token next to it — see [grid.kFieldIconSize].
                      size: grid.kFieldIconSize,
                      color: grid.AppPalette.textFaint,
                    ),
                  ),
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                ),
              ),
            // The rail's primary action, not a `+` hiding on a hover state.
            // Opening a new agent is the thing this window exists for, and it
            // used to be reachable only by pointing at the right machine row
            // and finding a 16px glyph that appeared under the pointer.
            _NewAgentButton(notifier: widget.notifier),
            Expanded(
              child: machines.isEmpty
                  // Two kinds of empty, and they must not look the same: the
                  // list has not answered yet, or it answered with nothing.
                  ? widget.notifier.machinesLoading
                        ? const _MachineListSkeleton(
                            key: ValueKey('machines-loading'),
                          )
                        : Center(
                            child: Text(
                              'no remote machines',
                              style: TextStyle(
                                color: grid.AppPalette.textFaint,
                                fontFamily: grid.AppFont.sans,
                                fontSize: 13.5,
                              ),
                            ),
                          )
                  : ListView.builder(
                      itemCount: machines.length,
                      itemBuilder: (context, index) => _MachineNode(
                        notifier: widget.notifier,
                        machine: machines[index],
                        query: _query,
                        isFirst: index == 0,
                      ),
                    ),
            ),
            const GridSelector(),
            AccountFooter(notifier: widget.notifier),
          ],
        );
      },
    );
  }
}

/// The rail's primary action.
///
/// A filled button, at the top, always visible — because opening an agent is
/// what this window is for. It used to be a 16px `+` that appeared on the
/// machine row under the pointer, which made the app's main verb the hardest
/// thing in the rail to find and tied it to picking the right row first.
///
/// It still has to launch *somewhere*, and the machine it picks is the same one
/// ⌘N picks (see `_newAgent` in home_screen.dart): the machine whose terminal
/// you are typing in, else the one you last selected. Where neither is set — a
/// cold window with nothing open — it falls back to THIS computer rather than
/// going dead, because a primary action that does nothing on a fresh launch is
/// worse than one that guesses the only machine you certainly have.
class _NewAgentButton extends StatefulWidget {
  const _NewAgentButton({required this.notifier});

  final AppNotifier notifier;

  @override
  State<_NewAgentButton> createState() => _NewAgentButtonState();
}

class _NewAgentButtonState extends State<_NewAgentButton> {
  bool _hovered = false;

  AppNotifier get notifier => widget.notifier;

  String? get _targetMachineId {
    final focused = notifier.focusedPane?.machineId;
    if (focused != null) return focused;
    final selected = notifier.selectedMachineId;
    if (selected != null) return selected;
    for (final machine in notifier.machines) {
      if (notifier.stateOf(machine.machineId)?.isLocalMachine == true) {
        return machine.machineId;
      }
    }
    return notifier.machines.isEmpty
        ? null
        : notifier.machines.first.machineId;
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final machineId = _targetMachineId;
    final enabled = machineId != null;
    final hint = shortcutHintFor(ShortcutAction.newAgent);
    // Not `withShortcutHint`: the chord is printed ON the button, so repeating
    // it in the tooltip would say the same thing twice in one hover.
    final label = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(LucideIcons.plus300, size: 15, color: Colors.white),
        const SizedBox(width: 7),
        Text(
          'New agent',
          style: TextStyle(
            color: Colors.white,
            fontFamily: grid.AppFont.sans,
            fontSize: 13,
            fontWeight: grid.AppFont.semibold,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 8),
          Text(
            hint,
            style: TextStyle(
              // The chord rides the button rather than sitting beside it, so it
              // takes the label's ink held back — loud enough to read, quiet
              // enough not to compete with the verb it belongs to.
              color: Colors.white.withValues(alpha: 0.62),
              fontFamily: grid.AppFont.sans,
              fontSize: 11.5,
              fontWeight: grid.AppFont.medium,
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          key: const Key('rail-new-agent-button'),
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () => showNewAgentDialog(context, notifier, machineId)
              : null,
          child: AnimatedContainer(
            duration: grid.AppMotion.hover,
            curve: grid.AppMotion.curve,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: !enabled
                  // Greyed, not hidden. A rail with no machines still has to
                  // show what it will let you do once one arrives.
                  ? grid.AppSurface.recess
                  : _hovered
                  ? grid.AppPalette.accentHover
                  : grid.AppPalette.accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: enabled
                ? label
                : Opacity(opacity: 0.45, child: label),
          ),
        ),
      ),
    );
  }
}

class _MachineNode extends StatefulWidget {
  /// Whether the guide line arrives from a row above. False on the first
  /// machine, where a line dangling up towards the New agent button would point
  /// at nothing.
  final bool isFirst;

  final AppNotifier notifier;
  final Machine machine;
  final String query;

  const _MachineNode({
    required this.notifier,
    required this.machine,
    required this.query,
    required this.isFirst,
  });

  @override
  State<_MachineNode> createState() => _MachineNodeState();
}

class _MachineNodeState extends State<_MachineNode> {
  final MenuController _machineMenu = MenuController();
  bool _menuOpen = false;
  bool _hovered = false;

  AppNotifier get notifier => widget.notifier;
  Machine get machine => widget.machine;
  String get query => widget.query;

  Future<void> _showRenameDialog() async {
    final controller = TextEditingController(text: machine.displayName);
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Edit name'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: grid.kFieldTextStyle,
                  onSubmitted: (_) async {
                    final result = await notifier.renameMachine(
                      machine.machineId,
                      controller.text,
                    );
                    if (result == null) {
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    } else {
                      setDialogState(() => error = result);
                    }
                  },
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: TextStyle(
                      color: grid.AppPalette.dangerFill,
                      fontFamily: grid.AppFont.sans,
                      fontSize: 11.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final result = await notifier.renameMachine(
                  machine.machineId,
                  controller.text,
                );
                if (result == null) {
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                } else {
                  setDialogState(() => error = result);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _confirmDeleteMachine() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete machine'),
        content: SizedBox(
          width: 360,
          child: Text(
            'Delete "${machine.displayName}"? All its agents will be disconnected and '
            "it'll need to be linked again. This can't be undone.",
            style: TextStyle(fontFamily: grid.AppFont.sans, fontSize: 13.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: grid.AppPalette.dangerFill,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final error = await notifier.deleteMachine(machine.machineId);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final expanded = notifier.expandedMachines.contains(machine.machineId);
    final state = notifier.stateOf(machine.machineId)!;
    // The relay's local WS session can stay `connected` for a beat after the backend has already
    // reported the underlying node offline (two independently-polled signals) — never show green here
    // while the offline-guide panel is (or is about to be) blocking the same machine.
    final connectionColor = state.nodeOnline == false
        ? grid.AppPalette.textFaint
        : switch (state.connectionStatus) {
            ConnectionStatus.connected => grid.AppPalette.online,
            ConnectionStatus.connecting ||
            ConnectionStatus.reconnecting => grid.AppPalette.warn,
            ConnectionStatus.disconnected => grid.AppPalette.textFaint,
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The machine is a CAPTION over its agents, not a row among them.
        //
        // Quiet micro-type is what makes that read at a glance: the eye sorts
        // the rail into "things I open" and "labels saying where they live"
        // without having to decode the indent alone. It used to be a full
        // SidebarItem, which gave a machine exactly the weight, the height and
        // the hover of the agents under it.
        //
        // Not upper-cased, though the type is sized for it: a hostname is 26
        // characters of shouting by the time it reaches the ellipsis, and the
        // case of `MacBooks-MacBook-Pro.local` is information.
        //
        // It is still a NODE on the guide line, and that is why the glyph sits
        // on [SidebarTimeline]'s trunk with nothing in front of it: the line
        // runs THROUGH the mark it breaks around, so anything to its left
        // pushes the mark off the line. Which is also why there is no chevron —
        // the trunk carrying on down into the agents already says the machine
        // is open, and says it better than a glyph pointing at itself.
        SidebarTimeline(
          role: SidebarTimelineRole.node,
          above: !widget.isFirst,
          below: expanded && state.agents.isNotEmpty,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              // Same menu the ⋯ opens — one shape for one set of actions.
              onSecondaryTap: _machineMenu.open,
              onTap: () => notifier.toggleExpand(machine.machineId),
              child: Padding(
                key: ValueKey('machine-row-${machine.machineId}'),
                // Symmetric top and bottom on purpose: [TimelineGuide] breaks
                // the trunk around the middle of the band it is given, so an
                // off-centre glyph would sit beside the gap left for it.
                padding: _machineCaptionPadding,
                child: SizedBox(
                  height: _machineCaptionHeight,
                  child: Row(
                    children: [
                      // 18px at the rail's 10px gutter puts this glyph's centre
                      // at x=19, which is exactly where SidebarTimeline runs
                      // its trunk. Change either and they part company.
                      Semantics(
                        label: state.isLocalMachine
                            ? 'This computer'
                            : 'Remote machine',
                        child: SizedBox(
                          width: _machineMarkSize,
                          height: _machineMarkSize,
                          child: Icon(
                            state.isLocalMachine
                                ? LucideIcons.laptopMinimal300
                                : LucideIcons.network300,
                            key: const ValueKey('machine-connection-icon'),
                            size: _machineMarkSize,
                            color: connectionColor,
                          ),
                        ),
                      ),
                      // The same 10px SidebarItem puts between its own icon and
                      // label, so the caption and the agents under it start in
                      // one column.
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          machine.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _machineCaptionStyle(
                            _hovered
                                ? grid.AppPalette.textSecondary
                                : grid.AppPalette.textFaint,
                          ),
                        ),
                      ),
                      // How many agents are inside something you have closed.
                      // Only when closed: with the list open you can count
                      // them, and a number beside a list you can see is noise.
                      if (!expanded && state.agents.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            '${state.agents.length}',
                            style: TextStyle(
                              color: grid.AppPalette.textFaint,
                              fontFamily: grid.AppFont.sans,
                              fontSize: 11,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      // One hover control, not two. "New agent" moved INTO this
                      // menu rather than sitting beside it as a second glyph:
                      // the button at the top of the rail already covers the
                      // common case, and this menu is where you go when you
                      // mean THIS machine specifically.
                      SizedBox(
                        width: 22,
                        child: AnimatedOpacity(
                          duration: grid.AppMotion.hover,
                          opacity: _hovered || _menuOpen ? 1 : 0,
                          child: MenuAnchor(
                            controller: _machineMenu,
                            onOpen: () => setState(() => _menuOpen = true),
                            onClose: () => setState(() => _menuOpen = false),
                            menuChildren: [
                              AppMenuItem(
                                icon: LucideIcons.plus300,
                                label: 'New agent here…',
                                onPressed: () {
                                  _machineMenu.close();
                                  showNewAgentDialog(
                                    context,
                                    notifier,
                                    machine.machineId,
                                  );
                                },
                              ),
                              const AppMenuDivider(),
                              AppMenuItem(
                                icon: LucideIcons.pencil300,
                                label: 'Edit name',
                                onPressed: () {
                                  _machineMenu.close();
                                  _showRenameDialog();
                                },
                              ),
                              if (state.isLocalMachine) ...[
                                const AppMenuDivider(),
                                AppMenuItem(
                                  icon: LucideIcons.keyRound300,
                                  label: 'Set remote password',
                                  onPressed: () {
                                    _machineMenu.close();
                                    unawaited(
                                      showLinkMachineDialog(context, notifier),
                                    );
                                  },
                                ),
                              ],
                              if (!state.isLocalMachine) ...[
                                const AppMenuDivider(),
                                AppMenuItem(
                                  icon: LucideIcons.link2300,
                                  label: 'Remote into this machine…',
                                  onPressed: () {
                                    _machineMenu.close();
                                    notifier.selectMachineForSetup(
                                      machine.machineId,
                                    );
                                  },
                                ),
                                const AppMenuDivider(),
                                AppMenuItem(
                                  icon: LucideIcons.trash2300,
                                  label: 'Delete machine',
                                  danger: true,
                                  onPressed: () {
                                    _machineMenu.close();
                                    _confirmDeleteMachine();
                                  },
                                ),
                              ],
                            ],
                            builder: (context, controller, child) =>
                                AppIconButton(
                                  icon: LucideIcons.ellipsis300,
                                  size: 16,
                                  onPressed: () => controller.isOpen
                                      ? controller.close()
                                      : controller.open(),
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (expanded)
          _AgentTree(notifier: notifier, state: state, query: query),
      ],
    );
  }
}

class _AgentTree extends StatelessWidget {
  final AppNotifier notifier;
  final MachineState state;
  final String query;

  const _AgentTree({
    required this.notifier,
    required this.state,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    if (state.agents.isEmpty) {
      switch (state.agentLoadStatus) {
        case AgentLoadStatus.idle:
          return _AgentStatusRow(
            icon: Icons.sync,
            label: state.connectionStatus == ConnectionStatus.connected
                ? 'preparing agent list…'
                : 'connecting…',
          );
        case AgentLoadStatus.needsLink:
          return _AgentStatusRow(
            icon: Icons.link,
            label: 'link required',
            onTap: () =>
                notifier.selectMachineForSetup(state.machine.machineId),
          );
        case AgentLoadStatus.loading:
          // Rows, not a sentence: "loading agents…" is one line tall, so
          // everything under the machine dropped when the real rows arrived.
          return const _AgentRowsSkeleton(key: ValueKey('agents-loading'));
        case AgentLoadStatus.error:
          return _AgentLoadError(notifier: notifier, state: state);
        case AgentLoadStatus.loaded:
          return _EmptyAgents(notifier: notifier, state: state);
      }
    }

    final byParent = <String?, List<Agent>>{};
    final ids = state.agents.map((agent) => agent.id).toSet();
    for (final agent in state.agents) {
      final parent = ids.contains(agent.parentAgentId)
          ? agent.parentAgentId
          : null;
      byParent.putIfAbsent(parent, () => []).add(agent);
    }
    final visible = query.isEmpty
        ? state.agents.map((agent) => agent.id).toSet()
        : state.agents
              .where(
                (agent) =>
                    agent.name.toLowerCase().contains(query) ||
                    (agent.engine?.toLowerCase().contains(query) ?? false) ||
                    (agent.engineDisplayName?.toLowerCase().contains(query) ??
                        false),
              )
              .map((agent) => agent.id)
              .toSet();

    final rows = <Widget>[
      for (final root in byParent[null] ?? const <Agent>[])
        ..._rows(root, byParent, visible, 0, <String>{}),
    ];

    return Column(
      children: [
        if (state.agentsRefreshing) const LinearProgressIndicator(minHeight: 1),
        // The guide arm reaches out to each agent from the trunk running down
        // through its machine's mark. `below` closes the line on the last row:
        // a trunk carrying on past the end would point at whatever section
        // happens to follow, which is not part of this tree.
        for (var i = 0; i < rows.length; i++)
          SidebarTimeline(
            role: SidebarTimelineRole.branch,
            below: i < rows.length - 1,
            child: rows[i],
          ),
        if (state.agentLoadStatus == AgentLoadStatus.needsLink)
          _AgentStatusRow(
            icon: Icons.link,
            label: 'link required',
            onTap: () =>
                notifier.selectMachineForSetup(state.machine.machineId),
          ),
        if (state.agentsLoadError != null)
          _AgentLoadError(notifier: notifier, state: state),
        if (state.terminalCapabilityLoaded &&
            !state.terminalCapabilityAvailable)
          Padding(
            padding: const EdgeInsets.fromLTRB(38, 2, 12, 8),
            child: Text(
              state.terminalCapabilityError ?? 'terminal unavailable',
              style: TextStyle(
                color: grid.AppPalette.dangerFill,
                fontFamily: grid.AppFont.sans,
                fontSize: 11.2,
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _rows(
    Agent agent,
    Map<String?, List<Agent>> byParent,
    Set<String> visible,
    int depth,
    Set<String> ancestors,
  ) {
    if (ancestors.contains(agent.id)) return const [];
    final children = byParent[agent.id] ?? const <Agent>[];
    final descendantVisible = children.any(
      (child) => visible.contains(child.id),
    );
    if (!visible.contains(agent.id) && !descendantVisible) return const [];
    final nextAncestors = {...ancestors, agent.id};
    return [
      _AgentRow(
        notifier: notifier,
        state: state,
        agent: agent,
        depth: depth,
        hasChildren: children.isNotEmpty,
      ),
      for (final child in children)
        ..._rows(child, byParent, visible, depth + 1, nextAncestors),
    ];
  }
}

class _AgentRow extends StatefulWidget {
  final AppNotifier notifier;
  final MachineState state;
  final Agent agent;
  final int depth;
  final bool hasChildren;

  const _AgentRow({
    required this.notifier,
    required this.state,
    required this.agent,
    required this.depth,
    required this.hasChildren,
  });

  @override
  State<_AgentRow> createState() => _AgentRowState();
}

class _AgentRowState extends State<_AgentRow> {
  final MenuController _agentMenu = MenuController();
  bool _menuOpen = false;

  AppNotifier get notifier => widget.notifier;
  MachineState get state => widget.state;
  Agent get agent => widget.agent;
  int get depth => widget.depth;
  bool get hasChildren => widget.hasChildren;

  /// The row's own way into the shared dialog — see rename_agent_dialog.dart.
  Future<void> _showRenameDialog() => showAgentRenameDialog(
    context,
    notifier,
    state.machine.machineId,
    agent.id,
    agent.name,
  );

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete agent'),
        content: SizedBox(
          width: 360,
          child: Text(
            "Delete “${agent.name}”? This can't be undone.",
            style: TextStyle(fontFamily: grid.AppFont.sans, fontSize: 13.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: grid.AppPalette.dangerFill,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final error = await notifier.deleteAgent(state.machine.machineId, agent.id);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  // Restart is disruptive (it briefly kills the current process) but NOT destructive — the same
  // agent survives, resumed where possible — so unlike delete it fires straight away, no
  // confirmation dialog, and just surfaces a failure the same lightweight way.
  Future<void> _restartAgent() async {
    final result = await notifier.restartAgent(
      state.machine.machineId,
      agent.id,
    );
    if (!mounted) return;
    final error = result.error;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (!result.resumed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Restarted with a new session — the previous one could not be resumed.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final machineId = state.machine.machineId;
    // Two different facts, and the grid is why they had to separate. "Selected"
    // used to be the only terminal there was. Now a row can be on screen in a
    // tile the keyboard is not in — still worth showing, but not as the current
    // one, or four rows would claim to be current at once.
    final focusedHere =
        notifier.focusedPane?.machineId == machineId &&
        notifier.focusedPane?.agentId == agent.id;
    final inAnotherPane =
        !focusedHere && notifier.isAgentInPane(machineId, agent.id);
    final selected = focusedHere;
    // Cached agents remain selectable while the adapter is offline so the
    // user gets the actionable `harness login` guide instead of a dead row.
    final offlineSelectable =
        state.nodeOnline == false && agent.terminalAvailable;
    final enabled =
        offlineSelectable ||
        // `connected` never arrives until the local CLI has finished terminating E2EE for this
        // machine (or confirmed none is needed, for its own) — no separate readiness check left.
        state.connectionStatus == ConnectionStatus.connected &&
            state.terminalCapabilityAvailable &&
            agent.terminalAvailable;
    // A cached agent under an offline machine stays clickable (`offlineSelectable`, above) so the
    // login guide is reachable — but it should still LOOK offline, not bright/normal. Decouple the
    // visual state from `enabled` (which only governs tap-ability) so the row dims whenever the
    // machine itself is offline, regardless of whether it's still selectable.
    final visuallyEnabled = enabled && state.nodeOnline != false;
    final reason = !agent.terminalAvailable
        ? agent.terminalUnavailableReason
        : offlineSelectable
        ? 'Harness is offline — run harness login'
        : !state.terminalCapabilityAvailable
        ? state.terminalCapabilityError
        : null;
    final identity = engineIdentity(
      agent.engine,
      displayName: agent.engineDisplayName,
    );
    final processing = state.processingAgentIds.contains(agent.id);
    // Right-click wraps the row rather than fighting it: SidebarItem owns the
    // primary tap and the press/hover states that go with it, and exposes no
    // secondary gesture.
    final row = GestureDetector(
      behavior: HitTestBehavior.translucent,
      // Right-click opens the SAME menu the ⋯ does. Two menus carrying the same
      // two actions in two different shapes is the drift this avoids; the only
      // thing lost is opening at the cursor rather than at the button.
      onSecondaryTap: _agentMenu.open,
      child: Padding(
        // 28px is where a nested row's box starts, which is what the guide's
        // arm is drawn to reach (trunk at 19, arm 7 long, stopping 2px short of
        // the row's own hover fill). Without it the agents line up under the
        // machine's own mark and the arm points at nothing. Sub-agents step in
        // further from there.
        padding: EdgeInsets.only(left: 28 + depth * 14.0),
        child: SidebarItem(
          label: agent.name,
          selected: selected,
          enabled: enabled,
          dimmed: !visuallyEnabled,
          onTap: () => notifier.selectAgent(state.machine.machineId, agent.id),
          // The same "Edit name" the row's own menu opens — a double click is
          // just the shorter way to it, and the place a hand reaches first.
          onDoubleTap: _showRenameDialog,

          // No tooltip on a row that works. "Claude engine" only repeated what
          // the mark beside it already says, and it followed the pointer down
          // the whole list. A row that CANNOT be used keeps one, because then
          // it carries the reason — which is the only thing here the row
          // itself cannot show.
          tooltip: enabled ? null : (reason ?? 'machine not ready'),
          // The engine's mark in a well, which is what carries the row now
          // that the guide line is gone. A bare 16px logo floating at the head
          // of a flat list left the column no left edge to sit on; the well is
          // a translucent overlay (see [grid.AppSurface.wellFill]) so it keeps
          // its edge on the hovered and the selected row too.
          leading: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: grid.AppSurface.wellFill,
              borderRadius: BorderRadius.circular(7),
            ),
            child: SizedBox(
              width: 15,
              height: 15,
              child: Semantics(
                label: '${identity.label} engine',
                image: true,
                child: EngineMark(
                  engine: agent.engine,
                  displayName: agent.engineDisplayName,
                  enabled: visuallyEnabled,
                  size: 15,
                ),
              ),
            ),
          ),
          // A turn in flight is a FACT about the row, so it goes in the badge
          // slot, which never hides. Reaching for the row must not take away
          // the only sign that it is busy.
          badge: SizedBox(
            width: 16,
            height: 16,
            child: AnimatedSwitcher(
              duration: grid.AppMotion.hover,
              child: processing
                  ? Padding(
                      key: const ValueKey('processing'),
                      padding: const EdgeInsets.all(2),
                      child: CircularProgressIndicator(
                        key: const ValueKey('agent-processing-indicator'),
                        strokeWidth: 1.6,
                        color: grid.AppPalette.online,
                      ),
                    )
                  : inAnotherPane
                  ? Tooltip(
                      key: const ValueKey('in-pane'),
                      message: 'Open in another pane',
                      child: Icon(
                        Icons.crop_square,
                        size: 12,
                        color: grid.AppPalette.textFaint,
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('idle')),
            ),
          ),
          // The ⋯ is an ACTION, so it arrives with the pointer — except while
          // its own menu is open, where a button that vanished under the menu
          // it opened would leave the panel pointing at nothing.
          trailingAlwaysVisible: _menuOpen,
          trailing: MenuAnchor(
            controller: _agentMenu,
            onOpen: () => setState(() => _menuOpen = true),
            onClose: () => setState(() => _menuOpen = false),
            menuChildren: [
              AppMenuItem(
                icon: LucideIcons.pencil300,
                label: 'Edit name',
                onPressed: () {
                  _agentMenu.close();
                  _showRenameDialog();
                },
              ),
              const AppMenuDivider(),
              AppMenuItem(
                icon: LucideIcons.refreshCw300,
                label: 'Restart',
                onPressed: () {
                  _agentMenu.close();
                  _restartAgent();
                },
              ),
              const AppMenuDivider(),
              AppMenuItem(
                icon: LucideIcons.trash2300,
                label: 'Delete',
                danger: true,
                onPressed: () {
                  _agentMenu.close();
                  _confirmDelete();
                },
              ),
            ],
            builder: (context, controller, child) => AppIconButton(
              icon: LucideIcons.ellipsis300,
              size: 16,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
          ),
        ),
      ),
    );

    // A row that cannot be opened cannot be dropped either: dragging it would
    // promise a tile that assignAgentToPane would then refuse to fill, and the
    // grid would answer a deliberate gesture with nothing at all.
    if (!enabled) return row;

    return Draggable<AgentDragRef>(
      data: AgentDragRef(
        machineId: machineId,
        agentId: agent.id,
        name: agent.name,
      ),
      // Horizontal only, and the rail is a scrolling list — that is the whole
      // reason. An unrestricted Draggable competes with the list's own vertical
      // drag, so trying to scroll past a row would pick the row up instead. The
      // tiles are to the RIGHT of the rail, so the gesture that means "take
      // this there" is horizontal anyway, and the two never contend.
      affinity: Axis.horizontal,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => agentDrag.value = AgentDragRef(
        machineId: machineId,
        agentId: agent.id,
        name: agent.name,
      ),
      onDragEnd: (_) => agentDrag.value = null,
      onDraggableCanceled: (_, _) => agentDrag.value = null,
      feedback: _DragChip(name: agent.name, engine: agent.engine),
      // The row stays put and dims. Removing it would reflow the list under the
      // pointer mid-drag, moving every other row out from under the place the
      // hand had already aimed at.
      childWhenDragging: Opacity(opacity: 0.4, child: row),
      child: row,
    );
  }
}

/// What travels with the pointer: enough to recognise the row it came from,
/// small enough not to cover the tile being aimed at.
class _DragChip extends StatelessWidget {
  const _DragChip({required this.name, required this.engine});

  final String name;
  final String? engine;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: grid.AppPalette.windowBg,
          border: Border.all(color: grid.AppPalette.divider),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            EngineMark(engine: engine, size: 14),
            const SizedBox(width: 7),
            Text(
              name,
              style: TextStyle(
                color: grid.AppPalette.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The machine list before the backend has answered: three rows on the guide
/// line, at a [SidebarItem]'s exact geometry.
///
/// Three because the rail is a list pane and most accounts have a few
/// machines; a skeleton taller than the answer jumps up when it lands.
class _MachineListSkeleton extends StatelessWidget {
  const _MachineListSkeleton({super.key});

  static const _labels = [0.56, 0.42, 0.64];

  @override
  Widget build(BuildContext context) => SkeletonList(
    rows: 3,
    semanticsLabel: 'Loading machines',
    itemBuilder: (context, i) => SidebarTimeline(
      role: SidebarTimelineRole.node,
      above: i > 0,
      below: false,
      child: _MachineCaptionSkeleton(labelFactor: _labels[i]),
    ),
  );
}

/// A machine caption with nothing in it yet.
///
/// Not [_SidebarRowSkeleton]: that one stands in for a [SidebarItem], which is
/// what an AGENT row is. A machine is a caption at half the label size in a
/// shorter box, and a placeholder built to the wrong one resizes the rail as
/// the answer lands — which is the whole thing a skeleton exists to avoid.
class _MachineCaptionSkeleton extends StatelessWidget {
  const _MachineCaptionSkeleton({required this.labelFactor});

  final double labelFactor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: _machineCaptionPadding,
    child: SizedBox(
      height: _machineCaptionHeight,
      child: Row(
        children: [
          Skeleton(
            width: _machineMarkSize,
            height: _machineMarkSize,
            radius: 5,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SkeletonText(
              style: _machineCaptionStyle(grid.AppPalette.textFaint),
              widthFactor: labelFactor,
            ),
          ),
        ],
      ),
    ),
  );
}

/// A machine's agents before `agents_list` has answered: two rows where the
/// agents will go, threaded onto the same guide line they will hang from.
class _AgentRowsSkeleton extends StatelessWidget {
  const _AgentRowsSkeleton({super.key});

  static const _rows = 2;
  static const _labels = [0.48, 0.36];

  @override
  Widget build(BuildContext context) => SkeletonList(
    rows: _rows,
    fadeDepth: skeletonFadeLight,
    semanticsLabel: 'Loading agents',
    itemBuilder: (context, i) => SidebarTimeline(
      role: SidebarTimelineRole.branch,
      below: i < _rows - 1,
      child: Padding(
        // Where a nested row's box starts — see [_AgentRow].
        padding: const EdgeInsets.only(left: 28),
        child: _SidebarRowSkeleton(
          leading: 16,
          leadingRadius: 4,
          labelFactor: _labels[i],
        ),
      ),
    ),
  );
}

/// A [SidebarItem] with nothing in it yet: the same 1px margin, 36px box,
/// icon gutter and label strut, so a placeholder row and a real one measure
/// the same to the pixel — the row's label pins its metrics with a strut, and
/// a bar measured without it comes out a pixel short.
class _SidebarRowSkeleton extends StatelessWidget {
  const _SidebarRowSkeleton({
    required this.leading,
    required this.leadingRadius,
    required this.labelFactor,
  });

  final double leading;
  final double leadingRadius;
  final double labelFactor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: SizedBox(
      height: 36,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(SidebarItem.iconGutter, 0, 5, 0),
        child: Row(
          children: [
            Skeleton(width: leading, height: leading, radius: leadingRadius),
            const SizedBox(width: 10),
            Expanded(
              child: SkeletonText(
                style: const TextStyle(fontSize: 13.7, height: 1.25),
                strutStyle: const StrutStyle(
                  fontSize: 13.5,
                  height: 1.25,
                  forceStrutHeight: true,
                ),
                widthFactor: labelFactor,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AgentStatusRow extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final String label;

  const _AgentStatusRow({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return InkWell(
      key: onTap == null ? null : const ValueKey('link-required'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(38, 3, 12, 9),
        child: Row(
          children: [
            Icon(
              icon,
              size: 12,
              color: onTap == null
                  ? grid.AppPalette.textFaint
                  : grid.AppPalette.accentOnSurface,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: onTap == null
                      ? grid.AppPalette.textFaint
                      : grid.AppPalette.textSecondary,
                  fontFamily: grid.AppFont.sans,
                  fontSize: 11.2,
                ),
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.arrow_forward_ios,
                size: 10,
                color: grid.AppPalette.textFaint,
              ),
          ],
        ),
      ),
    );
  }
}

class _AgentLoadError extends StatelessWidget {
  final AppNotifier notifier;
  final MachineState state;

  const _AgentLoadError({required this.notifier, required this.state});

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(38, 2, 8, 8),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 12,
            color: grid.AppPalette.dangerFill,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              state.agentsLoadError ?? 'Could not load agents',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: grid.AppPalette.dangerFill,
                fontFamily: grid.AppFont.sans,
                fontSize: 11.2,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 14),
            color: grid.AppPalette.textSecondary,
            tooltip: 'Retry agents',
            onPressed: () =>
                notifier.reloadMachineData(state.machine.machineId),
          ),
        ],
      ),
    );
  }
}

class _EmptyAgents extends StatelessWidget {
  final AppNotifier notifier;
  final MachineState state;
  const _EmptyAgents({required this.notifier, required this.state});

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(38, 2, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'no running agents',
              style: TextStyle(
                color: grid.AppPalette.textFaint,
                fontFamily: grid.AppFont.sans,
                fontSize: 13.5,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 14),
            color: grid.AppPalette.textSecondary,
            tooltip: 'Reload agents',
            onPressed: () =>
                notifier.reloadMachineData(state.machine.machineId),
          ),
        ],
      ),
    );
  }
}
