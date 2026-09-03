import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../grid/grid_overview_controller.dart';
import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/widgets/skeleton.dart';
import 'memory_ring.dart';
import 'status_panels.dart';

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
          style: TextStyle(color: grid.AppPalette.textFaint, fontSize: 11.5),
        ),
      );
    }
    final power = controller.power;
    final overview = controller.overview;
    final answered = power?.answered;
    // The first answer for this grid is still on its way. Every figure that
    // is about to appear is drawn blank at its final size, so the strip does
    // not assemble itself one number at a time — and only then: once a
    // reading exists it stays on screen through every refresh (see [stale]).
    final pending = power == null && controller.loading;
    return Row(
      children: [
        _GridMark(controller: controller),
        if (pending)
          const _FigureSkeleton(key: Key('rail-work-skeleton'), width: 58),
        if (power != null && answered != null && answered.freshInput > 0)
          _Figure(
            value: formatTokens(answered.freshInput),
            unit: formatWindow(answered.windowSeconds),
            semantics: 'work answered',
            panel: () => WorkPanel(answered: answered),
          ),
        const Spacer(),
        // WHAT THE GRID IS MADE OF — people, machines, models.
        if (pending) ...const [
          _CountSkeleton(icon: LucideIcons.users300),
          _CountSkeleton(icon: LucideIcons.server300),
          _CountSkeleton(icon: LucideIcons.boxes),
        ],
        if (controller.members != null)
          _Count(
            icon: LucideIcons.users300,
            value: '${controller.members}',
            semantics: 'people on this grid',
            panel: () => MembersPanel(members: controller.members!),
          ),
        if (power != null)
          _Count(
            icon: LucideIcons.server300,
            value: '${power.onlineNodes}',
            semantics: 'machines hosting',
            panel: () => NodesPanel(nodes: overview?.nodes ?? const []),
          ),
        if (power != null)
          _Count(
            icon: LucideIcons.boxes,
            value: '${power.models}',
            semantics: 'models available',
            panel: () => ModelsPanel(models: overview?.models ?? const []),
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
    final share = power?.share;
    final vram = power?.vramGb;
    final used = power?.vramUsedGb;
    return _Hoverable(
      semantics: 'grid ${controller.gridName}',
      panel: power == null
          ? null
          : () => PowerPanel(power: power, gridName: controller.gridName),
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
          if (power == null && controller.loading) ...const [
            SizedBox(width: 9),
            Skeleton.circle(size: 11),
            SizedBox(width: 6),
            SkeletonText(style: TextStyle(fontSize: 11.5), width: 64),
          ],
          if (share != null) ...[
            const SizedBox(width: 9),
            MemoryRing(share: share),
            const SizedBox(width: 6),
            Text(
              vram != null && used != null
                  ? formatMemoryPair(used, vram)
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

/// The value of a [_Figure] before there is one: the same padding the live
/// figure's hover region takes, so the strip is the same width before and
/// after.
class _FigureSkeleton extends StatelessWidget {
  const _FigureSkeleton({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    child: SkeletonText(
      style: TextStyle(fontSize: 11.5, fontWeight: grid.AppFont.medium),
      width: width,
    ),
  );
}

/// A [_Count] whose number has not arrived: the real glyph, because what is
/// being counted is known, and a blank where the count goes.
class _CountSkeleton extends StatelessWidget {
  const _CountSkeleton({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: grid.AppPalette.textFaint),
          const SizedBox(width: 5),
          SkeletonText(
            style: TextStyle(fontSize: 11.5, fontWeight: grid.AppFont.medium),
            width: 16,
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
  });

  final Widget child;
  final String semantics;

  /// Null when there is nothing to open — the figure is then still readable and
  /// simply inert.
  final Widget Function()? panel;

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  final _link = LayerLink();
  OverlayEntry? _entry;
  bool _pinned = false;
  bool _hovering = false;

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  void _show() {
    if (_entry != null || widget.panel == null) return;
    _entry = OverlayEntry(
      builder: (context) => Positioned(
        child: CompositedTransformFollower(
          link: _link,
          // Anchored to the figure's top-left and lifted by the panel's own
          // height — it opens UPWARD, because there is nothing below a strip on
          // the bottom edge of the window.
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          offset: const Offset(-10, -8),
          child: widget.panel!(),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  void _sync() {
    if (_hovering || _pinned) {
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
            _hovering = true;
            _sync();
          },
          onExit: (_) {
            _hovering = false;
            _sync();
          },
          child: GestureDetector(
            onTap: widget.panel == null
                ? null
                : () => setState(() {
                    _pinned = !_pinned;
                    _sync();
                  }),
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
class _VersionMark extends StatefulWidget {
  const _VersionMark();

  @override
  State<_VersionMark> createState() => _VersionMarkState();
}

class _VersionMarkState extends State<_VersionMark> {
  // Read once per mount, not once per rebuild: the rail rebuilds on every
  // refresh, and a future built in `build` would put the placeholder back for
  // a frame each time. Not a static either — a future outlives the zone it
  // was made in, and its callbacks are delivered to that zone, which is a
  // problem the moment two tests share a process.
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    const style = TextStyle(fontSize: 10.5);
    return FutureBuilder<PackageInfo>(
      future: _info,
      builder: (context, snapshot) {
        final version = snapshot.data?.version;
        // Answered with nothing (a bundle with no version, a plugin that is
        // not there): say nothing, as before. A skeleton is a promise that
        // something is coming, and here nothing is.
        if (version == null &&
            snapshot.connectionState == ConnectionState.done) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: version == null
              // Blank at the width of a version string, so the figures to
              // its left do not shift right when it lands.
              ? const SkeletonText(style: style, width: 34)
              : Text(
                  'v$version',
                  style: style.copyWith(
                    // Quiet is spent on size and weight, not ink.
                    color: grid.AppPalette.textFaint,
                  ),
                ),
        );
      },
    );
  }
}
