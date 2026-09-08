import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../analytics/analytics.dart';
import '../../grid/grid_overview_controller.dart';
import '../../grid/grid_surface.dart';
import '../../grid/node_metrics.dart';
import '../../grid/plural.dart';
import '../../shared/theme/app_theme.dart' as grid;
import '../../grid/grid_overview.dart';
import '../../grid/grid_power.dart';
import '../../shared/widgets/skeleton.dart';
import '../../usage/usage_controller.dart';
import '../../usage/usage_window.dart';
import '../node_dashboard/node_dashboard_screen.dart';
import '../share_grid/share_grid_dialog.dart';
import 'grid_models_panel.dart';
import 'grid_power_panel.dart';
import 'grid_stat_panels.dart';
import 'memory_ring.dart';
import 'rail_figure.dart';
import 'usage_readout.dart';
import 'usage_panel.dart';

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
  const GridStatusRail({
    super.key,
    this.controller,
    this.usage,
    this.onShareIntelligence,
  });

  /// Injected by tests. Null in the app, where the rail makes — and disposes —
  /// its own.
  final GridOverviewController? controller;

  /// The agent accounts' rate limits. Injected by tests; null in the app, where
  /// the rail makes — and disposes — its own.
  final UsageController? usage;

  /// Opens Settings ▸ Share Intelligence — the other way a grid with no
  /// machines on it grows one. Handed down from the shell, which is where the
  /// `AppNotifier` that Settings needs actually lives; null simply drops the
  /// offer rather than drawing a button that goes nowhere.
  final VoidCallback? onShareIntelligence;

  /// Tall enough for an 11.5pt figure with a hit target around it, short enough
  /// to stay furniture.
  static const double height = 26;

  @override
  State<GridStatusRail> createState() => _GridStatusRailState();
}

class _GridStatusRailState extends State<GridStatusRail> {
  late final GridOverviewController _controller =
      widget.controller ?? GridOverviewController();

  /// Unlike the grid controller, this one is created in every build flavour:
  /// a rate limit belongs to an account, so the figures are as true in a build
  /// that hides Grid as in one that shows it.
  late final UsageController _usage = widget.usage ?? UsageController();

  @override
  void dispose() {
    // `_controller` is `late`: in a build that hides Grid the readout below is
    // never drawn, so it was never created — and reaching for it here to
    // dispose it is what would create it, listener on the selection store and
    // all.
    if (widget.controller == null && kGridSurfaceEnabled) _controller.dispose();
    if (widget.usage == null) _usage.dispose();
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
              // The left of this strip answers whichever question this build
              // can. With a grid chosen it is the grid's figures; with none —
              // or in a build that hides Grid altogether — it is what the agent
              // accounts on this machine have spent, which is true either way
              // because a rate limit belongs to an account rather than a grid.
              // It used to read "No grid chosen", a sentence that tells someone
              // what they already know and hands a riddle to anyone who cannot
              // pick one.
              Expanded(
                child: ListenableBuilder(
                  // `_controller` is `late` and must stay untouched in a build
                  // that hides Grid — see [dispose]. The `if` guards the read,
                  // not just the listening.
                  listenable: Listenable.merge([
                    if (kGridSurfaceEnabled) _controller,
                    _usage,
                  ]),
                  builder: (context, _) => _Readout(
                    controller: kGridSurfaceEnabled ? _controller : null,
                    usage: _usage,
                    onShareIntelligence: widget.onShareIntelligence,
                  ),
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
/// memory ring — because all three are facts about the grid itself. The next
/// four name the thing their own figure counts.
///
/// [usageClaude] and [usageCodex] belong to the other readout entirely: one
/// kind per account rather than a single `usage` carrying a provider beside it,
/// because everything here is keyed on this enum alone and a kind that needed a
/// companion field would be a kind that could be hovered without it.
enum _PanelKind {
  power,
  tokens,
  members,
  nodes,
  models,
  usageClaude,
  usageCodex;

  /// The kind that opens [provider]'s panel.
  static _PanelKind forProvider(UsageProvider provider) => switch (provider) {
    UsageProvider.claude => usageClaude,
    UsageProvider.codex => usageCodex,
  };

  /// The account this kind belongs to, or null for the grid's own panels.
  UsageProvider? get provider => switch (this) {
    usageClaude => UsageProvider.claude,
    usageCodex => UsageProvider.codex,
    _ => null,
  };
}

/// The figures, read from both ends: what this grid *is* on the left, what it
/// is *made of* on the right — or, with no grid, what the agent accounts on
/// this machine have spent.
class _Readout extends StatefulWidget {
  const _Readout({
    required this.controller,
    required this.usage,
    this.onShareIntelligence,
  });

  /// The chosen grid's figures, or null in a build that hides Grid entirely.
  final GridOverviewController? controller;

  final UsageController usage;

  /// See [GridStatusRail.onShareIntelligence].
  final VoidCallback? onShareIntelligence;

  @override
  State<_Readout> createState() => _ReadoutState();
}

class _ReadoutState extends State<_Readout> {
  /// One anchor per figure, so a panel hangs under the number it explains
  /// rather than under the row as a whole. A [LayerLink] can only be attached
  /// to one target, hence one each.
  final _nameAnchor = newRailFigureAnchor();
  final _tokenAnchor = newRailFigureAnchor();
  final _memberAnchor = newRailFigureAnchor();
  final _nodeAnchor = newRailFigureAnchor();
  final _modelAnchor = newRailFigureAnchor();

  /// One per account, made up front rather than per build: an anchor rebuilt
  /// mid-hover would hand the open panel a [LayerLink] its target no longer
  /// holds, and the panel would jump to the window's origin.
  final Map<UsageProvider, RailFigureAnchor> _usageAnchors = {
    for (final provider in UsageProvider.values)
      provider: newRailFigureAnchor(),
  };
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
  ///
  /// `late`, because which panel is even *available* depends on whether a grid
  /// is chosen, and a field initialiser cannot ask.
  late _PanelKind _panel = _defaultKind;

  /// The grid's figures, or null when there is no grid to describe — either
  /// because none is chosen or because this build hides Grid altogether. The
  /// rail then reads the agent accounts instead.
  GridOverviewController? get _grid {
    final controller = widget.controller;
    return controller != null && controller.hasGrid ? controller : null;
  }

  /// What a click on empty rail opens: the grid's own panel when there is a
  /// grid, and otherwise the first account with figures to show.
  _PanelKind get _defaultKind {
    if (_grid != null) return _PanelKind.power;
    final first = widget.usage.answered.firstOrNull;
    return first == null
        ? _PanelKind.power
        : _PanelKind.forProvider(first.provider);
  }

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
    setState(() => _panel = _hovered ?? _defaultKind);
    _show();
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // Nothing to describe and nothing to report: no grid, and no account
    // signed in here either. The strip keeps its version mark and says
    // nothing else, rather than drawing a figure-shaped blank that will
    // never fill.
    if (_grid == null &&
        !widget.usage.loading &&
        widget.usage.answered.isEmpty) {
      return const SizedBox.shrink();
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
    for (final node in _grid?.overview?.nodes ?? const <OverviewNode>[])
      if (node.online) node,
  ];

  Widget _figures() {
    final controller = _grid;
    // No grid to describe: the strip reads the agent accounts instead. These
    // are the same figures either way — a rate limit is the account's, not the
    // grid's — so this is a substitution, not a fallback.
    if (controller == null) {
      return UsageReadout<_PanelKind>(
        readings: widget.usage.readings,
        loading: widget.usage.loading,
        anchorFor: (provider) => _usageAnchors[provider]!,
        kindFor: _PanelKind.forProvider,
        onEnter: _onEnter,
        onExit: _onExit,
      );
    }
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
          // Measured against what lands here — `92.4M tokens / 24h`, not the
          // bare `92.4M / 24h` this stood in for before the figure was given
          // its noun. A placeholder narrower than its answer is the jump a
          // skeleton exists to prevent.
          const _FigureSkeleton(key: Key('rail-work-skeleton'), width: 104),
        if (power != null && answered != null && answered.freshInputTokens > 0)
          // Flexible, so the one figure on this strip that carries words gives
          // them up before the row overflows. The rail is a plain Row over the
          // window's full width: past the Spacer there is no slack left, and a
          // narrow window is what turns the naming of this figure into a
          // yellow-and-black bar along the bottom edge.
          Flexible(
            child: _Figure(
              anchor: _tokenAnchor,
              kind: _PanelKind.tokens,
              value: formatCount(answered.freshInputTokens),
              // Pluralised off the raw count, not off what `formatCount` printed:
              // past a thousand that prints "1.2M" and the noun beside it is
              // still plural, and only the count itself knows that.
              noun: plural(answered.freshInputTokens, 'token'),
              unit: answeredWindowLabel(answered.windowSeconds),
              semantics: 'work answered',
              onEnter: _onEnter,
              onExit: _onExit,
            ),
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

  /// Opens the node dashboard, having got the panel out of the way first.
  ///
  /// Dismiss and push in that order, and `this.context` rather than the panel's:
  /// the callback runs from inside an [OverlayPortal] child, and hiding it
  /// unmounts the very element the route would be pushed from.
  ///
  /// A screen rather than the dialog this used to open: the panel is a glance,
  /// and what it links to is the place you go when a glance was not enough — so
  /// it takes the window, the way Settings does, instead of a box over a
  /// greyed-out shell.
  void _openNodes() {
    // Only ever reached from a grid panel, which cannot be open without one.
    final controller = _grid;
    if (controller == null) return;
    _hide();
    analytics.gridDashboardOpened(
      networkId: controller.networkId,
      nodes: controller.overview?.nodes.length,
    );
    showNodeDashboardScreen(
      context,
      controller: controller,
      onShareIntelligence: widget.onShareIntelligence,
      // The dashboard's empty state offers the other way to fill a grid, and
      // reaches it through the same sheet the members panel does.
      onInvite: controller.networkId == null ? null : _openShare,
    );
  }

  void _openShare() {
    final controller = _grid;
    final id = controller?.networkId;
    if (controller == null || id == null) return;
    _hide();
    analytics.gridShareOpened(networkId: id, members: controller.members);
    showShareGridDialog(
      context,
      networkId: id,
      gridName: controller.gridName,
      // An invite that lands changes the figure this rail prints, so the poll
      // is asked again rather than left to come round in its own time.
      onChanged: controller.refresh,
    );
  }

  /// The panel [kind] asks for, anchored to the figure it belongs to.
  Widget _panelFor(_PanelKind kind) {
    // An account's panel, which needs no grid — and is the only kind reachable
    // when there is none.
    final provider = kind.provider;
    if (provider != null) return _usagePanel(kind, provider);
    final controller = _grid;
    // The grid panels cannot be opened without a grid, but a pinned panel
    // outlives the frame that opened it: deselecting a grid while one is up
    // arrives here with nothing to draw.
    if (controller == null) return const SizedBox.shrink();
    final onShare = controller.networkId == null ? null : _openShare;
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
        onViewDashboard: _openNodes,
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
          onInvite: onShare,
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
      // Taken by the early return above, before a grid was even asked for.
      // Named rather than left to a wildcard so a seventh kind added later
      // still has to come here and say what it draws.
      _PanelKind.usageClaude ||
      _PanelKind.usageCodex => const SizedBox.shrink(),
    };
  }

  /// One account's windows, under the figure that summarises them.
  ///
  /// Narrower than the grid's lists: every row is a label, a bar and two short
  /// figures, and the extra width would go to the bar alone — which is the one
  /// thing here that carries no reading of its own.
  Widget _usagePanel(_PanelKind kind, UsageProvider provider) {
    final reading = widget.usage.readings.firstWhere(
      (r) => r.provider == provider,
      orElse: () => ProviderUsage.loading(provider),
    );
    return _stat(
      kind,
      _usageAnchors[provider]!,
      UsagePanelContent(reading: reading),
      width: 248,
    );
  }

  Widget _stat(
    _PanelKind kind,
    RailFigureAnchor anchor,
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
  final RailFigureAnchor anchor;
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
    return RailHoverTarget<_PanelKind>(
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

/// A figure, what it counts, and over how long: `92.4M tokens / 24h`.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.anchor,
    required this.kind,
    required this.value,
    required this.noun,
    required this.unit,
    required this.semantics,
    required this.onEnter,
    required this.onExit,
  });

  final RailFigureAnchor anchor;
  final _PanelKind kind;
  final String value;

  /// What the figure counts, drawn faint beside it.
  ///
  /// On screen rather than in [semantics] alone: a bare `92.4M / 24h` at the
  /// window's edge is a number nobody can name without hovering it, and the
  /// panel that names it is a whole card — far more than the question deserves.
  /// The counts beside it are read from their glyphs; this one has none.
  final String noun;

  final String unit;
  final String semantics;
  final void Function(_PanelKind) onEnter;
  final void Function(_PanelKind) onExit;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return RailHoverTarget<_PanelKind>(
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
          // The tail flexes, never the count: a truncated figure is a wrong
          // figure, while a truncated noun is still a legible hint at one.
          Flexible(
            child: Text(
              unit.isEmpty ? ' $noun' : ' $noun / $unit',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: grid.AppPalette.textFaint,
                fontSize: 11.5,
              ),
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

  final RailFigureAnchor anchor;
  final _PanelKind kind;
  final IconData icon;
  final String value;
  final String semantics;
  final void Function(_PanelKind) onEnter;
  final void Function(_PanelKind) onExit;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return RailHoverTarget<_PanelKind>(
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
