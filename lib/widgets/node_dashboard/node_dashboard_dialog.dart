import 'package:flutter/material.dart';

import '../../grid/grid_overview_controller.dart';
import '../../grid/node_dashboard_view.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_icon_button.dart';
import 'node_dashboard_body.dart';

/// Opens the node dashboard in a dialog — every machine on this grid with its
/// live readings, in a box over whatever the person was doing.
///
/// **The status rail no longer comes here.** Its "View dashboard" link opens
/// `showNodeDashboardScreen` instead: a grid of cards outgrew a 1180×860 box,
/// and a dashboard is a place you go to read rather than a question you dismiss.
/// This stays for callers that genuinely want a dismissable box over the shell,
/// and it draws the identical [NodeDashboardBody] the screen does — so the two
/// surfaces cannot drift into two dashboards that disagree.
Future<void> showNodeDashboard(
  BuildContext context, {
  required GridOverviewController controller,
  NodeDashboardViewStore? store,
  VoidCallback? onShareIntelligence,
  VoidCallback? onInvite,
}) => showAppDialog<void>(
  context: context,
  builder: (_) => NodeDashboardDialog(
    controller: controller,
    store: store ?? nodeDashboardViewStore,
    onShareIntelligence: onShareIntelligence,
    onInvite: onInvite,
  ),
);

/// The dashboard in a box, refreshed by the same overview poll the status rail
/// reads, so opening this never starts a second timer or a second source of
/// truth.
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
    final nodes = onlineDashboardNodes(controller);
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
              const SizedBox(height: 12),
              Flexible(
                child: NodeDashboardBody(
                  controller: controller,
                  store: store,
                  onShareIntelligence: onShareIntelligence,
                  onInvite: onInvite,
                  // Pop before the offer pushes Settings — pushing first and
                  // popping after would pop the thing just pushed.
                  onLeaveSurface: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
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
