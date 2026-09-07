/// Which grid new agents launch against, in the sidebar — the answer, and the control that changes
/// it, in the place the answer is wanted.
///
/// The choice lived in Settings ▸ Grid alone, which made switching a four-step trip through a
/// full-window screen for something people change between one agent and the next. This pill is the
/// same [GridSelectionStore] under a menu; Settings keeps its table, which is where a grid is
/// *compared* — owner, type, router, roles — rather than merely picked.
///
/// ⚠️ Picking here retargets NOTHING that is already running: an engine's environment is fixed at
/// exec. The menu's standing note says so, and an agent already up is moved from its own header
/// (`widgets/agent_model_menu.dart`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../analytics/analytics.dart';
import '../grid/grid_networks_controller.dart';
import '../grid/grid_selection_store.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_section.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_menu.dart';
import '../state/app_state.dart';

/// One row the grid picker can show: a real choice, or — while the grids load, after the load
/// failed, or on an account with none — a disabled line that exists to be read, not picked.
///
/// A null [networkId] on an ENABLED option is "own login"; on a disabled one it means nothing,
/// because a placeholder is never the thing picked.
@immutable
class GridTargetOption {
  const GridTargetOption({
    required this.label,
    this.networkId,
    this.enabled = true,
  });

  final String label;
  final String? networkId;
  final bool enabled;
}

/// The picker's rows, from whatever the shared controller has so far.
///
/// Own login comes FIRST and unconditionally — it is the only choice that needs no network call, so
/// it must not be a row that appears once a fetch lands. Pure, so the states a menu is hard to open
/// in (mid-load, failed, an account on no grids) are covered by a test rather than by hand.
List<GridTargetOption> gridTargetMenuOptions(GridNetworksState state) => [
  const GridTargetOption(label: kOwnLoginTargetLabel),
  ...switch (state) {
    GridNetworksIdle() || GridNetworksLoading() => const [
      GridTargetOption(label: 'Loading grids…', enabled: false),
    ],
    // No Grid sign-in on this computer. Said as a disabled row rather than
    // offered as one: signing in is a real action with a real failure mode, and
    // a menu that opens upward off a pill at the window's edge is the wrong
    // place to run it. Settings ▸ Grid has the button.
    GridNetworksSignedOut() => const [
      GridTargetOption(label: 'Sign in to Grid in Settings', enabled: false),
    ],
    // Already user-facing — GridApiClient turns the API's failure shapes into a sentence.
    GridNetworksFailed(:final message) => [
      GridTargetOption(label: message, enabled: false),
    ],
    GridNetworksReady(:final me) =>
      me.networks.isEmpty
          ? const [
              GridTargetOption(
                label: 'This account is on no grids',
                enabled: false,
              ),
            ]
          : [
              for (final network in me.networks)
                GridTargetOption(
                  label: network.displayName,
                  networkId: network.networkId,
                ),
            ],
  },
];

/// The rail's grid row: what new agents use, and a menu to change it.
class GridTargetPill extends StatefulWidget {
  const GridTargetPill({
    super.key,
    required this.notifier,
    this.networks,
    this.selection,
  });

  final AppNotifier notifier;

  /// Both injected by tests. The app uses the shared singletons, which is what lets this pill, the
  /// Settings pane and the New agent dialog change — and see — the same choice.
  final GridNetworksController? networks;
  final GridSelectionStore? selection;

  @override
  State<GridTargetPill> createState() => _GridTargetPillState();
}

class _GridTargetPillState extends State<GridTargetPill> {
  /// Held here because [AppMenuItem] does not close the panel for you.
  final _menu = MenuController();

  GridNetworksController get _networks =>
      widget.networks ?? gridNetworksController;
  GridSelectionStore get _selection => widget.selection ?? gridSelectionStore;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ValueListenableBuilder<GridSelection>(
      valueListenable: _selection,
      builder: (context, chosen, _) => ListenableBuilder(
        // Keeps an ALREADY-OPEN menu's rows current as the controller moves Idle → Loading → Ready,
        // rather than freezing them at the moment it was opened.
        listenable: _networks,
        builder: (context, _) => MenuAnchor(
          controller: _menu,
          alignmentOffset: const Offset(8, -8),
          // Wider than the rail, and capped taller than a plain menu: this one opens UPWARD off a
          // pill at the window's bottom edge, and an account on a dozen grids scrolls inside it
          // rather than lifting the panel clear of the control it belongs to.
          style: grid.AppMenu.style(
            minWidth: 248,
            maxWidth: _panelMaxWidth,
            maxHeight: 420,
          ),
          // Cheap on every open: only the first one fetches.
          onOpen: _networks.ensureLoaded,
          menuChildren: _rows(chosen),
          builder: (context, controller, _) => _Pill(
            open: controller.isOpen,
            chosen: chosen,
            onTap: controller.isOpen ? controller.close : controller.open,
          ),
        ),
      ),
    );
  }

  /// The panel's width, stated once.
  ///
  /// Read by [AppMenu.style] AND by the note at the top of the list, which
  /// cannot wrap without it. Two literals that have to agree is exactly how the
  /// note ends up clipped again.
  static const double _panelMaxWidth = 304;

  List<Widget> _rows(GridSelection chosen) => [
    const AppMenuNote(
      'New agents only. Agents already running keep the grid they started on.',
      // The same 304 handed to [AppMenu.style] below. A sentence this long has
      // to be told the panel's width or it is clipped rather than wrapped.
      panelWidth: _panelMaxWidth,
    ),
    const AppMenuDivider(),
    for (final option in gridTargetMenuOptions(_networks.state))
      if (option.enabled)
        AppMenuItem(
          label: option.label,
          selected: option.networkId == chosen.networkId,
          onPressed: () {
            _menu.close();
            unawaited(_pick(option));
          },
        )
      else
        AppMenuNote(option.label),
    if (_networks.state is GridNetworksFailed)
      AppMenuItem(
        icon: LucideIcons.refreshCw300,
        label: 'Try again',
        onPressed: () {
          _menu.close();
          unawaited(_networks.refresh());
        },
      ),
    const AppMenuDivider(),
    AppMenuItem(
      key: const Key('rail-grid-settings-item'),
      icon: LucideIcons.settings300,
      label: 'Grid settings…',
      onPressed: () {
        _menu.close();
        unawaited(
          showSettingsScreen(
            context,
            widget.notifier,
            gridNetworks: _networks,
            initialSection: SettingsSection.grid,
          ),
        );
      },
    ),
  ];

  Future<void> _pick(GridTargetOption option) {
    final networkId = option.networkId;
    analytics.gridPicked(source: 'pill', networkId: networkId);
    return networkId == null
        ? _selection.clear()
        : _selection.selectNetwork(
            networkId: networkId,
            networkName: option.label,
          );
  }
}

/// The row you press to reach the picker — the account pill's twin, one step quieter, so the two
/// read as one footer rather than as two competing controls.
class _Pill extends StatefulWidget {
  const _Pill({required this.open, required this.chosen, required this.onTap});

  final bool open;
  final GridSelection chosen;
  final VoidCallback onTap;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final on = widget.chosen.hasGrid;
    final lit = _hovered || widget.open;
    return Tooltip(
      message: on
          ? 'New agents run on ${widget.chosen.label}'
          : 'New agents use each engine’s own login',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const Key('rail-grid-target-button'),
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: grid.AppMotion.hover,
            curve: grid.AppMotion.curve,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            decoration: BoxDecoration(
              color: lit ? grid.AppSurface.recessHover : grid.AppSurface.recess,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.zap300,
                  size: 16,
                  // Lit only when a grid is actually in force: the glyph is the one part of this
                  // row readable at a glance, so it must not say "on" while the value says own
                  // login.
                  color: on
                      ? grid.AppPalette.accentOnSurface
                      : grid.AppPalette.textFaint,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEW AGENTS USE',
                        style: TextStyle(
                          color: grid.AppPalette.textFaint,
                          fontFamily: grid.AppFont.sans,
                          fontFamilyFallback: grid.AppFont.sansFallback,
                          fontSize: 9.5,
                          fontWeight: grid.AppFont.semibold,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        widget.chosen.targetLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: on
                              ? grid.AppPalette.textPrimary
                              : grid.AppPalette.textSecondary,
                          fontFamily: grid.AppFont.sans,
                          fontFamilyFallback: grid.AppFont.sansFallback,
                          fontSize: 12.5,
                          fontWeight: on
                              ? grid.AppFont.medium
                              : grid.AppFont.regular,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.chevronDown300,
                  size: 14,
                  color: grid.AppPalette.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
