import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../analytics/analytics.dart';
import '../../grid/grid_overview_controller.dart';
import '../../grid/node_dashboard_layout.dart';
import '../../grid/node_dashboard_view.dart';
import '../../shared/layouts/widgets/sidebar_item.dart';
import '../../shared/theme/app_theme.dart';
import '../window_chrome.dart';
import 'node_dashboard_body.dart';

/// Opens the node dashboard as a screen — every machine on this grid with its
/// live readings, taking the whole window.
///
/// **A screen, not the dialog it replaced.** The dialog capped itself at
/// 1180×860 and then let a grid of cards fight for what was left: on a wide
/// display it drew a letterboxed pane with the shell greyed out behind it, and
/// a grid of a dozen machines scrolled inside a box inside a window. A
/// dashboard is a place you go to read, not a question you answer and dismiss,
/// so it gets the room Settings gets — same route, same cross-fade, same way
/// back.
///
/// Pushed as a route rather than switched into the shell, exactly as
/// `showSettingsScreen` is: nothing carries a notion of "which screen", and a
/// route needs none — the way back is [Navigator.pop], and the shell underneath
/// keeps its panes attached and its terminals streaming while this is up.
Future<void> showNodeDashboardScreen(
  BuildContext context, {
  required GridOverviewController controller,
  NodeDashboardViewStore? store,
  VoidCallback? onShareIntelligence,
  VoidCallback? onInvite,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      // Opaque: it covers the window, and letting the shell show through would
      // mean compositing four live terminals under it for nothing.
      pageBuilder: (context, animation, _) => NodeDashboardScreen(
        controller: controller,
        store: store ?? nodeDashboardViewStore,
        onShareIntelligence: onShareIntelligence,
        onInvite: onInvite,
      ),
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
      // A cross-fade, not a slide — the same arrival Settings makes, because a
      // screen that slides in from the right reads as a phone pushing a detail
      // view rather than the window changing what it is showing.
      transitionDuration: const Duration(milliseconds: 170),
      reverseTransitionDuration: const Duration(milliseconds: 120),
    ),
  );
}

/// The dashboard screen: a header that says what the grid is, the filters, and
/// the cards.
class NodeDashboardScreen extends StatefulWidget {
  const NodeDashboardScreen({
    super.key,
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
  State<NodeDashboardScreen> createState() => _NodeDashboardScreenState();
}

class _NodeDashboardScreenState extends State<NodeDashboardScreen> {
  @override
  void initState() {
    super.initState();
    // A screen view now that this is a screen. `grid_dashboard_opened` still
    // fires at the call site, because the two answer different questions —
    // which entry point was used, and which screen is being read.
    analytics.screenView('grid_nodes');
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    // Both listenables, because the cards follow the 60s poll and the toolbar
    // follows the reader — and a dashboard that redrew only on one of the two
    // would either freeze its figures or ignore its own filters.
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, widget.store]),
      builder: (context, _) {
        final nodes = onlineDashboardNodes(widget.controller);
        final shown = applyNodeDashboardView(nodes, widget.store.value);
        return Scaffold(
          backgroundColor: AppPalette.windowBg,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Clearance for the macOS traffic lights, and somewhere to grab
              // the window. No fill of its own — the screen sits on the window.
              const WindowDragStrip(),
              Padding(
                padding: const EdgeInsets.fromLTRB(_gutter, 10, _gutter, 0),
                child: _ScreenHeader(
                  gridName: widget.controller.gridName,
                  total: nodes.length,
                  shown: shown.length,
                ),
              ),
              Expanded(
                child: Padding(
                  // Wider gutters than the dialog's 22: a screen's content
                  // needs a margin the window edge does not supply, and the
                  // card grid reflows to whatever is left rather than being
                  // held at a fixed width.
                  padding: const EdgeInsets.fromLTRB(
                    _gutter,
                    18,
                    _gutter,
                    _gutter,
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      // A ceiling, not a width. Cards stop growing past the
                      // point where a row of them reads as a wall of text on a
                      // 34" display; below it the grid simply fills the window.
                      // The figure is eight target-width columns, so a full
                      // fleet lays out in two rows before the cap ever bites.
                      constraints: const BoxConstraints(maxWidth: _maxContent),
                      child: NodeDashboardBody(
                        controller: widget.controller,
                        store: widget.store,
                        onShareIntelligence: widget.onShareIntelligence,
                        onInvite: widget.onInvite,
                        // The empty state's offers open Settings, which is a
                        // route like this one — so leave this screen first,
                        // or the push it makes is what gets popped.
                        onLeaveSurface: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The screen's side margin.
const double _gutter = 28;

/// Eight columns at [kNodeCardTargetWidth] plus their gaps — see the constraint
/// this is used in.
const double _maxContent =
    kNodeCardTargetWidth * 8 + kNodeCardGap * 7;

class _ScreenHeader extends StatelessWidget {
  const _ScreenHeader({
    required this.gridName,
    required this.total,
    required this.shown,
  });

  /// The grid these machines serve — the same name the status rail's panel is
  /// titled with, so arriving here from that panel lands on the thing it named.
  final String gridName;

  /// Machines serving this grid, and how many of them the filters let through.
  final int total;
  final int shown;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The way out reads as a row, not a close button: a screen is left, a
        // dialog is dismissed, and the arrow is what says which of the two this
        // is. The same [SidebarItem] Settings uses, so the two screens are left
        // by the identical control rather than by two lookalikes.
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 148,
            child: SidebarItem(
              icon: LucideIcons.arrowLeft300,
              label: 'Back to app',
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Nodes',
                    style: TextStyle(
                      // Larger than the dialog's 17: at screen scale a heading
                      // set at dialog size reads as a caption stranded in the
                      // top-left corner.
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: AppPalette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Says "serving", not "N of M online": the relay lists only
                  // nodes whose heartbeat is still live, so every card below is
                  // online by construction and a ratio would always read N of N.
                  //
                  // The ratio that *is* printed is a different one — cards shown
                  // out of machines serving — and only while a filter is on. The
                  // count has to follow what the dashboard is actually showing,
                  // or the one line naming a number contradicts the cards under
                  // it.
                  Text(
                    _subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppPalette.textFaint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// The grid's name in front of the count, when there is one: the screen has
  /// the room the dialog did not, and "autonomous.ai · 8 machines serving" is
  /// what the person clicked through from.
  String get _subtitle {
    final counts = nodeDashboardSubtitle(total, shown);
    return gridName.isEmpty ? counts : '$gridName · $counts';
  }
}
