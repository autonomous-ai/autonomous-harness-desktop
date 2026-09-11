import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../analytics/analytics.dart';
import '../../grid/grid_overview_controller.dart';
import '../../grid/grid_selection_store.dart';
import '../../grid/provider_enablement_store.dart';
import '../../grid/grid_surface.dart';
import '../../grid/node_metrics.dart';
import '../../grid/plural.dart';
import '../../shared/theme/app_theme.dart' as grid;
import '../../state/app_state.dart';
import '../../grid/grid_overview.dart';
import '../../grid/grid_power.dart';
import '../../shared/widgets/skeleton.dart';
import '../../usage/usage_accounts.dart';
import '../../usage/usage_controller.dart';
import '../../usage/usage_pressure.dart';
import '../../usage/usage_window.dart';
import '../node_dashboard/node_dashboard_screen.dart';
import '../share_grid/share_grid_dialog.dart';
import '../usage_limit_notice.dart';
import '../usage_offer_actions.dart';
import 'grid_models_panel.dart';
import 'grid_power_panel.dart';
import 'grid_stat_panels.dart';
import 'memory_ring.dart';
import 'rail_figure.dart';
import 'rail_provider_pill.dart';
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
    required this.notifier,
    this.controller,
    this.usage,
    this.selection,
    this.enablement,
    this.onShareIntelligence,
  });

  /// Handed down from the shell for [RailProviderPill]'s settings row — the
  /// rail holds no `AppNotifier` of its own, and Settings needs one.
  final AppNotifier notifier;

  /// Injected by tests. Null in the app, where the rail makes — and disposes —
  /// its own.
  final GridOverviewController? controller;

  /// The agent accounts' rate limits.
  ///
  /// Handed down by the shell, which owns it because [UsageLimitNotice] above
  /// this rail reads the same figures — two controllers would be two pollers
  /// and two answers. Null only in a test that wants the rail on its own, where
  /// the rail makes — and disposes — one for itself.
  final UsageController? usage;

  /// What new agents run on, for [RailProviderPill]. Injected by tests so the
  /// pill and the overview controller read ONE store: handed different ones
  /// they disagree about which provider is chosen, and the rail would then name
  /// a provider whose figures it is not showing.
  final GridSelectionStore? selection;

  /// Which providers this computer offers, for the pill's menu. Injected by
  /// tests so a run never reads the developer's own `providers_config.json`.
  final ProviderEnablementStore? enablement;

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
    // NO FILL, NO RULE — the strip is its text and nothing else.
    //
    // It used to paint AppGlass.sidebarFill with a hairline on top, matching the machine rail it ran
    // under: both were window furniture and a third tone would have read as a third pane. That rail is
    // a floating card on a gradient field now, so what this matched no longer exists, and a flat grey
    // slab laid across the bottom of the window was the one surface that did not belong to anything.
    return SizedBox(
      height: GridStatusRail.height,
      child: Padding(
        // Even on both sides now. The right was 10 to offset the version mark's
        // own hover inset, and that mark is gone — leaving 10 would be a
        // two-pixel lean nothing accounts for any more.
        padding: EdgeInsets.only(left: kGridSurfaceEnabled ? 4 : 12, right: 12),
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
                  notifier: widget.notifier,
                  selection: widget.selection,
                  enablement: widget.enablement,
                  onShareIntelligence: widget.onShareIntelligence,
                ),
              ),
            ),
          ],
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
    required this.notifier,
    this.selection,
    this.enablement,
    this.onShareIntelligence,
  });

  /// All three are the provider pill's, passed straight through: the pill lives
  /// inside this row because it stands where the grid's name did, and that is
  /// a position only this widget knows.
  final AppNotifier notifier;
  final GridSelectionStore? selection;
  final ProviderEnablementStore? enablement;

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
    // Any account with figures — a remote machine's included, since on a
    // computer signed in to nothing it can be the only one there is.
    final first = widget.usage.accounts
        .where((account) => account.reading.hasFigures)
        .firstOrNull;
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
          // The rail's own width is what `_railBudget` tapers the word-carrying
          // blocks against — see `_railBlock` for why this is not a flex.
          child: LayoutBuilder(
            builder: (context, constraints) => _figures(constraints.maxWidth),
          ),
        ),
      ),
    );
  }

  List<OverviewNode> get _onlineNodes => [
    for (final node in _grid?.overview?.nodes ?? const <OverviewNode>[])
      if (node.online) node,
  ];

  /// One block on the rail: as wide as its content, shrinkable, never greedy.
  ///
  /// The three requirements here genuinely conflict under a plain `Flexible`,
  /// which is why this took several passes to get right:
  ///
  ///  * `flex: 1` (a bare `Flexible`) lets the inner text ellipsise, but the
  ///    block also claims an equal share of the row's leftover room — four
  ///    such children split the slack four ways and drift apart.
  ///  * `flex: 0` alone stops the drift, but it measures the child against an
  ///    UNBOUNDED width, and these blocks are `mainAxisSize.max` Rows, which
  ///    cannot resolve against infinity — a layout assertion, not a bad look.
  ///  * `mainAxisSize.min` on the inner Row sizes to content, but on its own
  ///    it makes the `Flexible` inside inert and a long reading overflows.
  ///
  /// [maxWidth] is what breaks the tie, and it is why the blocks passed here
  /// pair it with `mainAxisSize.min`: the bound gives their inner `Flexible` a
  /// finite budget to ellipsise against, while `min` stops the block at its
  /// last glyph rather than stretching to fill that budget — a `max` Row here
  /// spent the whole allowance and left the surplus as visible dead space.
  /// Generous enough never to trim a normal reading; it bounds, it does not
  /// size.
  ///
  /// ⚠️ **A flex factor cannot be the answer to the fourth requirement** —
  /// giving width back on a narrow rail — and trying it is a mistake this
  /// file has now made twice. `flex` means BOTH "claim a share of the slack"
  /// and "yield a share of the shortfall", and there is no way to ask for the
  /// second without the first: a block set to `flex: 1` starts splitting the
  /// leftover room with the `Spacer`, so the counts at the far right stop
  /// sitting against the window edge. Every block here stays `flex: 0`, and
  /// the shrinking is done by [maxWidth] instead — see [_railBudget], which
  /// scales the bound with the rail so the ellipsis arrives from the cap
  /// rather than from the flex.
  Widget _railBlock({required double maxWidth, required Widget child}) =>
      Flexible(
        flex: 0,
        fit: FlexFit.loose,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );

  /// [full] on a roomy rail, tapering to [floor] as the window closes.
  ///
  /// This is the shrinking that [_railBlock] deliberately does not ask a flex
  /// factor for. The rail's own width is the only honest input: below
  /// [_taperFrom] every pixel the window loses has to come out of the two
  /// blocks that carry words, and above it they should be left alone entirely.
  double _railBudget(double railWidth, double full, double floor) {
    if (railWidth >= _taperFrom) return full;
    // Linear between the app's minimum window and the taper point, so the
    // reading gives up width smoothly rather than snapping at a breakpoint.
    final t = ((railWidth - _minRail) / (_taperFrom - _minRail)).clamp(
      0.0,
      1.0,
    );
    return floor + (full - floor) * t;
  }

  /// Above this the rail has room to spare and no block is trimmed.
  static const double _taperFrom = 1180;

  /// `desktop_window.dart`'s `minimumSize.width` — the narrowest the rail can
  /// actually be asked to lay out.
  static const double _minRail = 880;

  /// The rail for a provider with no machines on it.
  ///
  /// Everything the ordinary row would print here is zero, and zeros are the
  /// one thing this strip must not show for an absence — `0 · 0` beside a
  /// green dot is what a broken poll looks like, not what an empty provider
  /// looks like. So the figures give way to the sentence they would otherwise
  /// leave the reader to infer, and the offer that fixes it.
  ///
  /// The pill stays: it is how somebody switches to a provider that does have
  /// machines, which is the likeliest thing they want from this row.
  ///
  /// No staleness marker here, deliberately. The live dot elsewhere on this
  /// strip separates "measured just now" from "measured a while ago", and
  /// there is no measurement on this row to be old — a provider with nothing
  /// on it is equally empty whether the poll landed a second or a minute ago.
  Widget _emptyProviderRow(
    GridOverviewController controller,
    double railWidth,
  ) {
    final canShare = widget.onShareIntelligence != null;
    return Row(
      children: [
        _railBlock(
          maxWidth: 260,
          child: RailProviderPill(
            notifier: widget.notifier,
            selection: widget.selection,
            enablement: widget.enablement,
            fallbackName: controller.gridName,
          ),
        ),
        const SizedBox(width: RailHoverTarget.gap * 2 - 8),
        // No hover target and no chevron: the power panel behind them lists
        // machines, and there are none to list. A caret onto an empty card is
        // a promise the rail cannot keep.
        Flexible(
          flex: 0,
          fit: FlexFit.loose,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _railBudget(railWidth, 360, 180),
            ),
            child: Text(
              'No machines on this provider yet',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: grid.AppPalette.textFaint,
                fontSize: 11.5,
              ),
            ),
          ),
        ),
        const Spacer(),
        // The one thing a person can do about it, and only when the shell
        // handed down a way to open it — otherwise the row simply states the
        // fact rather than drawing a button that goes nowhere.
        if (canShare)
          _EmptyProviderAction(onPressed: widget.onShareIntelligence!),
      ],
    );
  }

  Widget _figures(double railWidth) {
    final controller = _grid;
    // No grid to describe: the strip reads the agent accounts instead. These
    // are the same figures either way — a rate limit is the account's, not the
    // grid's — so this is a substitution, not a fallback.
    if (controller == null) {
      // No provider chosen — so the pill says `Subscription`, and the figures
      // beside it are exactly what that subscription has spent. In a build with
      // no provider surface at all there is nothing to pick and no pill.
      return Row(
        children: [
          if (kGridSurfaceEnabled) ...[
            // `flex: 0` for the reason the grid branch gives at length: a bare
            // `Flexible` here is `flex: 1` against the `Expanded` after it, so
            // the pill would take HALF the rail to say one word.
            _railBlock(
              maxWidth: 260,
              child: RailProviderPill(
                notifier: widget.notifier,
                selection: widget.selection,
                enablement: widget.enablement,
              ),
            ),
            const SizedBox(width: RailHoverTarget.gap * 2 - 8),
          ],
          Expanded(
            child: UsageReadout<_PanelKind>(
              accounts: widget.usage.accounts,
              loading: widget.usage.loading,
              anchorFor: (provider) => _usageAnchors[provider]!,
              kindFor: _PanelKind.forProvider,
              onEnter: _onEnter,
              onExit: _onExit,
            ),
          ),
        ],
      );
    }
    final power = controller.power;
    final answered = power?.answered;
    // The first answer for this grid is still on its way. Every figure that
    // is about to appear is drawn blank at its final size, so the strip does
    // not assemble itself one number at a time — and only then: once a
    // reading exists it stays on screen through every refresh (see [stale]).
    final pending = power == null && controller.loading;
    // A provider nobody has joined yet. The relay answered — this is not a
    // failure and not a wait — but every figure it answered with is zero, and
    // the ordinary row renders that as a live dot, a chevron onto an empty
    // panel, and `0 · 0`. That reads like a rail that broke rather than a
    // provider with nothing on it, so it says which in words instead.
    if (power != null && power.isEmpty) {
      return _emptyProviderRow(controller, railWidth);
    }
    return Row(
      children: [
        // WHAT NEW AGENTS RUN ON — where the grid's name already stood.
        //
        // ⚠️ This REPLACES `_GridMark`'s name rather than standing beside it.
        // The rail was measured full at a 1000px window before any of this: a
        // pill added as a fourth thing at this end overflowed by 40px, and the
        // name it would have duplicated was already sitting here costing the
        // same width while being the one thing on the strip you could not act
        // on. Turning it into the control costs an icon and a caret, not a
        // block. What is left of `_GridMark` is the live dot and the memory
        // ring — the facts the pill does not carry.
        // ⚠️ `flex: 0`, and so is every flexible block on this row. A bare
        // `Flexible` is `flex: 1`, so the pill, the mark, the work figure and
        // the `Spacer` were splitting the rail's leftover room FOUR WAYS —
        // each block inflating to a quarter of slack it never asked for, which
        // is what stranded the work figure in the middle of the strip with a
        // 445px hole ahead of it. At `flex: 0` a loose child takes its
        // content's width and no more, and the `Spacer` is left as the only
        // thing claiming slack, which is its whole job.
        //
        // Loose rather than rigid so a narrow rail can still shrink these
        // blocks — but that only works because each one bounds itself (see
        // `_railBlock`): `flex: 0` lays the child out against an UNBOUNDED
        // width, and a `mainAxisSize.max` Row cannot resolve against infinity.
        //
        // The pill's own Row is `min` and its name is capped in its own file,
        // so it would survive unbounded — but it goes through `_railBlock` all
        // the same, because "safe as long as another file keeps its Row min"
        // is an invariant nothing here can see being broken.
        _railBlock(
          maxWidth: 260,
          child: RailProviderPill(
            notifier: widget.notifier,
            selection: widget.selection,
            enablement: widget.enablement,
            fallbackName: controller.gridName,
          ),
        ),
        // The rail's rhythm is `RailFigure.gap` of padding on each side of a
        // figure, so any two figures sit 2×9 apart. The pill is not a figure —
        // it carries 8px inside its own hover box — so it needs the difference
        // here to land on that same rhythm, or the seam between the pill and
        // the live dot reads tighter than every other seam on the strip.
        const SizedBox(width: RailHoverTarget.gap * 2 - 8),
        // Flexible for the same reason the figure after it is: this block
        // carries the memory reading, which is words (`1 / 1.7 TB`), and a
        // rigid child demands its full width and hands the overflow to its
        // neighbour rather than giving any up itself. `flex: 0` with a bound —
        // see `_railBlock`.
        // Tapers second, and less far than the work figure: the memory reading
        // is a measurement and would rather not be trimmed, but the ring beside
        // it makes the same claim as a picture, so a clipped `1.1 / 1.6 TB`
        // still leaves the block readable. Without any give here the rail runs
        // out once the work figure is spent, and a provider named longer than
        // `autonomous.ai` overflows a window the app actually allows.
        _railBlock(
          maxWidth: _railBudget(railWidth, 190, 150),
          child: _GridMark(
            controller: controller,
            anchor: _nameAnchor,
            onEnter: _onEnter,
            onExit: _onExit,
          ),
        ),
        if (pending)
          // Measured against what lands here — `92.4M tokens / 24h`, not the
          // bare `92.4M / 24h` this stood in for before the figure was given
          // its noun. A placeholder narrower than its answer is the jump a
          // skeleton exists to prevent.
          const _FigureSkeleton(key: Key('rail-work-skeleton'), width: 104),
        // Hard against the cluster it follows, not adrift after it. The gap
        // that opened here when the grid's name moved to the pill was the
        // hover padding `_Figure` has always carried: harmless behind a long
        // name, plainly a gap once the block ahead of it got short.
        if (power != null && answered != null && answered.freshInputTokens > 0)
          // Flexible, so the one figure on this strip that carries words gives
          // them up before the row overflows. The rail is a plain Row over the
          // window's full width: past the Spacer there is no slack left, and a
          // narrow window is what turns the naming of this figure into a
          // yellow-and-black bar along the bottom edge. `flex: 0` with a bound
          // — see `_railBlock`.
          // Tapers first and furthest, because it carries the words a reader
          // can most afford to lose: ` tokens / 24h` still means something
          // half-ellipsised, where a trimmed memory figure or a trimmed
          // provider name is simply wrong.
          _railBlock(
            maxWidth: _railBudget(railWidth, 230, 120),
            child: _Figure(
              anchor: _tokenAnchor,
              kind: _PanelKind.tokens,
              value: formatCount(answered.freshInputTokens),
              // Pluralised off the raw count, not off what `formatCount`
              // printed: past a thousand that prints "1.2M" and the noun
              // beside it is still plural, and only the count knows that.
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
    // THIS computer's reading drives the offer below, whatever else the panel
    // lists: a remote account running out is no reason to move this Mac's
    // agents anywhere (see `UsageController.accounts`).
    final reading = widget.usage.readings.firstWhere(
      (r) => r.provider == provider,
      orElse: () => ProviderUsage.loading(provider),
    );
    final accounts = [
      for (final account in widget.usage.accounts)
        if (account.provider == provider) account,
    ];
    // The same offer the card above the rail makes, in the one place that is
    // always reachable: that card shows once per window and can be closed, and
    // somebody who closed it an hour ago still needs a door.
    final alerts = usageAlerts([reading]);
    final offer = alerts.isEmpty
        ? null
        : usageOfferOf(
            widget.notifier,
            alerts.first,
            selection: widget.selection,
          ).offer;
    return _stat(
      kind,
      _usageAnchors[provider]!,
      UsagePanelContent(
        accounts: accounts.isEmpty
            ? [UsageAccount(reading: reading, isLocal: true)]
            : accounts,
        offer: offer,
        onAct: offer == null
            ? null
            : () => unawaited(
                runUsageOffer(
                  context,
                  widget.notifier,
                  offer,
                  selection: widget.selection,
                ),
              ),
      ),
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
      // ⚠️ `min`, and the `ConstrainedBox` in `_railBlock` is what makes that
      // safe. A `max` Row here stretched to the whole 190px budget even though
      // this cluster is ~141px of content, and the surplus fell into the
      // `Flexible` around the memory reading — which is the empty gap that
      // opened between the chevron and `1.1 / 1.6 TB`. Sized to its children
      // the block ends where its last glyph does; the bound above still gives
      // the `Flexible` a finite budget to ellipsise against on a narrow rail.
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
          // ⚠️ The grid's NAME used to follow this dot. The provider pill just
          // ahead of it carries it now — see the note at this row's head. What
          // stays is what the pill does not say: whether the reading is fresh,
          // and how full the memory is.
          //
          // The chevron that marks this block as openable moved up here with
          // it. It used to trail the whole cluster, which read as a caret on
          // the memory figure once the name it actually belonged to was gone —
          // beside the live dot it marks the block, which is what it means.
          if (power != null) ...[
            const SizedBox(width: 5),
            Icon(
              LucideIcons.chevronUp300,
              size: 11,
              color: grid.AppPalette.textFaint,
            ),
          ],
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
            // The one string in this block that can lose characters and still
            // mean something: the ring beside it keeps the reading legible.
            Flexible(
              child: Text(
                vram != null && used != null
                    ? formatVramShare(used, vram)
                    : '${(share * 100).round()}% load',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: grid.AppPalette.textSecondary,
                  fontSize: 11.5,
                ),
              ),
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
      // ⚠️ `min`, and it is only safe because `_railBlock` bounds this widget
      // from outside. A min-sized Row measures against its CHILDREN, so on its
      // own it would make the `Flexible` below inert and hand the overflow
      // upward — which is exactly what it did before that bound existed. With
      // a finite `maxWidth` above, `min` means the block stops at its last
      // glyph instead of stretching to fill the budget, and the flex still has
      // something real to shrink against when the rail runs short.
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
/// The offer beside an empty provider: put this machine on it.
///
/// A rail is normally what you *know* rather than what you *press* — but the
/// exception earns itself here. Every other figure on this strip reports
/// something; this row reports an absence, and an absence with no way to act
/// on it is a dead end at the bottom of the window. It is drawn as quietly as
/// the version mark it sits beside, so a rail that usually carries no buttons
/// does not suddenly grow a loud one.
class _EmptyProviderAction extends StatefulWidget {
  const _EmptyProviderAction({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_EmptyProviderAction> createState() => _EmptyProviderActionState();
}

class _EmptyProviderActionState extends State<_EmptyProviderAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Semantics(
      button: true,
      label: 'share this computer with the provider',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _hovered ? grid.AppSurface.hoverFill : null,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.share2300,
                  size: 11,
                  color: _hovered
                      ? grid.AppPalette.accentOnSurface
                      : grid.AppPalette.textFaint,
                ),
                const SizedBox(width: 6),
                Text(
                  'Share this computer',
                  style: TextStyle(
                    color: _hovered
                        ? grid.AppPalette.textPrimary
                        : grid.AppPalette.textSecondary,
                    fontFamily: grid.AppFont.sans,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
