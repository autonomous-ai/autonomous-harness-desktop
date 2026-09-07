import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../grid/grid_overview.dart';
import '../../grid/grid_overview_controller.dart';
import '../../grid/node_dashboard_layout.dart';
import '../../grid/node_dashboard_view.dart';
import '../../grid/node_display.dart' show modelCapabilities;
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/empty_state.dart';
import 'node_dashboard_card.dart';
import 'node_dashboard_toolbar.dart';

/// Everything the node dashboard *is*, with no opinion about the surface it is
/// drawn on.
///
/// Extracted when the dashboard grew a second entry point: the status rail's
/// "View dashboard" now opens a full screen ([NodeDashboardScreen]) while the
/// dialog stays for callers that want it. One body, so the two surfaces cannot
/// drift into two dashboards that disagree about what a node card says.
///
/// The surface keeps only what a surface owns — its frame, its header, its way
/// out — and hands this the same [controller] and [store] either way, so
/// opening either one never starts a second poll or a second source of truth.
class NodeDashboardBody extends StatelessWidget {
  const NodeDashboardBody({
    super.key,
    required this.controller,
    required this.store,
    this.onShareIntelligence,
    this.onInvite,
    this.onLeaveSurface,
  });

  final GridOverviewController controller;
  final NodeDashboardViewStore store;

  /// Where a grid with no machines sends someone who could add one. Null hides
  /// the offer rather than drawing a button that goes nowhere.
  final VoidCallback? onShareIntelligence;

  /// The other way a grid grows: somebody else's machine.
  final VoidCallback? onInvite;

  /// Run before an empty state's offer, to get this surface out of the way.
  ///
  /// A dialog has to pop itself before pushing Settings — pushing first and
  /// popping after would pop the thing just pushed. A screen has the same
  /// problem and the same fix, so the surface says how to leave itself rather
  /// than the body guessing which one it is on. Null means the offers fire as
  /// they are, which is what a body embedded in a pane wants.
  final VoidCallback? onLeaveSurface;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final nodes = onlineDashboardNodes(controller);
    // Two lists on purpose. The cards render [shown]; the toolbar and the header
    // are given [nodes], because a filter's own menu must keep offering what the
    // grid has rather than what is left after it — see [NodeDashboardToolbar].
    final shown = applyNodeDashboardView(nodes, store.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (nodes.isNotEmpty) ...[
          NodeDashboardToolbar(nodes: nodes, store: store),
          const SizedBox(height: 16),
        ],
        Flexible(
          child: switch ((nodes.isEmpty, shown.isEmpty)) {
            (true, _) => _EmptyState(
              onShareIntelligence: onShareIntelligence,
              onInvite: onInvite,
              onLeaveSurface: onLeaveSurface,
            ),
            // Machines are serving, the filters just don't want any of them —
            // a different fact, and one with a way out.
            (false, true) => _NoMatchState(store: store),
            (false, false) => NodeDashboardGrid(
              nodes: shown,
              gridWide: modelCapabilities(
                controller.overview?.models ?? const <OverviewModel>[],
              ),
            ),
          },
        ),
      ],
    );
  }
}

/// The machines a dashboard draws: every node the relay still hears from.
///
/// Shared with the surfaces, because a header printing "8 serving" has to be
/// counting the same list the cards under it are built from.
List<OverviewNode> onlineDashboardNodes(GridOverviewController controller) => [
  for (final node in controller.overview?.nodes ?? const <OverviewNode>[])
    if (node.online) node,
];

/// The cards, laid out in rows that each take the height their tallest card
/// needs.
///
/// **Not a `GridView`, and the reason is a bug this replaced.** A grid tile has
/// to be given its height up front — `mainAxisExtent`, or an aspect ratio — and
/// any figure chosen there is a guess about content that varies per node: a
/// machine reporting three gauges, four detail fields and a throughput footer is
/// taller than one reporting a size and a sentence. The guess was 300px and the
/// fullest cards overflowed it by 22, clipping the tok/s figure off the bottom.
/// Raising the number would only move the cliff.
///
/// Rows are built lazily, so this keeps what the grid was chosen for: a dashboard
/// of many machines still builds only the rows on screen.
class NodeDashboardGrid extends StatelessWidget {
  const NodeDashboardGrid({
    super.key,
    required this.nodes,
    required this.gridWide,
  });

  final List<OverviewNode> nodes;
  final Map<String, ModelCapability> gridWide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = dashboardColumns(constraints.maxWidth);
        final rowCount = (nodes.length + columns - 1) ~/ columns;
        return ListView.builder(
          itemCount: rowCount,
          itemBuilder: (_, row) {
            final first = row * columns;
            final cards = nodes.skip(first).take(columns).toList();
            return Padding(
              padding: EdgeInsets.only(
                bottom: row == rowCount - 1 ? 0 : kNodeCardGap,
              ),
              // `IntrinsicHeight` + `stretch`: every card in a row takes the
              // height of the tallest, so their footers sit on one line and the
              // row reads as a set rather than a ragged edge. It measures its
              // children twice, which is affordable here — a row holds at most a
              // handful of cards, and only visible rows are ever built.
              //
              // Still no card declares a height of its own: the row's height is
              // whatever its content needs, which is what keeps the 22px
              // overflow from the fixed-extent grid from coming back.
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < columns; i++) ...[
                      if (i > 0) const SizedBox(width: kNodeCardGap),
                      Expanded(
                        child: i < cards.length
                            // A trailing gap in the last row is an empty cell,
                            // so the final card keeps its column width instead
                            // of stretching across the leftovers.
                            ? NodeDashboardCard(
                                node: cards[i],
                                gridWide: gridWide,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Machines are serving, but none of them answer the filters in force.
///
/// Its own state rather than the empty grid's, because the two are opposite
/// facts and only one of them is the user's to fix: an empty grid needs a
/// machine joined to it, and this needs a button pressed. Telling somebody to go
/// join a machine to a grid that already has nine is the kind of wrong advice
/// that costs an afternoon.
///
/// [EmptyState] rather than a private column, and not [EmptyState.noMatches]
/// either: that constructor is deliberately actionless because the usual fix for
/// a filter is to retype the query, and here there is a button that does it.
class _NoMatchState extends StatelessWidget {
  const _NoMatchState({required this.store});

  final NodeDashboardViewStore store;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return EmptyState(
      icon: Icons.filter_alt_off_outlined,
      title: 'No machine matches',
      message:
          'Every machine on this grid is filtered out by what you asked for.',
      action: TextButton(
        onPressed: store.clearFilters,
        child: const Text('Show all machines'),
      ),
    );
  }
}

/// A grid with nothing serving it yet.
///
/// The header keeps the fact and this keeps the next step, because a grid grows
/// in exactly two ways: this computer joins it, or somebody else's does. Both
/// are offers rather than statements — a state that only restates the line above
/// it leaves the reader with nowhere to go.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    this.onShareIntelligence,
    this.onInvite,
    this.onLeaveSurface,
  });

  final VoidCallback? onShareIntelligence;
  final VoidCallback? onInvite;
  final VoidCallback? onLeaveSurface;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    // Leave this surface only once, and before the next screen is pushed:
    // pushing first and popping after would pop the thing just pushed.
    VoidCallback? after(VoidCallback? action) {
      if (action == null) return null;
      return () {
        onLeaveSurface?.call();
        action();
      };
    }

    final share = after(onShareIntelligence);
    final invite = after(onInvite);
    return EmptyState(
      icon: LucideIcons.server300,
      title: 'Add the first machine',
      message:
          "Share this computer's models with the grid, or invite someone who "
          'can share theirs.',
      action: (share == null && invite == null)
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (share != null) ...[
                  // The screen's own name — Settings lists it under exactly
                  // this word, and one screen answers to one word.
                  FilledButton(
                    onPressed: share,
                    child: const Text('Share Intelligence'),
                  ),
                  if (invite != null) const SizedBox(width: 8),
                ],
                if (invite != null)
                  TextButton(
                    onPressed: invite,
                    child: const Text('Invite people'),
                  ),
              ],
            ),
    );
  }
}
