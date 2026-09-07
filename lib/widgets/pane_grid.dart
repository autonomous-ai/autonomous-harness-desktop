import 'package:flutter/material.dart';

import 'window_chrome.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shortcuts/app_shortcuts.dart';
import '../state/app_state.dart';
import '../state/pane_preset.dart';
import '../state/pane_splits.dart';
import '../state/terminal_pane.dart';
import '../terminal/terminal_font_store.dart';
import '../theme/app_theme.dart';
import 'agent_drag.dart';
import 'pane_snap.dart';
import 'harness_join_guide_screen.dart';
import 'terminal_panel.dart';

/// The terminals, as up to four tiles.
///
/// Fixed shapes rather than a splittable tree. A binary layout tree is what
/// tmux and herdr give you, and it earns its complexity — drag handles, sibling
/// ordering, a serialised shape — only once the count is open-ended. Capped at
/// four, every arrangement anyone would build by hand is already one of the
/// four below, and none of that machinery has to exist or be maintained.
///
/// The shapes are fixed; the DIVIDERS are not. Each one can be dragged and its
/// position is remembered per pane count (see [PaneSplits]) — which is the part
/// of a split tree people actually reach for, without the tree.
class PaneGrid extends StatelessWidget {
  const PaneGrid({super.key, required this.notifier});

  final AppNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AgentDragRef?>(
      valueListenable: agentDrag,
      builder: (context, dragging, _) {
        final panes = notifier.panes;
        if (panes.isEmpty) {
          return _DropZone(
            notifier: notifier,
            paneId: null,
            dragging: dragging,
            child: const _EmptyGrid(),
          );
        }
        final cells = <Widget>[
          for (final pane in panes)
            _PaneCell(
              key: pane.cellKey,

              notifier: notifier,
              pane: pane,
              dragging: dragging,
            ),
          // Revealed only mid-drag: a permanent "add a tile" cell would halve a
          // single terminal for the whole session to advertise itself.
          if (dragging != null && notifier.canAddPane)
            _DropZone(
              notifier: notifier,
              paneId: null,
              dragging: dragging,
              child: const _AddSlot(),
            ),
        ];
        return _arrange(cells, interactive: dragging == null);
      },
    );
  }

  /// Row-major, and the odd count spans rather than leaving a hole: three tiles
  /// are two over one, not two over one-and-a-gap.
  ///
  /// Keyed on the number of CELLS, not of panes: mid-drag an extra drop slot
  /// joins them, and the grid on screen is the one the dividers have to match.
  /// Those dividers are inert while an agent is being dragged — one pointer
  /// cannot mean both things.
  Widget _arrange(List<Widget> cells, {required bool interactive}) {
    final splits = notifier.splitsFor(cells.length);
    void put(PaneSplits next) => notifier.setSplits(cells.length, next);

    // Above four, one shape: a grid whose COLUMN COUNT is chosen by the width.
    // The hand-tuned shapes below stay exactly as they are — three tiles are
    // two over one with the bottom one SPANNING, and no uniform grid can say
    // that. They were tuned by eye and there is nothing to gain by re-deriving
    // them from a rule.
    if (cells.length > 4) {
      // The column count is the choice at this size, and `auto` states none —
      // which is exactly what the lattice already means by a null.
      return _Lattice(
        cells: cells,
        splits: splits,
        onSplits: interactive ? put : null,
        columns: notifier.presetFor(cells.length)?.statedColumns,
      );
    }

    final preset = notifier.presetFor(cells.length);

    switch (cells.length) {
      case 1:
        return cells[0];
      case 2:
        return LayoutBuilder(
          builder: (context, constraints) {
            // `splitLong` halves whichever side is longer, so two tiles on a
            // wide window are columns and two on a tall one are rows: a
            // terminal's usable size is its column count first, and halving the
            // short axis is what protects it. The other two say it outright.
            final side = switch (preset) {
              PanePreset.columns => Axis.horizontal,
              PanePreset.rows => Axis.vertical,
              _ =>
                constraints.maxWidth >= constraints.maxHeight
                    ? Axis.horizontal
                    : Axis.vertical,
            };
            return _Split(
              axis: side,
              fraction: splits.col,
              onFraction: interactive
                  ? (v) => put(splits.copyWith(col: v))
                  : null,
              first: cells[0],
              second: cells[1],
            );
          },
        );
      case 3:
        // Three across is the one shape here with no spanning tile, so it is
        // the lattice with its column count stated rather than measured — the
        // same widget the five-and-up grid uses, which is what makes its
        // dividers, its 40-column floor and its scroll fallback behave
        // identically to every other grid in the app.
        if (preset == PanePreset.cols3) {
          return _Lattice(
            cells: cells,
            splits: splits,
            onSplits: interactive ? put : null,
            columns: 3,
          );
        }
        // The rest each have ONE spanning tile — the whole reason three is not
        // a grid. Which tile spans, and on which side, is the choice.
        _Split pair(Widget a, Widget b, Axis axis) => _Split(
          axis: axis,
          fraction: splits.col,
          onFraction: interactive ? (v) => put(splits.copyWith(col: v)) : null,
          first: a,
          second: b,
        );
        return switch (preset) {
          PanePreset.oneOverTwo => _Split(
            axis: Axis.vertical,
            fraction: splits.row,
            onFraction: interactive
                ? (v) => put(splits.copyWith(row: v))
                : null,
            first: cells[0],
            second: pair(cells[1], cells[2], Axis.horizontal),
          ),
          PanePreset.mainLeft => _Split(
            axis: Axis.horizontal,
            fraction: splits.col,
            onFraction: interactive
                ? (v) => put(splits.copyWith(col: v))
                : null,
            first: cells[0],
            second: _Split(
              axis: Axis.vertical,
              fraction: splits.row,
              onFraction: interactive
                  ? (v) => put(splits.copyWith(row: v))
                  : null,
              first: cells[1],
              second: cells[2],
            ),
          ),
          _ => _Split(
            axis: Axis.vertical,
            fraction: splits.row,
            onFraction: interactive
                ? (v) => put(splits.copyWith(row: v))
                : null,
            first: pair(cells[0], cells[1], Axis.horizontal),
            second: cells[2],
          ),
        };
      default:
        // Four columns and main+stack are both just the lattice with the column
        // count stated instead of measured — the same widget, so the dividers,
        // the floor and the scroll fallback all behave identically.
        if (preset == PanePreset.cols4) {
          return _Lattice(
            cells: cells,
            splits: splits,
            onSplits: interactive ? put : null,
            columns: 4,
          );
        }
        if (preset == PanePreset.mainAndStack) {
          return _Split(
            axis: Axis.horizontal,
            fraction: splits.col,
            onFraction: interactive
                ? (v) => put(splits.copyWith(col: v))
                : null,
            first: cells[0],
            second: _Axis(
              axis: Axis.vertical,
              fractions: splits.rows.length == 3
                  ? splits.rows
                  : PaneSplits.even(3),
              minExtent: _MinTile.of().height,
              onFractions: interactive
                  ? (next) => put(splits.copyWith(rows: next))
                  : null,
              children: [cells[1], cells[2], cells[3]],
            ),
          );
        }
        return _Split(
          axis: Axis.vertical,
          fraction: splits.row,
          onFraction: interactive ? (v) => put(splits.copyWith(row: v)) : null,
          // BOTH rows read and write the same fraction, so the column is one
          // line down the whole grid and dragging it anywhere moves all of it —
          // the same way the row divider already spans the full width. Per-row
          // columns were tried first and read as a staircase: moving one
          // boundary left the tile under it behind, and the second drag existed
          // only to undo the damage of the first.
          first: _Split(
            axis: Axis.horizontal,
            fraction: splits.col,
            onFraction: interactive
                ? (v) => put(splits.copyWith(col: v))
                : null,
            first: cells[0],
            second: cells[1],
          ),
          second: _Split(
            axis: Axis.horizontal,
            fraction: splits.col,
            onFraction: interactive
                ? (v) => put(splits.copyWith(col: v))
                : null,
            first: cells[2],
            second: cells[3],
          ),
        );
    }
  }
}

/// Five or more tiles: a grid, sized by what a terminal actually needs.
///
/// The column count is NOT ceil(sqrt(n)). A terminal is unusable below 40
/// columns — both this app and the daemon clamp there, and the daemon does it
/// silently, so a tile narrower than that shows a grid wider than its own box
/// and simply loses the right-hand text. So width decides how many columns
/// there can be, and the rows fall out of that.
///
/// Every line is draggable, and each axis remembers its own fractions.
class _Lattice extends StatelessWidget {
  const _Lattice({
    required this.cells,
    required this.splits,
    required this.onSplits,
    this.columns,
  });

  final List<Widget> cells;
  final PaneSplits splits;
  final ValueChanged<PaneSplits>? onSplits;

  /// A column count the user asked for, instead of the one the width implies.
  /// Still bounded by the floor below — a shape cannot conjure room that is
  /// not there, and four columns on a narrow window is four unusable tiles.
  final int? columns;

  @override
  Widget build(BuildContext context) {
    final minTile = _MinTile.of();
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = cells.length;
        // As many columns as the width can carry at the floor, never more than
        // the tiles to put in them, and never fewer than one.
        final byWidth = (constraints.maxWidth / minTile.width).floor();
        final wanted = this.columns ?? byWidth;
        final columns = wanted.clamp(1, n);
        final rows = (n / columns).ceil();

        final colFractions = _axis(splits.cols, columns);
        final rowFractions = _axis(splits.rows, rows);

        // Does the window have the height for this many rows at the floor?
        //
        // When it does not, the grid SCROLLS rather than squeezing. Squeezing
        // is the tempting answer and it is wrong twice over: the daemon clamps
        // the terminal at twelve rows regardless, so the shrunk tile shows a
        // grid taller than its own box, and the pane's own chrome overflows —
        // measured at six tiles in 736px, which is 115px each against a 46px
        // header. Nine usable tiles behind a scrollbar beat nine unusable ones
        // in view.
        final needed = rows * minTile.height + _Split.grab * (rows - 1);
        final scrolls = needed > constraints.maxHeight;

        final grid = _Axis(
          axis: Axis.vertical,
          // Fixed rows while scrolling: a fraction of a height the window does
          // not have is not a thing anyone can drag meaningfully.
          fractions: scrolls ? PaneSplits.even(rows) : rowFractions,
          minExtent: minTile.height,
          onFractions: scrolls || onSplits == null
              ? null
              : (next) => onSplits!(splits.copyWith(rows: next)),
          children: [
            for (var r = 0; r < rows; r++)
              _Axis(
                axis: Axis.horizontal,
                fractions: colFractions,
                minExtent: minTile.width,
                // One column line down the whole grid, so dragging it in any
                // row moves all of it — the same rule the four-tile shape got.
                onFractions: onSplits == null
                    ? null
                    : (next) => onSplits!(splits.copyWith(cols: next)),
                children: [
                  for (var c = 0; c < columns; c++)
                    // The last row can be short. An empty box rather than a
                    // stretched neighbour: a tile that silently grows to twice
                    // its siblings reads as a layout bug, not as a spare slot.
                    // Clipped, because a tile can be squeezed below the floor:
                    // the grid still has to draw every pane it was given, and
                    // a window too small for this many is the user's call to
                    // make. What it must NOT do is let a pane paint outside
                    // its own box — that is a render overflow, which is a bug
                    // whatever the window size.
                    if (r * columns + c < n)
                      ClipRect(child: cells[r * columns + c])
                    else
                      const SizedBox.shrink(),
                ],
              ),
          ],
        );

        if (!scrolls) return grid;
        return SingleChildScrollView(
          child: SizedBox(height: needed, child: grid),
        );
      },
    );
  }

  /// The stored fractions if they still describe this many slots, else even.
  ///
  /// A count change invalidates them rather than stretching them: three columns
  /// of remembered widths say nothing about where two lines belong, and a
  /// guessed answer is worse than the even one nobody has an opinion about yet.
  static List<double> _axis(List<double> stored, int slots) =>
      stored.length == slots ? stored : PaneSplits.even(slots);
}

/// N children along one axis, with a draggable line between each pair.
class _Axis extends StatelessWidget {
  const _Axis({
    required this.axis,
    required this.fractions,
    required this.minExtent,
    required this.onFractions,
    required this.children,
  });

  final Axis axis;
  final List<double> fractions;
  final double minExtent;
  final ValueChanged<List<double>>? onFractions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.length < 2) {
      return children.isEmpty ? const SizedBox.shrink() : children.first;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = axis == Axis.horizontal;
        final total = horizontal ? constraints.maxWidth : constraints.maxHeight;
        final available = total - _Split.grab * (children.length - 1);
        // No room to honour the floor for everyone: share it out evenly and
        // refuse the drag, rather than offering a line that cannot be obeyed.
        final cramped =
            !available.isFinite || available <= minExtent * children.length;
        final extents = [
          for (final f in fractions)
            cramped ? available / children.length : available * f,
        ];

        final laid = <Widget>[];
        for (var i = 0; i < children.length; i++) {
          laid.add(
            SizedBox(
              width: horizontal ? extents[i] : null,
              height: horizontal ? null : extents[i],
              child: children[i],
            ),
          );
          if (i == children.length - 1) continue;
          laid.add(
            _Divider(
              axis: axis,
              grab: _Split.grab,
              onDelta: cramped || onFractions == null
                  ? null
                  : (delta) => onFractions!(
                      _moved(extents, i, delta, available, minExtent),
                    ),
              onReset: cramped || onFractions == null
                  ? null
                  : () => onFractions!(PaneSplits.even(children.length)),
            ),
          );
        }
        return Flex(direction: axis, children: laid);
      },
    );
  }

  /// Move ONE line: the pair either side of it trade space and nothing else
  /// moves. Pushing every slot along would make one drag rearrange the whole
  /// row, which is not what a hand on a boundary is asking for.
  static List<double> _moved(
    List<double> extents,
    int line,
    double delta,
    double available,
    double minExtent,
  ) {
    final next = [...extents];
    final room = next[line] + next[line + 1];
    // Snapped against the PAIR's own room, so a boundary between two tiles in a
    // row of five feels the same as the only boundary on the screen.
    final wanted = snapFraction((next[line] + delta) / room, room) * room;
    final first = wanted.clamp(minExtent, room - minExtent);
    next[line] = first;
    next[line + 1] = room - first;
    return [for (final e in next) e / available];
  }
}

/// The smallest a tile may be dragged to, in pixels.
///
/// MEASURED, not guessed, and it is the whole reason a divider clamps at all:
/// both ends already floor a terminal at 40 columns and 12 rows, and the daemon
/// applies that floor SILENTLY (`boundedSize` in tmuxStream.ts). Drag a tile
/// narrower than 40 columns and nothing reports it — the pane simply shows a
/// grid wider than the space it has, clipped, with nothing on screen saying
/// why. So the divider stops where the terminal does.
///
/// The font is one process-wide setting, so one measurement serves every tile.
class _MinTile {
  static double _forSize = -1;
  static Size _cached = Size.zero;

  static Size of() {
    final style = terminalFontStore.value;
    if (style.fontSize == _forSize) return _cached;
    // The renderer measures its cell by laying out ten 'm' and dividing; do the
    // same here rather than inventing a second idea of how wide a column is.
    final painter = TextPainter(
      text: TextSpan(
        text: 'mmmmmmmmmm',
        style: TextStyle(
          fontFamily: style.fontFamily,
          fontFamilyFallback: style.fontFamilyFallback,
          fontSize: style.fontSize,
          height: style.height,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final cellW = painter.width / 10;
    final cellH = painter.height;
    _forSize = style.fontSize;
    // 46 is the pane header, which is chrome the terminal never gets.
    _cached = Size(40 * cellW + 16, 46 + 12 * cellH + 8);
    return _cached;
  }
}

/// Two children and a draggable boundary between them.
///
/// `onFraction == null` means the boundary is drawn but inert — used while an
/// agent is being dragged across the grid.
class _Split extends StatelessWidget {
  const _Split({
    required this.axis,
    required this.first,
    required this.second,
    required this.fraction,
    required this.onFraction,
  });

  final Axis axis;
  final Widget first;
  final Widget second;
  final double fraction;
  final ValueChanged<double>? onFraction;

  /// 1px of line, 9px of grab. A boundary you have to hit exactly is a
  /// boundary people give up on, and the extra 8px sit over tile edges where
  /// there is nothing else to press.
  static const double grab = 9;

  @override
  Widget build(BuildContext context) {
    final minTile = _MinTile.of();
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = axis == Axis.horizontal;
        final total = horizontal ? constraints.maxWidth : constraints.maxHeight;
        final minEach = horizontal ? minTile.width : minTile.height;
        final available = total - grab;

        // Too small to honour both floors: centre it and refuse the drag. The
        // alternative is a boundary that can be moved but never obeyed.
        if (!available.isFinite || available <= minEach * 2) {
          return Flex(
            direction: axis,
            children: [
              Expanded(child: first),
              _Divider(axis: axis, grab: grab, onDelta: null),
              Expanded(child: second),
            ],
          );
        }

        final firstExtent = (available * fraction).clamp(
          minEach,
          available - minEach,
        );

        return Flex(
          direction: axis,
          children: [
            SizedBox(
              width: horizontal ? firstExtent : null,
              height: horizontal ? null : firstExtent,
              child: first,
            ),
            _Divider(
              axis: axis,
              grab: grab,
              onDelta: onFraction == null
                  ? null
                  : (delta) => onFraction!(
                      snapFraction(
                        ((firstExtent + delta) / available).clamp(0.0, 1.0),
                        available,
                      ),
                    ),
              onReset: onFraction == null ? null : () => onFraction!(0.5),
            ),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({
    required this.axis,
    required this.grab,
    required this.onDelta,
    this.onReset,
  });

  final Axis axis;
  final double grab;
  final ValueChanged<double>? onDelta;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final horizontal = axis == Axis.horizontal;
    final line = ColoredBox(
      color: AppColors.border,
      child: SizedBox(
        width: horizontal ? 1 : double.infinity,
        height: horizontal ? double.infinity : 1,
      ),
    );
    final bar = SizedBox(
      width: horizontal ? grab : null,
      height: horizontal ? null : grab,
      child: Center(child: line),
    );
    if (onDelta == null) return bar;
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        // Opaque: the grab strip lies over the tiles either side, and a drag
        // that started on it must not also reach the terminal underneath.
        behavior: HitTestBehavior.opaque,
        onDoubleTap: onReset,
        onHorizontalDragUpdate: horizontal ? (d) => onDelta!(d.delta.dx) : null,
        onVerticalDragUpdate: horizontal ? null : (d) => onDelta!(d.delta.dy),
        child: bar,
      ),
    );
  }
}

class _PaneCell extends StatelessWidget {
  const _PaneCell({
    super.key,
    required this.notifier,
    required this.pane,
    required this.dragging,
  });

  final AppNotifier notifier;
  final TerminalPane pane;
  final AgentDragRef? dragging;

  bool get _single => notifier.panes.length == 1;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final focused = notifier.isPaneFocused(pane.id);
    final agentId = pane.agentId;
    final blocked =
        agentId != null &&
        notifier.questionFor(pane.machineId, agentId) != null;
    return Listener(
      // Translucent so the press still reaches the renderer underneath: on
      // macOS the terminal is a WebView and AppKit gives it first responder on
      // its own, so this only has to keep the app's idea of the current tile in
      // step with the one the keyboard already went to.
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => notifier.focusPane(pane.id),
      child: Container(
        decoration: BoxDecoration(
          color: grid.AppPalette.windowBg,
          border: Border.all(
            // Only meaningful with company. A ring around the only tile would
            // be decoration, since there is nowhere else focus could be.
            color: _single
                ? Colors.transparent
                : focused
                ? AppColors.accent
                : AppColors.border,
            width: 1,
          ),
        ),
        // Attention, drawn OVER the terminal and inside the border above, so a
        // pane can carry both at once — this one is blocked AND focused is a
        // normal state, not a conflict to resolve. It is amber and 2px against
        // the border's 1px accent precisely so the two never read as each
        // other. Unlike focus, it shows on a single pane too: with one tile
        // there is nowhere else focus could be, but there is very much a
        // question waiting.
        foregroundDecoration: blocked
            ? BoxDecoration(
                border: Border.all(color: grid.AppPalette.warn, width: 2),
              )
            : null,
        // Keeps a terminal's constant repainting inside its own layer instead
        // of dirtying the whole grid. No key: nothing reads this boundary, it
        // only has to exist.
        child: RepaintBoundary(
          child: _SwapZone(
            notifier: notifier,
            paneId: pane.id,
            child: _DropZone(
              notifier: notifier,
              paneId: pane.id,
              dragging: dragging,
              child: ValueListenableBuilder<PaneDragRef?>(
                valueListenable: paneDragging,
                // The tile being carried fades where it sits, so the grid shows
                // where it came FROM while the ghost shows where it is going.
                builder: (context, inFlight, child) => Opacity(
                  opacity: inFlight?.paneId == pane.id ? 0.35 : 1,
                  child: child,
                ),
                child: _PaneContent(
                  notifier: notifier,
                  pane: pane,
                  single: _single,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaneContent extends StatelessWidget {
  const _PaneContent({
    required this.notifier,
    required this.pane,
    required this.single,
  });

  final AppNotifier notifier;
  final TerminalPane pane;
  final bool single;

  @override
  Widget build(BuildContext context) {
    final machine = notifier.stateOf(pane.machineId);
    void close() => notifier.closePane(pane.id);

    final wantedAgentId = pane.agentId;

    if (machine == null) {
      // The ordinary state of a restored tile for the first moments of a launch,
      // and of a tile whose machine is briefly out of the list.
      return _PaneStatus(
        title: wantedAgentId ?? pane.machineId,
        icon: Icons.hourglass_empty,
        message: 'Waiting for this machine to answer…',
        onClose: single ? null : close,
        busy: true,
      );
    }

    final agentName = wantedAgentId == null
        ? null
        : machine.agents
              .where((agent) => agent.id == wantedAgentId)
              .map((agent) => agent.name)
              .firstOrNull;

    // Deliberately NOT gated on isLinkPromptDismissed: dismissing only suppresses the popup (see
    // showLinkMachineScreenDialog / HomeScreen._maybeShowLinkDialog) — the tile's own status stays
    // honest about the machine actually being unlinked regardless.
    final needsLink =
        machine.isRemote && !machine.isLocalMachine && machine.needsLink;
    if (needsLink) {
      return _PaneStatus(
        title: agentName ?? machine.machine.displayName,
        icon: Icons.link_off,
        message:
            '${machine.machine.displayName} is not linked to this computer yet.',
        onClose: single ? null : close,
      );
    }

    final offline =
        machine.nodeOnline == false ||
        (machine.isLocalMachine && !machine.usesLocalTransport);
    if (offline) {
      return _Guide(
        single: single,
        onClose: close,
        title: agentName ?? machine.machine.displayName,
        compactMessage: machine.isLocalMachine
            ? 'Harness is not running on this computer.'
            : 'Harness is not running on ${machine.machine.displayName}.',
        compactIcon: Icons.cloud_off,
        full: HarnessJoinGuideScreen(
          notifier: notifier,
          machineState: machine,
          agentName: agentName ?? 'selected agent',
        ),
      );
    }

    // A machine tile that has nothing left to report. It arrived to carry a
    // link prompt or a setup form; once those are answered it has said all it
    // has to say, and the person can drag an agent into it.
    if (wantedAgentId == null) {
      return _PaneStatus(
        title: machine.machine.displayName,
        icon: Icons.check_circle_outline,
        message: 'This machine is ready. Drag an agent here to open it.',
        onClose: close,
      );
    }

    if (agentName == null) {
      return _PaneStatus(
        title: wantedAgentId,
        icon: Icons.help_outline,
        message: 'This agent is no longer on ${machine.machine.displayName}.',
        onClose: close,
      );
    }

    final session = pane.session;
    if (session == null) {
      return _PaneStatus(
        title: agentName,
        icon: Icons.hourglass_empty,
        message: 'Attaching…',
        onClose: single ? null : close,
        busy: true,
      );
    }

    // LayoutBuilder ONLY to learn this tile's size, for the drag ghost to be
    // cut to. Asking the render object instead — `key.currentContext.size` —
    // is what Flutter refuses outright during build: "the size getter should
    // only be called from paint callbacks or interaction event handlers", and
    // it does not warn, it throws, so every pane became a red error box.
    return LayoutBuilder(
      builder: (context, constraints) => TerminalPanel(
        notifier: notifier,
        session: session,
        focused: notifier.isPaneFocused(pane.id),
        composerVisible: pane.composerVisible,
        onToggleComposer: () => notifier.toggleComposer(pane.id),
        onClose: single ? null : close,
        // A single tile has no slot to hold, so the pin has nothing to say.
        pinned: pane.isPinned,
        onTogglePin: single ? null : () => notifier.togglePinPane(pane.id),
        onRendererFocus: () => notifier.focusPane(pane.id),
        // Nothing to trade places with while it is the only tile.
        paneDrag: single
            ? null
            : PaneDragHandle(
                ref: PaneDragRef(paneId: pane.id),
                size: constraints.biggest,
              ),
      ),
    );
  }
}

/// Where a dragged pane may be dropped to trade places with this one.
///
/// A sibling of [_DropZone] rather than a branch inside it: they are live at
/// different times and mean different things at the same pixel — a rail row
/// landing here REPLACES what this tile shows, a pane landing here SWAPS the
/// two. `DragTarget<T>` keeps them apart by generic, so neither has to ask what
/// kind of drag is in flight.
class _SwapZone extends StatelessWidget {
  const _SwapZone({
    required this.notifier,
    required this.paneId,
    required this.child,
  });

  final AppNotifier notifier;
  final int paneId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ValueListenableBuilder<PaneDragRef?>(
      valueListenable: paneDragging,
      builder: (context, dragging, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                // Off entirely unless a pane is in flight, so the terminal
                // underneath keeps every click the rest of the time.
                ignoring: dragging == null || dragging.paneId == paneId,
                child: DragTarget<PaneDragRef>(
                  onAcceptWithDetails: (details) =>
                      notifier.reorderPane(details.data.paneId, paneId),
                  builder: (context, candidate, _) => candidate.isEmpty
                      ? const SizedBox.expand()
                      : Container(
                          color: AppColors.accent.withValues(alpha: 0.16),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: grid.AppPalette.panelBg,
                                border: Border.all(color: AppColors.accent),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Swap with this pane',
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontFamily: AppFonts.sans,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A full-screen guide, but only where one fits.

///
/// The link and join screens are fixed-width cards written for the whole
/// window. In a quarter tile they would overflow rather than shrink, so a tile
/// too small to hold one says the same thing in a sentence. Measured, not
/// counted: a small window has the same problem with a single tile.
class _Guide extends StatelessWidget {
  const _Guide({
    required this.single,
    required this.onClose,
    required this.title,
    required this.compactMessage,
    required this.compactIcon,
    required this.full,
  });

  final bool single;
  final VoidCallback onClose;
  final String title;
  final String compactMessage;
  final IconData compactIcon;
  final Widget full;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final roomForCard =
            constraints.maxWidth >= 520 && constraints.maxHeight >= 430;
        if (roomForCard) {
          if (single) return full;
          return Column(
            children: [
              _PaneHeader(title: title, onClose: onClose),
              Expanded(child: full),
            ],
          );
        }
        return _PaneStatus(
          title: title,
          icon: compactIcon,
          message: compactMessage,
          onClose: single ? null : onClose,
        );
      },
    );
  }
}

/// The same 46pt strip TerminalPanel draws, for the tiles that have no terminal
/// to draw one — so the close button never moves between states.
class _PaneHeader extends StatelessWidget {
  const _PaneHeader({required this.title, this.onClose});

  final String title;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // The pane's head is a drag handle too: with the title bar hidden it is
    // the top edge of the window.
    return WindowDragArea(
      child: SizedBox(
        height: 46,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text,
                    fontFamily: AppFonts.sans,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onClose != null) PaneCloseButton(onPressed: onClose!),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaneStatus extends StatelessWidget {
  const _PaneStatus({
    required this.title,
    required this.icon,
    required this.message,
    this.onClose,
    this.busy = false,
  });

  final String title;
  final IconData icon;
  final String message;
  final VoidCallback? onClose;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Column(
      children: [
        _PaneHeader(title: title, onClose: onClose),
        Divider(height: 1, color: AppColors.border),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(icon, size: 26, color: AppColors.mutedStrong),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.mutedStrong,
                      fontFamily: AppFonts.sans,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Where a dragged rail row can land.
///
/// [paneId] null means "make a new tile"; otherwise the drop replaces what that
/// tile is showing. Hit-testable only while a drag is actually in flight, so an
/// ordinary click still reaches the terminal underneath.
class _DropZone extends StatelessWidget {
  const _DropZone({
    required this.notifier,
    required this.paneId,
    required this.dragging,
    required this.child,
  });

  final AppNotifier notifier;
  final int? paneId;
  final AgentDragRef? dragging;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: dragging == null,
            child: DragTarget<AgentDragRef>(
              onAcceptWithDetails: (details) => notifier.assignAgentToPane(
                paneId,
                details.data.machineId,
                details.data.agentId,
              ),
              builder: (context, candidate, _) => candidate.isEmpty
                  ? const SizedBox.expand()
                  : Container(
                      color: AppColors.accent.withValues(alpha: 0.16),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: grid.AppPalette.panelBg,
                            border: Border.all(color: AppColors.accent),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            paneId == null
                                ? 'Open ${candidate.first?.name ?? 'agent'} here'
                                : 'Show ${candidate.first?.name ?? 'agent'} in this pane',
                            style: TextStyle(
                              color: AppColors.text,
                              fontFamily: AppFonts.sans,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddSlot extends StatelessWidget {
  const _AddSlot();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: grid.AppPalette.windowBg,
        border: Border.all(color: AppColors.border),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 24, color: AppColors.mutedStrong),
            const SizedBox(height: 8),
            Text(
              'Drop here for a new pane',
              style: TextStyle(
                color: AppColors.mutedStrong,
                fontFamily: AppFonts.sans,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyGrid extends StatelessWidget {
  const _EmptyGrid();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // Holds the keyboard while there is no terminal to hold it.
    //
    // App shortcuts are bound above this screen (home_screen.dart) and, like
    // every Flutter shortcut, they are delivered along the focus chain — from
    // whatever has focus up through its ancestors. With no pane open nothing
    // inside the screen has any, so the chain starts at the route's own scope,
    // which sits ABOVE the bindings: ⌘\, ⌘N, ⌘R and ⌘/ all did nothing until
    // the first terminal took focus. This is the state that tells the user to
    // press ⌘/ two lines below, so it had better answer.
    //
    // Safe here in a way it is not on the screen's own scope: this widget
    // exists only while there is no terminal, so it can never be the node that
    // keeps a focused pane from opening its TextInput connection.
    return Focus(
      autofocus: true,
      skipTraversal: true,
      child: ColoredBox(
        color: grid.AppPalette.windowBg,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select an agent, or drag one in from the left.',
                style: TextStyle(
                  color: AppColors.mutedStrong,
                  fontFamily: AppFonts.sans,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              // The empty pane is the one screen a new user is guaranteed to
              // look at, and it is doing nothing else. A sheet behind a key
              // nobody has been told about is a sheet nobody opens.
              Text(
                'Press ${shortcutHintFor(ShortcutAction.showShortcuts)} for '
                'keyboard shortcuts',
                style: TextStyle(
                  color: grid.AppPalette.textFaint,
                  fontFamily: AppFonts.sans,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
