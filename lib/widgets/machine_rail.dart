import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../core/models.dart';
import '../shared/layouts/widgets/rail_section_header.dart';
import '../shared/layouts/widgets/sidebar_item.dart';
import '../shared/layouts/widgets/sidebar_timeline.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_icon_button.dart';
import '../shared/widgets/app_menu.dart';
import '../shortcuts/app_shortcuts.dart';
import '../state/app_state.dart';
import 'agent_drag.dart';
import 'account_footer.dart';
import 'engine_identity.dart';
import 'link_machine_dialog.dart';
import 'new_agent_dialog.dart';
import 'window_chrome.dart';

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
            // The head is also the window's drag handle — the title bar is
            // hidden (see configureDesktopWindow) — and on macOS it leaves
            // room above the wordmark for the traffic lights, as Grid's
            // sidebar does. No rule under it: Grid draws none, and a rule here
            // would sit 32px below the pane header's and read as a mistake.
            DragToMoveArea(
              child: Padding(
                padding: EdgeInsets.only(top: railTopInset),
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
            ),
            if (_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    focusNode: _filterFocus,
                    style: TextStyle(
                      color: grid.AppPalette.textSecondary,
                      fontFamily: grid.AppFont.sans,
                      fontSize: 13.5,
                    ),
                    decoration: InputDecoration(
                      hintText: 'filter machines / agents',
                      hintStyle: TextStyle(color: grid.AppPalette.textFaint),
                      prefixIcon: Icon(
                        LucideIcons.search300,
                        size: 16,
                        color: grid.AppPalette.textFaint,
                      ),
                      filled: true,
                      fillColor: grid.AppPalette.windowBg,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: grid.AppPalette.divider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: grid.AppPalette.divider),
                      ),
                    ),
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                  ),
                ),
              ),
            const RailSectionHeader(label: 'Machines'),
            Expanded(
              child: machines.isEmpty
                  ? Center(
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
            AccountFooter(notifier: widget.notifier),
          ],
        );
      },
    );
  }
}

class _MachineNode extends StatefulWidget {
  /// Whether the guide line arrives from a row above. False on the first
  /// machine, where a line dangling up towards the section heading would point
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
                  style: const TextStyle(fontSize: 13.5),
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
              child: const Text('Cancel', style: TextStyle(fontSize: 13.5)),
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
              child: const Text('Save', style: TextStyle(fontSize: 13.5)),
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
            child: const Text('Cancel', style: TextStyle(fontSize: 13.5)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: grid.AppPalette.dangerFill,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(fontSize: 13.5)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final error = await notifier.deleteMachine(machine.machineId);
    if (error != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
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
        // A node on the rail's guide line, not a row that happens to sit above
        // some others: the line breaks around the machine's own mark so the
        // agents under it read as threaded onto it.
        SidebarTimeline(
          role: SidebarTimelineRole.node,
          above: !widget.isFirst,
          below: expanded && state.agents.isNotEmpty,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            // Same menu the ⋯ opens — one shape for one set of actions.
            onSecondaryTap: _machineMenu.open,
            child: SidebarItem(
              key: ValueKey('machine-row-${machine.machineId}'),
              label: machine.displayName,
              onTap: () => notifier.toggleExpand(machine.machineId),
              // The chevron and the machine's state travel as one mark. The
              // colour is the answer to "can I reach this?", and putting it on
              // the icon the line threads keeps question and answer together.
              //
              // Which KIND of machine it is rides the same glyph: the lid you
              // are sitting at, or nodes on a wire you reach across. It used to
              // be a monitor for every machine plus a 13px house beside the
              // local one — two marks where the rail has room for one, and two
              // machines that looked identical until you found the house.
              leading: Semantics(
                label: state.isLocalMachine
                    ? 'This computer'
                    : 'Remote machine',
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: Icon(
                    state.isLocalMachine
                        ? LucideIcons.laptopMinimal300
                        : LucideIcons.network300,
                    key: const ValueKey('machine-connection-icon'),
                    size: 18,
                    color: connectionColor,
                  ),
                ),
              ),
              // Two actions, so the row reserves room for two. At the default
              // width one clips the other.
              trailingWidth: 52,
              trailingAlwaysVisible: _menuOpen,
              trailing: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  MenuAnchor(
                    controller: _machineMenu,
                    style: appMenuStyle(),
                    onOpen: () => setState(() => _menuOpen = true),
                    onClose: () => setState(() => _menuOpen = false),
                    menuChildren: [
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
                            unawaited(showLinkMachineDialog(context, notifier));
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
                            notifier.selectMachineForSetup(machine.machineId);
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
                    builder: (context, controller, child) => AppIconButton(
                      icon: LucideIcons.ellipsis300,
                      size: 16,
                      onPressed: () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                    ),
                  ),
                  const SizedBox(width: 2),
                  AppIconButton(
                    icon: LucideIcons.plus300,
                    size: 16,
                    tooltip: withShortcutHint(
                      'New agent',
                      ShortcutAction.newAgent,
                    ),
                    onPressed: () => showNewAgentDialog(
                      context,
                      notifier,
                      machine.machineId,
                    ),
                  ),
                ],
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
          return const _AgentStatusRow(
            icon: Icons.sync,
            label: 'loading agents…',
            loading: true,
          );
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

  Future<void> _showRenameDialog() async {
    final controller = TextEditingController(text: agent.name);
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
                  style: const TextStyle(fontSize: 13.5),
                  onSubmitted: (_) async {
                    final result = await notifier.renameAgent(
                      state.machine.machineId,
                      agent.id,
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
              child: const Text('Cancel', style: TextStyle(fontSize: 13.5)),
            ),
            FilledButton(
              onPressed: () async {
                final result = await notifier.renameAgent(
                  state.machine.machineId,
                  agent.id,
                  controller.text,
                );
                if (result == null) {
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                } else {
                  setDialogState(() => error = result);
                }
              },
              child: const Text('Save', style: TextStyle(fontSize: 13.5)),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

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
            child: const Text('Cancel', style: TextStyle(fontSize: 13.5)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: grid.AppPalette.dangerFill,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(fontSize: 13.5)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final error = await notifier.deleteAgent(state.machine.machineId, agent.id);
    if (error != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
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
        // arm is drawn to reach; without it the agents line up under the
        // machine's own mark and the arm points at nothing. Sub-agents step in
        // further from there.
        padding: EdgeInsets.only(left: 28 + depth * 14.0),
        child: SidebarItem(
          label: agent.name,
          selected: selected,
          enabled: enabled,
          dimmed: !visuallyEnabled,
          onTap: () => notifier.selectAgent(state.machine.machineId, agent.id),
          // No tooltip on a row that works. "Claude engine" only repeated what
          // the mark beside it already says, and it followed the pointer down
          // the whole list. A row that CANNOT be used keeps one, because then
          // it carries the reason — which is the only thing here the row
          // itself cannot show.
          tooltip: enabled ? null : (reason ?? 'machine not ready'),
          leading: SizedBox(
            width: 16,
            height: 16,
            child: Semantics(
              label: '${identity.label} engine',
              image: true,
              child: EngineMark(
                engine: agent.engine,
                displayName: agent.engineDisplayName,
                enabled: visuallyEnabled,
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
            style: appMenuStyle(),
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

class _AgentStatusRow extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final String label;
  final bool loading;

  const _AgentStatusRow({
    required this.icon,
    required this.label,
    this.loading = false,
    this.onTap,
  });

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
            if (loading)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              )
            else
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
