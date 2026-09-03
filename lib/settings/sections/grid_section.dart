import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../grid/grid_models_controller.dart';
import '../../grid/grid_network.dart';
import '../../grid/grid_networks_controller.dart';
import '../../grid/grid_selection_store.dart';
import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/widgets/app_icon_button.dart';
import '../../shared/widgets/section_scaffold.dart';
import '../../shared/widgets/skeleton.dart';
import 'grid_network_table.dart';
import 'grid_target_strip.dart';

/// Settings ▸ Grid: where new agents send their inference, and every grid this
/// account could send it to instead.
///
/// Read straight from the Grid control plane over HTTPS — this screen does not
/// go through the `harness` CLI, which knows nothing about Grid accounts. See
/// [GridApiClient].
///
/// The pane is a **picker wearing a table**: the strip at the top says what is
/// in force, the table under it is the radio group that changes it, and the
/// filter between them exists because an account on twenty grids should not
/// have to scroll to find the one it means. Picking here retargets nothing that
/// is already running — the strip's own wording is what says so.
class GridSection extends StatefulWidget {
  const GridSection({
    super.key,
    required this.controller,
    this.selection,
    this.models,
  });

  final GridNetworksController controller;

  /// Injected by tests. The app uses the shared singletons, which is what lets
  /// this pane and the sidebar's [GridSelector] change the same choice.
  final GridSelectionStore? selection;
  final GridModelsController? models;

  @override
  State<GridSection> createState() => _GridSectionState();
}

class _GridSectionState extends State<GridSection> {
  String _query = '';
  _GridFilter _filter = _GridFilter.all;

  GridSelectionStore get _selection => widget.selection ?? gridSelectionStore;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // Cheap on every rebuild: only the first call fetches.
    widget.controller.ensureLoaded();
    // The whole pane, heading included, hangs off the controller: the count
    // beside the title is part of the load, so a scaffold built outside this
    // builder would keep saying nothing after the grids arrived.
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        final total = state is GridNetworksReady
            ? state.me.networks.length
            : null;
        final loading =
            state is GridNetworksIdle || state is GridNetworksLoading;
        final countStyle = TextStyle(
          color: grid.AppPalette.textFaint,
          fontSize: 12.5,
        );
        return SectionScaffold(
          title: 'Grid',
          // The count is part of the load, so while it is unknown the heading
          // wears a bar of the same height rather than nothing: a heading that
          // grows a figure a beat after the table is a heading that moved.
          titleTrailing: total == null
              ? (loading
                    ? SkeletonText(
                        key: const Key('grid-count-skeleton'),
                        style: countStyle,
                        width: 44,
                      )
                    : null)
              : Text(
                  '$total grid${total == 1 ? '' : 's'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: countStyle,
                ),
          subtitle:
              'Every grid this account can reach, and which one new agents '
              'launch against. Agents already running stay where they are.',
          child: switch (state) {
            // The strip does not wait on the network — it reads the choice
            // already on disk — so it is real from the first frame. Only the
            // table and the count are placeholders.
            GridNetworksIdle() || GridNetworksLoading() => _body(null, null),
            GridNetworksFailed(:final message) => _Failed(
              message: message,
              onRetry: () => unawaited(widget.controller.refresh()),
            ),
            GridNetworksReady(:final me) => _body(me.user.email, me.networks),
          },
        );
      },
    );
  }

  /// The pane's one layout, with or without its answer. [email] and
  /// [networks] are null while the grids load, and every part that depends
  /// on them is then drawn at its final size and left blank.
  Widget _body(String? email, List<GridNetwork>? networks) {
    final visible = email == null || networks == null
        ? null
        : _visible(email, networks);
    return ValueListenableBuilder<GridSelection>(
      valueListenable: _selection,
      builder: (context, chosen, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridTargetStrip(
            selection: _selection,
            chosen: chosen,
            models: widget.models,
          ),
          const SizedBox(height: 16),
          _FilterBar(
            query: _query,
            filter: _filter,
            shown: visible?.length,
            total: networks?.length,
            email: email,
            onQuery: (value) => setState(() => _query = value),
            onFilter: (value) => setState(() => _filter = value),
            onReload: () => unawaited(widget.controller.refresh()),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: visible == null
                ? GridNetworkTableSkeleton(
                    key: const Key('grid-table-skeleton'),
                    noGridSelected: chosen.networkId == null,
                  )
                : GridNetworkTable(
                    networks: visible,
                    signedInEmail: email!,
                    selectedId: chosen.networkId,
                    filtered: visible.length != networks!.length,
                    onUse: (network) => unawaited(
                      network == null
                          ? _selection.clear()
                          : _selection.selectNetwork(
                              networkId: network.networkId,
                              networkName: network.displayName,
                            ),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            'Switching grids clears the model — a model id only means '
            'something on the grid that serves it.',
            style: TextStyle(color: grid.AppPalette.textFaint, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  /// The grids the filter and the query leave standing.
  ///
  /// Matching is a plain case-insensitive substring across the fields a person
  /// would type — the name, the id, the owner, the type, the roles — for the
  /// reason the settings rail's own filter gives: anything cleverer is
  /// machinery nobody can feel.
  List<GridNetwork> _visible(String email, List<GridNetwork> networks) {
    final query = _query.trim().toLowerCase();
    return [
      for (final network in networks)
        if (_filter.admits(network, email) &&
            (query.isEmpty || _haystack(network).contains(query)))
          network,
    ];
  }

  String _haystack(GridNetwork network) => [
    network.displayName,
    network.networkId,
    network.ownerEmail,
    network.networkType,
    ...?network.member?.roles,
  ].join(' ').toLowerCase();
}

/// The three questions worth asking of a list of grids.
///
/// Not a general facet builder: these are the axes that decide whether a grid
/// is one you can act on — is it mine, and does it route.
enum _GridFilter {
  all('All'),
  owned('You own'),
  router('Router on');

  const _GridFilter(this.label);

  final String label;

  bool admits(GridNetwork network, String email) => switch (this) {
    _GridFilter.all => true,
    _GridFilter.owned => network.isOwnedBy(email),
    _GridFilter.router => network.routerEnabled,
  };
}

/// Narrow the table, and say whose grids these are.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.query,
    required this.filter,
    required this.shown,
    required this.total,
    required this.email,
    required this.onQuery,
    required this.onFilter,
    required this.onReload,
  });

  final String query;
  final _GridFilter filter;

  /// All three null while the grids load: the controls are real (a query
  /// typed early is kept), the line that names whose grids these are is not.
  final int? shown;
  final int? total;
  final String? email;
  final ValueChanged<String> onQuery;
  final ValueChanged<_GridFilter> onFilter;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 210,
                child: TextField(
                  key: const Key('grid-filter-field'),
                  onChanged: onQuery,
                  style: grid.kFieldTextStyle,
                  decoration: InputDecoration(
                    hintText: 'Filter grids',
                    prefixIcon: Icon(
                      LucideIcons.search300,
                      size: grid.kFieldIconSize,
                      color: grid.AppPalette.textFaint,
                    ),
                  ),
                ),
              ),
              for (final option in _GridFilter.values)
                _Chip(
                  label: option.label,
                  selected: option == filter,
                  onTap: () => onFilter(option),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Capped rather than flexible: a `Flexible` here has the same flex as
        // the search-and-chips side and so reserves half the bar for an email
        // and a 16px button, which is what pushed the last chip onto a line of
        // its own. Bounded, it takes what it needs and the filters keep the
        // rest.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: email == null
                    ? const SkeletonText(
                        style: TextStyle(fontSize: 12),
                        width: 150,
                        alignment: Alignment.centerRight,
                      )
                    : Text(
                        // The plain total lives on the heading now. This line
                        // says whose grids these are, and speaks up only when
                        // the filter is hiding some of them.
                        shown == total
                            ? email!
                            : '$shown of $total grids · $email',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: grid.AppPalette.textFaint,
                          fontSize: 12,
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              AppIconButton(
                key: const Key('grid-refresh-button'),
                icon: LucideIcons.refreshCw300,
                size: 16,
                tooltip: 'Reload grids',
                onPressed: onReload,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A filter's on/off state, in the app's accent wash — the same treatment the
/// rail gives the section you are in, because it means the same thing: this is
/// what you are looking at.
class _Chip extends StatefulWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: grid.AppMotion.hover,
          curve: grid.AppMotion.curve,
          height: grid.AppControl.height,
          // Padding, and NOT `alignment` — a Container with an alignment wraps
          // its child in an unbounded Align, which fills whatever it is offered.
          // Inside the filter bar's Wrap that is the bar's whole width, so each
          // chip took a run of its own and the row came out as a stack of
          // full-width bars.
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: widget.selected
                ? grid.AppPalette.accent
                : (_hovered ? grid.AppSurface.hoverFill : Colors.transparent),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: widget.selected
                  ? grid.AppPalette.accent
                  : grid.AppGlass.hair,
            ),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              widget.label,
              style: TextStyle(
                color: widget.selected
                    ? Colors.white
                    : grid.AppPalette.textSecondary,
                fontSize: 12,
                fontWeight: widget.selected
                    ? grid.AppFont.semibold
                    : grid.AppFont.regular,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The load failed — say what went wrong and leave a way to try again, rather
/// than an empty pane that looks like an account with no grids.
class _Failed extends StatelessWidget {
  const _Failed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: grid.AppPalette.warn.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: grid.AppPalette.warn.withValues(alpha: 0.26),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.triangleAlert300,
                  size: 16,
                  color: grid.AppPalette.warn,
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    'Could not load your grids',
                    style: TextStyle(
                      color: grid.AppPalette.textPrimary,
                      fontSize: 12.5,
                      fontWeight: grid.AppFont.semibold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(
                color: grid.AppPalette.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('grid-retry-button'),
                onPressed: onRetry,
                child: const Text(
                  'Try again',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
