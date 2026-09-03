import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../grid/grid_overview.dart';
import '../../grid/grid_overview_controller.dart';
import '../../grid/node_dashboard_layout.dart';
import '../../grid/node_dashboard_view.dart';
import '../../grid/node_display.dart' show modelCapabilities;
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_icon_button.dart';
import '../../shared/widgets/empty_state.dart';
import 'node_dashboard_card.dart';
import 'node_dashboard_toolbar.dart';

/// Opens the node dashboard — every machine on this grid with its live readings.
///
/// A dialog rather than a Settings section on purpose: the entry point is the
/// status rail, which is on screen from every part of the app, and a screen
/// would have meant leaving whatever the person was doing to look at a gauge.
Future<void> showNodeDashboard(
  BuildContext context, {
  required GridOverviewController controller,
  NodeDashboardViewStore? store,
  VoidCallback? onShareIntelligence,
  VoidCallback? onInvite,
}) => showDialog<void>(
  context: context,
  // The same scrim the app's other full dialogs dim behind, rather than
  // Material's heavier default.
  barrierColor: const Color(0x66000000),
  builder: (_) => NodeDashboardDialog(
    controller: controller,
    store: store ?? nodeDashboardViewStore,
    onShareIntelligence: onShareIntelligence,
    onInvite: onInvite,
  ),
);

/// The dashboard surface: one [NodeDashboardCard] per node, refreshed by the
/// same overview poll the status rail reads, so opening this never starts a
/// second timer or a second source of truth.
///
/// Ported from Grid (`features/network/presentation/node_dashboard_dialog.dart`),
/// with Riverpod swapped for the controller and store handed in.
class NodeDashboardDialog extends StatelessWidget {
  const NodeDashboardDialog({
    super.key,
    required this.controller,
    required this.store,
    this.onShareIntelligence,
    this.onInvite,
  });

  final GridOverviewController controller;
  final NodeDashboardViewStore store;

  /// Where a grid with no machines sends someone who could add one. Null hides
  /// the offer rather than drawing a button that goes nowhere.
  final VoidCallback? onShareIntelligence;

  /// The other way a grid grows: somebody else's machine.
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    // Both listenables, because the cards follow the 60s poll and the toolbar
    // follows the reader — and a dashboard that redrew only on one of the two
    // would either freeze its figures or ignore its own filters.
    return ListenableBuilder(
      listenable: Listenable.merge([controller, store]),
      builder: (context, _) => _Surface(
        controller: controller,
        store: store,
        onShareIntelligence: onShareIntelligence,
        onInvite: onInvite,
      ),
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({
    required this.controller,
    required this.store,
    this.onShareIntelligence,
    this.onInvite,
  });

  final GridOverviewController controller;
  final NodeDashboardViewStore store;
  final VoidCallback? onShareIntelligence;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    final nodes = [
      for (final node in controller.overview?.nodes ?? const <OverviewNode>[])
        if (node.online) node,
    ];
    // Two lists on purpose. The cards render [shown]; the toolbar and the header
    // are given [nodes], because a filter's own menu must keep offering what the
    // grid has rather than what is left after it — see [NodeDashboardToolbar].
    final shown = applyNodeDashboardView(nodes, store.value);
    return Dialog(
      backgroundColor: AppPalette.windowBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppCard.radius),
        side: BorderSide(color: AppCard.hair),
      ),
      child: ConstrainedBox(
        // A grid of cards wants the room; a sentence and two buttons do not.
        // Holding 1180 for an empty grid drew a near-empty pane the width of the
        // window, which reads as a dashboard that failed to load rather than as
        // a grid with nothing on it yet.
        constraints: BoxConstraints(
          maxWidth: nodes.isEmpty ? 460 : 1180,
          maxHeight: 860,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogHeader(total: nodes.length, shown: shown.length),
              if (nodes.isNotEmpty) ...[
                const SizedBox(height: 12),
                NodeDashboardToolbar(nodes: nodes, store: store),
              ],
              const SizedBox(height: 16),
              Flexible(
                child: switch ((nodes.isEmpty, shown.isEmpty)) {
                  (true, _) => _EmptyState(
                    onShareIntelligence: onShareIntelligence,
                    onInvite: onInvite,
                  ),
                  // Machines are serving, the filters just don't want any of
                  // them — a different fact, and one with a way out.
                  (false, true) => _NoMatchState(store: store),
                  (false, false) => _NodeGrid(
                    nodes: shown,
                    gridWide: modelCapabilities(
                      controller.overview?.models ?? const <OverviewModel>[],
                    ),
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
class _NodeGrid extends StatelessWidget {
  const _NodeGrid({required this.nodes, required this.gridWide});

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

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.total, required this.shown});

  /// Machines serving this grid, and how many of them the filters let through.
  final int total;
  final int shown;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Nodes',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              // Says "serving", not "N of M online": the relay lists only nodes
              // whose heartbeat is still live, so every card below is online by
              // construction and a ratio would always read N of N.
              //
              // The ratio that *is* printed is a different one — cards shown out
              // of machines serving — and only while a filter is on. The count
              // has to follow what the dashboard is actually showing, or the one
              // line naming a number contradicts the cards under it.
              Text(
                nodeDashboardSubtitle(total, shown),
                style: TextStyle(fontSize: 12, color: AppPalette.textFaint),
              ),
            ],
          ),
        ),
        // [AppIconButton], not a bare [IconButton]: the raw one keeps Material's
        // 48px tap padding and its own hover grey, so it would sit further from
        // the dialog's edge than every other close in the app and light
        // differently on hover.
        AppIconButton(
          icon: Icons.close,
          size: 18,
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
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
  const _EmptyState({this.onShareIntelligence, this.onInvite});

  final VoidCallback? onShareIntelligence;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    // Push the next screen only once this dialog is gone: pushing first and
    // popping after would pop the thing just pushed.
    VoidCallback? after(VoidCallback? action) {
      if (action == null) return null;
      return () {
        Navigator.of(context).pop();
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
