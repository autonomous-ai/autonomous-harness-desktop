import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart' as grid;

/// The handful of colours one preview tile needs, already resolved.
///
/// ⚠️ A record of RESOLVED colours, not a brightness the tile reads tokens
/// against. [grid.AppTheme.as] swaps the global brightness, reads, and puts it
/// back in a `finally` — synchronously, before anything else in the frame. A
/// widget that only received a `Brightness` and read tokens inside its own
/// `build` would run AFTER the swap had been undone and would paint the palette
/// the app is currently wearing, in all three tiles. Resolving up front is what
/// makes the dark tile actually look dark while the app is light.
@immutable
class ThemeSwatches {
  const ThemeSwatches({
    required this.windowBg,
    required this.panelBg,
    required this.cardBg,
    required this.divider,
    required this.accent,
    required this.ink,
    required this.inkFaint,
  });

  /// Read the palette as [brightness] would resolve it.
  ///
  /// ⚠️ Never `await` inside the callback: that would hand the swapped
  /// brightness to the rest of the frame and the app would paint half a palette.
  factory ThemeSwatches.of(Brightness brightness) =>
      grid.AppTheme.as(brightness, () {
        return ThemeSwatches(
          windowBg: grid.AppPalette.windowBg,
          panelBg: grid.AppPalette.panelBg,
          cardBg: grid.AppPalette.cardBg,
          divider: grid.AppPalette.divider,
          accent: grid.AppPalette.accent,
          ink: grid.AppPalette.textPrimary,
          inkFaint: grid.AppPalette.textFaint,
        );
      });

  final Color windowBg;
  final Color panelBg;
  final Color cardBg;
  final Color divider;
  final Color accent;
  final Color ink;
  final Color inkFaint;
}

/// One theme choice, drawn as a miniature of the app rather than named in words.
///
/// This is how macOS System Settings offers the same choice, and it answers a
/// question a word cannot: what the app will actually look like. The artwork is
/// painted from the REAL tokens of the palette it advertises — a hand-typed hex
/// here would be a fourth palette, and the one that drifts is always the one
/// nobody is looking at.
class ThemePreviewTile extends StatefulWidget {
  const ThemePreviewTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.swatches,
    this.trailingSwatches,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// The palette this tile advertises. For `System`, the left half.
  final ThemeSwatches swatches;

  /// Set only by the `System` tile, which means both — so it draws both, cut
  /// down the middle, because that is exactly what the choice does.
  final ThemeSwatches? trailingSwatches;

  static const double _width = 156;
  static const double _height = 96;

  /// The artwork's own rounding, one step inside the tile's. A child is never
  /// rounder than its parent (§3), and at equal radii the clip and the rim
  /// fight along the corner.
  static const double _artRadius = grid.AppCard.radius - 3;

  @override
  State<ThemePreviewTile> createState() => _ThemePreviewTileState();
}

class _ThemePreviewTileState extends State<ThemePreviewTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final trailing = widget.trailingSwatches;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: grid.AppMotion.hover,
              curve: grid.AppMotion.curve,
              width: ThemePreviewTile._width,
              height: ThemePreviewTile._height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(grid.AppCard.radius),
                // ⚠️ The ring is drawn OUTSIDE the artwork, never over it: a rim
                // laid on top would tint the very colours the tile exists to
                // show. This is also the one place a border earns its keep —
                // it is carrying the selected state, not decorating a surface.
                border: Border.all(
                  color: widget.selected
                      ? grid.AppPalette.accent
                      : (_hovered
                            ? grid.AppPalette.textFaint
                            : grid.AppPalette.divider),
                  width: widget.selected ? 2 : 1,
                ),
              ),
              padding: EdgeInsets.all(widget.selected ? 2 : 3),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  ThemePreviewTile._artRadius,
                ),
                child: trailing == null
                    ? _MiniApp(swatches: widget.swatches)
                    : Row(
                        children: [
                          // Each half is drawn at the FULL tile width and then
                          // clipped, so the miniature keeps its proportions
                          // instead of being squeezed into half a window.
                          Expanded(
                            child: ClipRect(
                              child: OverflowBox(
                                maxWidth: ThemePreviewTile._width,
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: ThemePreviewTile._width,
                                  child: _MiniApp(swatches: widget.swatches),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: ClipRect(
                              child: OverflowBox(
                                maxWidth: ThemePreviewTile._width,
                                alignment: Alignment.centerRight,
                                child: SizedBox(
                                  width: ThemePreviewTile._width,
                                  child: _MiniApp(swatches: trailing),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.label,
              style: TextStyle(
                fontFamily: grid.AppFont.sans,
                fontFamilyFallback: grid.AppFont.sansFallback,
                fontSize: 12,
                letterSpacing: grid.AppFont.trackingFor(12),
                fontWeight: widget.selected
                    ? grid.AppFont.medium
                    : grid.AppFont.regular,
                color: widget.selected
                    ? grid.AppPalette.textPrimary
                    : grid.AppPalette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The miniature itself: this app's own shape — a rail on the left, a pane on
/// the right — so the tile reads as *this* app in that palette, not as a generic
/// light/dark swatch.
class _MiniApp extends StatelessWidget {
  const _MiniApp({required this.swatches});

  final ThemeSwatches swatches;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: swatches.windowBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 46,
            child: ColoredBox(
              color: swatches.panelBg,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(7, 9, 7, 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Bar(width: 20, color: swatches.accent),
                    const SizedBox(height: 8),
                    _Bar(width: 32, color: swatches.inkFaint),
                    const SizedBox(height: 5),
                    _Bar(width: 26, color: swatches.inkFaint),
                    const SizedBox(height: 5),
                    _Bar(width: 30, color: swatches.inkFaint),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 9, 9, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Bar(width: 44, color: swatches.ink, height: 4),
                  const SizedBox(height: 8),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: swatches.cardBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Bar(width: 52, color: swatches.divider),
                            const SizedBox(height: 5),
                            _Bar(width: 38, color: swatches.divider),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.color, this.height = 3});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(height / 2),
    ),
  );
}
