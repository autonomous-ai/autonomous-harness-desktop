import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../grid/grid_overview_controller.dart';
import '../../grid/node_metrics.dart';
import '../../shared/theme/app_theme.dart' as grid;
import '../../grid/grid_overview.dart';
import '../../grid/grid_power.dart';
import '../../shared/widgets/skeleton.dart';
import 'grid_models_panel.dart';
import 'grid_power_panel.dart';
import 'grid_stat_panels.dart';
import 'memory_ring.dart';

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

/// Which of the rail's panels is open.
///
/// [power] is the whole left cluster — the grid's name, its live dot and its
/// memory ring — because all three are facts about the grid itself. The other
/// four name the thing their own figure counts.
enum _PanelKind { power, tokens, members, nodes, models }

/// What a panel hangs from: the link that places it under its figure, and the
/// key that says where that figure sits. Both, because the link alone cannot
/// answer whether the panel it places still fits inside the window — see
/// [GridStatPanel.anchorKey].
typedef _FigureAnchor = ({LayerLink link, GlobalKey key});

_FigureAnchor _newFigureAnchor() => (link: LayerLink(), key: GlobalKey());

/// The figures, read from both ends: what this grid *is* on the left, what it
/// is *made of* on the right.
class _Readout extends StatefulWidget {
  const _Readout({required this.controller});

  final GridOverviewController controller;

  @override
  State<_Readout> createState() => _ReadoutState();
}

class _ReadoutState extends State<_Readout> {
  /// One anchor per figure, so a panel hangs under the number it explains
  /// rather than under the row as a whole. A [LayerLink] can only be attached
  /// to one target, hence one each.
  final _nameAnchor = _newFigureAnchor();
  final _tokenAnchor = _newFigureAnchor();
  final _memberAnchor = _newFigureAnchor();
  final _nodeAnchor = _newFigureAnchor();
  final _modelAnchor = _newFigureAnchor();
  final _portal = OverlayPortalController();

  /// Ties the rail and its panel into one tap region, so a click inside either
  /// is not the "click outside" that dismisses a pinned panel.
  final _tapGroup = Object();

  /// What the pointer is over right now, or null when it is over none of it.
  ///
  /// Moving between two figures sets this to the new one *before* the old one's
  /// delayed close runs, which is what lets the panel swap in place instead of
  /// blinking shut and reopening. It is also what carries the pointer across
  /// the gap between a figure and the panel above it: the panel sets this to
  /// the kind it is showing, so leaving the figure finds it already claimed.
  _PanelKind? _hovered;

  /// What the panel is currently showing.
  _PanelKind _panel = _PanelKind.power;

  /// Held open by a click, rather than by the pointer resting on the rail.
  ///
  /// Hover alone cannot carry an action: reaching for a link in the panel means
  /// crossing whatever the pointer passes on the way, and a panel that closes
  /// mid-reach makes its own call to action unpressable. A pinned panel closes
  /// on a second click, or on a click anywhere outside it.
  bool _pinned = false;

  void _show() => _portal.show();

  void _hide() {
    _pinned = false;
    if (_portal.isShowing) _portal.hide();
  }

  /// The pointer settled on [kind] — a figure, or the open panel itself.
  ///
  /// With a panel already open the swap is immediate: the pointer has crossed
  /// from one figure to the next inside a surface it never left, and re-serving
  /// the wait there would make the rail feel like it had to be re-asked. The
  /// wait is for *opening*, so a pointer crossing the rail on its way elsewhere
  /// does not flash a panel open behind it.
  void _onEnter(_PanelKind kind) {
    _hovered = kind;
    if (_portal.isShowing) {
      if (_panel != kind) setState(() => _panel = kind);
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (!mounted || _hovered != kind) return;
      setState(() => _panel = kind);
      _show();
    });
  }

  /// The pointer left [kind]. Closes only if it has not landed on another part
  /// of the rail or on the panel — the guard is the *current* hover, not this
  /// one, so figure-to-figure and figure-to-panel both survive the gap.
  void _onExit(_PanelKind kind) {
    if (_hovered == kind) _hovered = null;
    // A beat of grace so the pointer can cross the gap between the rail and the
    // panel without the panel closing out from under it.
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted || _hovered != null || _pinned) return;
      _hide();
    });
  }

  /// A click pins whatever the pointer is on, so the panel can be read — and
  /// its links reached — without the pointer having to stay put.
  void _toggle() {
    if (_pinned) {
      _hide();
      return;
    }
    _pinned = true;
    setState(() => _panel = _hovered ?? _PanelKind.power);
    _show();
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final controller = widget.controller;
    if (!controller.hasGrid) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'No grid chosen',
          style: TextStyle(color: grid.AppPalette.textFaint, fontSize: 11.5),
        ),
      );
    }
    return TapRegion(
      groupId: _tapGroup,
      onTapOutside: (_) {
        if (_pinned) _hide();
      },
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => _panelFor(_panel),
        child: GestureDetector(
          // Defer, not opaque: opaque would swallow the spacer between the two
          // clusters, and a click on empty rail would pin the hardware panel.
          behavior: HitTestBehavior.deferToChild,
          onTap: _toggle,
          child: _figures(),
        ),
      ),
    );
  }

  List<OverviewNode> get _onlineNodes => [
    for (final node in widget.controller.overview?.nodes ??
        const <OverviewNode>[])
      if (node.online) node,
  ];

  Widget _figures() {
    final controller = widget.controller;
    final power = controller.power;
    final answered = power?.answered;
    // The first answer for this grid is still on its way. Every figure that
    // is about to appear is drawn blank at its final size, so the strip does
    // not assemble itself one number at a time — and only then: once a
    // reading exists it stays on screen through every refresh (see [stale]).
    final pending = power == null && controller.loading;
    return Row(
      children: [
        _GridMark(
          controller: controller,
          anchor: _nameAnchor,
          onEnter: _onEnter,
          onExit: _onExit,
        ),
        if (pending)
          const _FigureSkeleton(key: Key('rail-work-skeleton'), width: 58),
        if (power != null && answered != null && answered.freshInputTokens > 0)
          _Figure(
            anchor: _tokenAnchor,
            kind: _PanelKind.tokens,
            value: formatCount(answered.freshInputTokens),
            unit: answeredWindowLabel(answered.windowSeconds),
            semantics: 'work answered',
            onEnter: _onEnter,
            onExit: _onExit,
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
            anchor: _memberAnchor,
            kind: _PanelKind.members,
            icon: LucideIcons.users300,
            value: '${controller.members}',
            semantics: 'people on this grid',
            onEnter: _onEnter,
            onExit: _onExit,
          ),
        if (power != null)
          _Count(
            anchor: _nodeAnchor,
            kind: _PanelKind.nodes,
            icon: LucideIcons.server300,
            value: '${power.onlineNodes}',
            semantics: 'machines hosting',
            onEnter: _onEnter,
            onExit: _onExit,
          ),
        if (power != null)
          _Count(
            anchor: _modelAnchor,
            kind: _PanelKind.models,
            icon: LucideIcons.boxes,
            value: '${power.models}',
            semantics: 'models available',
            onEnter: _onEnter,
            onExit: _onExit,
          ),
      ],
    );
  }

  /// The panel [kind] asks for, anchored to the figure it belongs to.
  Widget _panelFor(_PanelKind kind) {
    final controller = widget.controller;
    final url = controller.gridUrl;
    final open = url == null ? null : () => launchUrl(Uri.parse(url));
    return switch (kind) {
      _PanelKind.power => GridPowerPanel(
        link: _nameAnchor.link,
        anchorKey: _nameAnchor.key,
        tapGroupId: _tapGroup,
        onEnter: () => _onEnter(kind),
        onExit: () => _onExit(kind),
        gridName: controller.gridName,
        power: controller.power!,
        nodes: _onlineNodes,
        uptimePct: controller.overview?.stats.uptimePct,
        onViewDashboard: open,
      ),
      _PanelKind.tokens => _stat(
        kind,
        _tokenAnchor,
        GridTokensList(answered: controller.power?.answered),
        width: 255,
      ),
      _PanelKind.members => _stat(
        kind,
        _memberAnchor,
        GridMembersList(
          gridName: controller.gridName,
          roster: controller.roster,
          usage: controller.memberUsage,
          usageLoading: controller.memberUsageLoading,
          rosterLoading: controller.rosterLoading,
          onInvite: open,
        ),
        width: 320,
      ),
      // Wider than the rest: its rows carry a spec line, and at the list width
      // those ellipsize to nothing worth reading.
      _PanelKind.nodes => _stat(
        kind,
        _nodeAnchor,
        GridNodesList(nodes: _onlineNodes),
        width: 358,
      ),
      // Each row ends in two figure columns, and at the list width they would
      // take the width out of the model id — the one string every row is read
      // for.
      _PanelKind.models => _stat(
        kind,
        _modelAnchor,
        GridModelsList(
          models: controller.overview?.models ?? const [],
          nodes: _onlineNodes,
          gridTotal: controller.power?.answered,
          loading: controller.loading,
        ),
        width: 352,
      ),
    };
  }

  Widget _stat(
    _PanelKind kind,
    _FigureAnchor anchor,
    Widget child, {
    required double width,
  }) => GridStatPanel(
    link: anchor.link,
    anchorKey: anchor.key,
    tapGroupId: _tapGroup,
    onEnter: () => _onEnter(kind),
    onExit: () => _onExit(kind),
    width: width,
    child: child,
  );
}

/// The grid's name, its live dot, and how much of its memory is spoken for.
///
/// One cluster, because all three are facts about the grid itself rather than
/// about what is running on it — and the chevron that says there is more sits
/// with them rather than at the far end of the row.
class _GridMark extends StatelessWidget {
  const _GridMark({
    required this.controller,
    required this.anchor,
    required this.onEnter,
    required this.onExit,
  });

  final GridOverviewController controller;
  final _FigureAnchor anchor;
  final void Function(_PanelKind) onEnter;
  final void Function(_PanelKind) onExit;

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
    return _HoverTarget(
      kind: _PanelKind.power,
      anchor: anchor,
      enabled: power != null,
      semantics: 'grid ${controller.gridName}',
      onEnter: onEnter,
      onExit: onExit,
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
    required this.anchor,
    required this.kind,
    required this.value,
    required this.unit,
    required this.semantics,
    required this.onEnter,
    required this.onExit,
  });

  final _FigureAnchor anchor;
  final _PanelKind kind;
  final String value;
  final String unit;
  final String semantics;
  final void Function(_PanelKind) onEnter;
  final void Function(_PanelKind) onExit;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return _HoverTarget(
      kind: kind,
      anchor: anchor,
      semantics: semantics,
      onEnter: onEnter,
      onExit: onExit,
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
    required this.anchor,
    required this.kind,
    required this.icon,
    required this.value,
    required this.semantics,
    required this.onEnter,
    required this.onExit,
  });

  final _FigureAnchor anchor;
  final _PanelKind kind;
  final IconData icon;
  final String value;
  final String semantics;
  final void Function(_PanelKind) onEnter;
  final void Function(_PanelKind) onExit;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return _HoverTarget(
      kind: kind,
      anchor: anchor,
      semantics: '$value $semantics',
      onEnter: onEnter,
      onExit: onExit,
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

/// One figure on the rail, and the panel it opens.
///
/// The regions touch: the gap between figures is each figure's own padding
/// rather than a spacer between them. A bare `SizedBox` would be dead ground —
/// the pointer crossing it belongs to nothing, so an open panel would close on
/// the way past and reopen on landing.
class _HoverTarget extends StatelessWidget {
  const _HoverTarget({
    required this.kind,
    required this.anchor,
    required this.semantics,
    required this.child,
    required this.onEnter,
    required this.onExit,
    this.enabled = true,
  });

  final _PanelKind kind;
  final _FigureAnchor anchor;
  final String semantics;
  final Widget child;
  final void Function(_PanelKind) onEnter;
  final void Function(_PanelKind) onExit;

  /// False while there is nothing to open — the figure is then still readable
  /// and simply inert.
  final bool enabled;

  /// Half the space between two figures. Each side owns its own half, so the
  /// two regions meet with nothing between them.
  static const double _gap = 9;

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: anchor.link,
      child: KeyedSubtree(
        key: anchor.key,
        child: Semantics(
          label: semantics,
          child: MouseRegion(
            cursor: enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onEnter: enabled ? (_) => onEnter(kind) : null,
            onExit: enabled ? (_) => onExit(kind) : null,
            child: Padding(
              // Full height, so the pointer entering the rail anywhere over a
              // figure is already on it — a region inset from the strip's own
              // edges leaves a lane above and below that closes the panel.
              padding: const EdgeInsets.symmetric(horizontal: _gap),
              child: Center(child: child),
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
