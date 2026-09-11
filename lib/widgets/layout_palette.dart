import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_dialog.dart';
import '../state/app_state.dart';
import '../state/pane_preset.dart';
import '../theme/app_theme.dart';

/// ⌘S — pick the shape of the grid.
///
/// Shapes are DRAWN, not listed. "Two over one" and "one over two" are the same
/// four words in a different order, and nobody reads a layout name twice; the
/// little diagram is the whole interface and the label only confirms it.
///
/// Every size has a choice except one tile. Up to four they are named shapes;
/// above that the choice is the column count, with "Auto" — as many columns as
/// the width carries at the forty-column floor — sitting among them as the
/// measured answer rather than as the only one.
/// Guards against a second ⌘S while the palette is already up. Without this,
/// each press stacked another dialog route — and another 30%-black barrier —
/// on top of the last, so holding or repeatedly pressing ⌘S read as the whole
/// window fading to black rather than as "already open".
bool _layoutPaletteOpen = false;

Future<void> showLayoutPalette(BuildContext context, AppNotifier notifier) {
  if (_layoutPaletteOpen) return Future<void>.value();
  _layoutPaletteOpen = true;
  return showAppDialog<void>(
    context: context,
    builder: (context) => _LayoutPalette(notifier: notifier),
  ).whenComplete(() => _layoutPaletteOpen = false);
}

class _LayoutPalette extends StatefulWidget {
  const _LayoutPalette({required this.notifier});

  final AppNotifier notifier;

  @override
  State<_LayoutPalette> createState() => _LayoutPaletteState();
}

class _LayoutPaletteState extends State<_LayoutPalette> {
  /// Which shape the arrow keys are resting on, which is NOT the same as the
  /// one in use: moving the cursor must not rearrange the grid under someone
  /// still looking at the choices. Applying is Enter, a digit, or a click.
  int? _cursor;

  /// Where the cursor is, read from state rather than from a captured local.
  ///
  /// Two keys can land inside one frame — an arrow and the Enter that takes it
  /// — and a value closed over at build time would still hold the position
  /// BEFORE the arrow moved, so the palette would apply the shape the cursor
  /// had just left. Reading it here means the answer is always current.
  ///
  /// It starts on the shape already in use, so the first arrow press steps off
  /// that one rather than jumping to the top of the list.
  int _cursorIn(List<PanePreset> choices, PanePreset? current) {
    if (choices.isEmpty) return 0;
    final start = _cursor ?? choices.indexOf(current ?? choices.first);
    return start.clamp(0, choices.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final notifier = widget.notifier;
    grid.AppTheme.watch(context);
    final count = notifier.panes.length;
    final choices = PanePreset.forCount(count);
    final current = notifier.presetFor(count);
    final cursor = _cursorIn(choices, current);

    return Dialog(
      backgroundColor: grid.AppGlass.surfaceFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: grid.AppGlass.hair),
      ),
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          // Repeats count: holding an arrow should walk the list, the way it
          // does in every other list on this OS.
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          if (choices.isEmpty) return KeyEventResult.ignored;

          void apply(PanePreset preset) {
            notifier.setPreset(count, preset);
            Navigator.of(context).pop();
          }

          final at = _cursorIn(choices, current);
          final step = _step(event.logicalKey);
          if (step != null) {
            // Clamped, not wrapped: the shapes are laid out as a strip on
            // screen, and a cursor that leaps from the last to the first reads
            // as a mis-key rather than as an answer.
            setState(() => _cursor = (at + step).clamp(0, choices.length - 1));
            return KeyEventResult.handled;
          }
          if (_isCommit(event.logicalKey)) {
            apply(choices[at]);
            return KeyEventResult.handled;
          }
          final index = _digit(event.logicalKey);
          if (index == null || index > choices.length) {
            return KeyEventResult.ignored;
          }
          apply(choices[index - 1]);
          return KeyEventResult.handled;
        },
        child: ConstrainedBox(
          // Wide enough that four shapes still get a diagram big enough to read
          // and a label that is not ellipsised into a guess.
          constraints: BoxConstraints(maxWidth: choices.length > 3 ? 500 : 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: Text(
                  choices.isEmpty ? 'Layout' : 'Layout · $count tiles',
                  style: TextStyle(
                    color: grid.AppPalette.textSecondary,
                    fontSize: 11.5,
                    letterSpacing: 0.9,
                    fontWeight: grid.AppFont.medium,
                  ),
                ),
              ),
              if (choices.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                  child: Text(
                    'One tile has no layout to choose. Open another and the '
                    'shapes appear here.',
                    style: TextStyle(
                      color: grid.AppPalette.textFaint,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                  // Wrapped, not a Row: a big grid offers five column counts,
                  // and five diagrams squeezed across one line are five things
                  // nobody can tell apart. 108px keeps a shape readable.
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var i = 0; i < choices.length; i++)
                        SizedBox(
                          width: 108,
                          child: _ShapeButton(
                            preset: choices[i],
                            count: count,
                            index: i + 1,
                            selected: choices[i] == current,
                            cursor: i == cursor,
                            onTap: () {
                              notifier.setPreset(count, choices[i]);
                              Navigator.of(context).pop();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
                  child: Text(
                    'Arrows to move, Enter or a number to pick. Changing the '
                    'shape resets the dividers — they described boundaries the '
                    'old one had.',
                    style: TextStyle(
                      color: grid.AppPalette.textFaint,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Which way an arrow moves the cursor.
  ///
  /// Up and left both mean "back" and down and right both mean "forward",
  /// because the shapes WRAP onto more than one line when there are five of
  /// them: a vertical key that only moved between rows would do nothing on a
  /// single-row palette, and stepping by one is the only motion that means the
  /// same thing however the wrap happens to fall.
  static int? _step(LogicalKeyboardKey key) => switch (key) {
    LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.arrowUp => -1,
    LogicalKeyboardKey.arrowRight || LogicalKeyboardKey.arrowDown => 1,
    _ => null,
  };

  static bool _isCommit(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.space;

  static int? _digit(LogicalKeyboardKey key) {
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
    ];
    final index = digits.indexOf(key);
    return index < 0 ? null : index + 1;
  }
}

class _ShapeButton extends StatelessWidget {
  const _ShapeButton({
    required this.preset,
    required this.count,
    required this.index,
    required this.selected,
    required this.cursor,
    required this.onTap,
  });

  final PanePreset preset;
  final int count;
  final int index;

  /// The shape the grid is in now.
  final bool selected;

  /// Where the arrow keys are resting. Drawn as a ring rather than as the
  /// selected fill, so "what I am about to pick" never looks like "what is
  /// already in use" — the two are different answers and both are on screen.
  final bool cursor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        decoration: BoxDecoration(
          color: selected
              ? grid.AppSurface.accentWash
              : grid.AppSurface.hoverFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: cursor
                ? AppColors.accent
                : (selected ? AppColors.accent : grid.AppGlass.hair),
            width: cursor ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: CustomPaint(painter: _ShapePainter(preset, count)),
            ),
            const SizedBox(height: 8),
            Text(
              preset.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? grid.AppPalette.textPrimary
                    : grid.AppPalette.textSecondary,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '⌘S then $index',
              style: TextStyle(
                fontFamily: grid.AppFont.mono,
                fontSize: 9.5,
                color: grid.AppPalette.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The diagram: [PanePreset.tiles], drawn.
///
/// It paints the shape's own description rather than a picture of it, and
/// `pane_preset_test` measures the real grid against the same list — so an
/// illustration that lies about the layout fails a test instead of misleading
/// someone into picking the wrong shape.
class _ShapePainter extends CustomPainter {
  const _ShapePainter(this.preset, this.count);

  final PanePreset preset;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 1.5;
    final fill = Paint()..color = AppColors.accent.withValues(alpha: 0.55);
    for (final unit in preset.tilesFor(count)) {
      final rect = Rect.fromLTRB(
        unit.left * size.width + gap,
        unit.top * size.height + gap,
        unit.right * size.width - gap,
        unit.bottom * size.height - gap,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(_ShapePainter old) =>
      old.preset != preset || old.count != count;
}
