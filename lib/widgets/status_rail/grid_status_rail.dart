import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../grid/grid_overview_controller.dart';
import '../../grid/node_metrics.dart';
import '../../shared/theme/app_theme.dart' as grid;
import '../../grid/grid_overview.dart';
import '../../grid/grid_power.dart';
import 'grid_models_panel.dart';
import 'grid_power_panel.dart';
import 'grid_stat_panels.dart';
import 'memory_ring.dart';
import 'pill_panel_shell.dart';

/// The strip along the bottom of the window: what the chosen grid is made of,
/// and which build of the app is reading it.
///
/// It exists because the top of the window is where the things you *press*
/// live — the rail, the panes, the menus — and none of these figures is a call
/// to action. **The top is what you press, the bottom is what you know.**
///
/// Full-bleed, under the machine rail as well as the panes, so the window
/// closes on one unbroken line. A strip that started after the rail would put a
/// step in the bottom edge and read as part of the pane rather than the window.
class GridStatusRail extends StatefulWidget {
  const GridStatusRail({super.key, this.controller});

  /// Injected by tests. Null in the app, where the rail makes — and disposes —
  /// its own.
  final GridOverviewController? controller;

  /// Tall enough for an 11.5pt figure with a hit target around it, short enough
  /// to stay furniture.
  static const double height = 26;

  @override
  State<GridStatusRail> createState() => _GridStatusRailState();
}

class _GridStatusRailState extends State<GridStatusRail> {
  late final GridOverviewController _controller =
      widget.controller ?? GridOverviewController();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        // The rail's own fill, matching the machine rail it runs under — both
        // are window furniture, and a third tone here would read as a third
        // pane.
        color: grid.AppGlass.sidebarFill,
        border: Border(top: BorderSide(color: grid.AppPalette.divider)),
      ),
      child: SizedBox(
        height: GridStatusRail.height,
        child: Padding(
          // Less on the right: the version mark carries its own hover inset, so
          // 10 there lands on the same optical margin as 12 on the left.
          padding: const EdgeInsets.only(left: 12, right: 10),
          child: Row(
            children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => _Readout(controller: _controller),
                ),
              ),
              const _VersionMark(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The figures, read from both ends: what this grid *is* on the left, what it
/// is *made of* on the right.
class _Readout extends StatelessWidget {
  const _Readout({required this.controller});

  final GridOverviewController controller;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    if (!controller.hasGrid) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'No grid chosen',
          style: TextStyle(
            color: grid.AppPalette.textFaint,
            fontSize: 11.5,
          ),
        ),
      );
    }
    final power = controller.power;
    final overview = controller.overview;
    final answered = power?.answered;
    // Online only, once, so every panel and the rail's own count read the same
    // set of machines.
    final onlineNodes = [
      for (final node in overview?.nodes ?? const <OverviewNode>[])
        if (node.online) node,
    ];
    return Row(
      children: [
        _GridMark(controller: controller),
        if (power != null && answered != null && answered.freshInputTokens > 0)
          _Figure(
            value: formatCount(answered.freshInputTokens),
            unit: answeredWindowLabel(answered.windowSeconds),
            semantics: 'work answered',
            panel: () => _Panel(
              width: 255,
              child: GridTokensList(answered: answered),
            ),
          ),
        const Spacer(),
        // WHAT THE GRID IS MADE OF — people, machines, models.
        if (controller.members != null)
          _Count(
            icon: LucideIcons.users300,
            value: '${controller.members}',
            semantics: 'people on this grid',
            panel: () => _Panel(
              width: 320,
              child: GridMembersList(
                gridName: controller.gridName,
                roster: controller.roster,
                usage: controller.memberUsage,
                usageLoading: controller.memberUsageLoading,
                rosterLoading: controller.rosterLoading,
                onInvite: controller.gridUrl == null
                    ? null
                    : () => launchUrl(Uri.parse(controller.gridUrl!)),
              ),
            ),
          ),
        if (power != null)
          _Count(
            icon: LucideIcons.server300,
            value: '${power.onlineNodes}',
            semantics: 'machines hosting',
            panel: () => _Panel(
              width: 358,
              child: GridNodesList(nodes: onlineNodes),
            ),
          ),
        if (power != null)
          _Count(
            icon: LucideIcons.boxes,
            value: '${power.models}',
            semantics: 'models available',
            panel: () => _Panel(
              width: 352,
              child: GridModelsList(
                models: overview?.models ?? const [],
                nodes: onlineNodes,
                gridTotal: power.answered,
                loading: controller.loading,
              ),
            ),
          ),
      ],
    );
  }
}

/// The grid's name, its live dot, and how much of its memory is spoken for.
///
/// One cluster, because all three are facts about the grid itself rather than
/// about what is running on it — and the chevron that says there is more sits
/// with them rather than at the far end of the row.
class _GridMark extends StatelessWidget {
  const _GridMark({required this.controller});

  final GridOverviewController controller;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final power = controller.power;
    final vram = power?.vramGb;
    final used = power?.vramUsedGb;
    // What the ring is a share of, in the order the data allows. Memory in use
    // is the honest first choice — it is the figure printed right beside it, so
    // the ring and the text are the same claim. Failing that, mean GPU load.
    // Failing both, no ring: an empty circle beside a total would imply a
    // measurement of zero.
    final share = (vram != null && used != null && vram > 0)
        ? used / vram
        : (power?.gpuUtilPct != null ? power!.gpuUtilPct! / 100 : null);
    return _Hoverable(
      semantics: 'grid ${controller.gridName}',
      panel: power == null
          ? null
          : () => GridPowerPanel(
              gridName: controller.gridName,
              power: power,
              nodes: [
                for (final node in controller.overview?.nodes ?? const [])
                  if (node.online) node,
              ],
              uptimePct: controller.overview?.stats.uptimePct,
              onViewDashboard: controller.gridUrl == null
                  ? null
                  : () => launchUrl(Uri.parse(controller.gridUrl!)),
            ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              // Stale is its own state and gets its own colour: the figures on
              // screen are real, they are just not from a moment ago.
              color: controller.stale
                  ? grid.AppPalette.warn
                  : grid.AppPalette.online,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              controller.gridName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                // The only full-strength text on the rail, so everything else
                // reads as its supporting detail.
                color: grid.AppPalette.textPrimary,
                fontSize: 11.5,
                fontWeight: grid.AppFont.medium,
              ),
            ),
          ),
          if (share != null) ...[
            const SizedBox(width: 9),
            MemoryRing(share: share),
            const SizedBox(width: 6),
            Text(
              vram != null && used != null
                  ? formatVramShare(used, vram)
                  : '${(share * 100).round()}% load',
              style: TextStyle(
                color: grid.AppPalette.textSecondary,
                fontSize: 11.5,
              ),
            ),
          ],
          if (power != null) ...[
            const SizedBox(width: 4),
            Icon(
              LucideIcons.chevronUp300,
              size: 12,
              color: grid.AppPalette.textFaint,
            ),
          ],
        ],
      ),
    );
  }
}

/// A figure with its unit: `92.4M / 24h`.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.unit,
    required this.semantics,
    required this.panel,
  });

  final String value;
  final String unit;
  final String semantics;
  final Widget Function() panel;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return _Hoverable(
      semantics: semantics,
      panel: panel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: grid.AppPalette.textSecondary,
              fontSize: 11.5,
              fontWeight: grid.AppFont.medium,
            ),
          ),
          if (unit.isNotEmpty)
            Text(
              ' / $unit',
              style: TextStyle(
                color: grid.AppPalette.textFaint,
                fontSize: 11.5,
              ),
            ),
        ],
      ),
    );
  }
}

/// A glyph and a count.
class _Count extends StatelessWidget {
  const _Count({
    required this.icon,
    required this.value,
    required this.semantics,
    required this.panel,
  });

  final IconData icon;
  final String value;
  final String semantics;
  final Widget Function() panel;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return _Hoverable(
      semantics: '$value $semantics',
      panel: panel,
      // At the far end of the rail, so it hangs from its right edge.
      alignEnd: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: grid.AppPalette.textFaint),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              color: grid.AppPalette.textSecondary,
              fontSize: 11.5,
              fontWeight: grid.AppFont.medium,
            ),
          ),
        ],
      ),
    );
  }
}

/// One figure on the rail, with the panel it opens.
///
/// Hover opens it and a click holds it, which is the pairing a status strip
/// wants: reading is a glance, and keeping it open to compare two machines is a
/// decision. The regions touch — each figure's gap is its own padding rather
/// than a spacer between them — so the pointer never crosses dead ground that
/// would close the panel on the way past and reopen it on landing.
class _Hoverable extends StatefulWidget {
  const _Hoverable({
    required this.child,
    required this.semantics,
    required this.panel,
    this.alignEnd = false,
  });

  final Widget child;
  final String semantics;

  /// Null when there is nothing to open — the figure is then still readable and
  /// simply inert.
  final Widget Function()? panel;

  /// Hang the panel from the figure's RIGHT edge instead of its left.
  ///
  /// The counts sit at the far end of the rail, and a 300px card opening
  /// rightward from them is a card mostly off the screen.
  final bool alignEnd;

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  final _link = LayerLink();
  OverlayEntry? _entry;
  bool _pinned = false;
  bool _overFigure = false;
  bool _overPanel = false;

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _show() {
    if (_entry != null || widget.panel == null) return;
    _entry = OverlayEntry(
      builder: (context) => Positioned(
        // ⚠️ `left`/`top` MUST be given, even though the follower does the real
        // positioning. A `Positioned` with every offset null is a *non*-
        // positioned child, and the overlay lays those out with TIGHT
        // constraints — which is a panel stretched over the whole window, with
        // its own width ignored. That is exactly what this looked like before.
        left: 0,
        top: 0,
        child: CompositedTransformFollower(
          link: _link,
          // Anchored to the figure's top edge and hung from the panel's bottom:
          // it opens UPWARD, because there is nothing below a strip that sits
          // on the bottom edge of the window.
          targetAnchor: widget.alignEnd
              ? Alignment.topRight
              : Alignment.topLeft,
          followerAnchor: widget.alignEnd
              ? Alignment.bottomRight
              : Alignment.bottomLeft,
          offset: Offset(widget.alignEnd ? 10 : -10, -6),
          showWhenUnlinked: false,
          // The panel keeps itself open. Without this the pointer leaving the
          // figure to reach the panel closes the thing it was reaching for, so
          // a list of eight machines could be looked at but never scrolled.
          child: MouseRegion(
            onEnter: (_) {
              _overPanel = true;
              _sync();
            },
            onExit: (_) {
              _overPanel = false;
              _sync();
            },
            child: widget.panel!(),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  void _sync() {
    if (!mounted) return;
    if (_overFigure || _overPanel || _pinned) {
      _show();
    } else {
      _hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return CompositedTransformTarget(
      link: _link,
      child: Semantics(
        label: widget.semantics,
        child: MouseRegion(
          cursor: widget.panel == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onEnter: (_) {
            _overFigure = true;
            _sync();
          },
          onExit: (_) {
            _overFigure = false;
            _sync();
          },
          child: GestureDetector(
            onTap: widget.panel == null
                ? null
                : () {
                    _pinned = !_pinned;
                    _sync();
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Which build this is, at the end of the rail.
///
/// The quietest thing here on purpose: it answers a question nobody asks until
/// something is wrong, and then it is the first thing they are asked for.
class _VersionMark extends StatelessWidget {
  const _VersionMark();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version;
        if (version == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            'v$version',
            style: TextStyle(
              // Quiet is spent on size and weight, not ink.
              color: grid.AppPalette.textFaint,
              fontSize: 10.5,
            ),
          ),
        );
      },
    );
  }
}

/// One panel on the shared surface, at the width its contents were drawn for.
class _Panel extends StatelessWidget {
  const _Panel({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: width, child: PillPanelSurface(child: child));
}
