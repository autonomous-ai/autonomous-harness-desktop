import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../usage/usage_window.dart';
import '../engine_identity.dart';

/// What one account has spent, window by window.
///
/// The panel behind a figure on the status rail: the same numbers the strip
/// prints, given the room to say which window each belongs to and when it
/// starts over.
class UsagePanelContent extends StatelessWidget {
  const UsagePanelContent({super.key, required this.reading});

  final ProviderUsage reading;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(reading: reading),
        if (reading.hasFigures)
          for (final window in reading.windows) ...[
            const SizedBox(height: 12),
            _WindowRow(
              window: window,
              color: engineIdentity(reading.provider.engineId).color,
            ),
          ]
        else ...[
          const SizedBox(height: 10),
          Text(
            // The source wrote this sentence, because the source is what knows
            // whether signing in or retrying is the way out of it.
            reading.message ?? 'No usage to show',
            style: TextStyle(
              color: grid.AppPalette.textFaint,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

/// The account this panel is about, and how fresh its figures are.
class _Header extends StatelessWidget {
  const _Header({required this.reading});

  final ProviderUsage reading;

  @override
  Widget build(BuildContext context) {
    final fetchedAt = reading.fetchedAt;
    return Row(
      children: [
        // The mark the machine rail already draws beside every agent of this
        // engine — the account's own logo, in its own colour. Drawing a second
        // glyph here would make one account look like two things.
        EngineMark(engine: reading.provider.engineId, size: 13),
        const SizedBox(width: 7),
        Text(
          reading.provider.label,
          style: TextStyle(
            color: grid.AppPalette.textPrimary,
            fontSize: 12.5,
            fontWeight: grid.AppFont.semibold,
          ),
        ),
        const Spacer(),
        if (fetchedAt != null)
          // Flexible, not bare: the account's name is the header's point and
          // must never be pushed out by the freshness note beside it, which is
          // the half that can afford to shorten.
          Flexible(
            child: Text(
              _freshness(fetchedAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: grid.AppPalette.textFaint,
                fontSize: 10.5,
              ),
            ),
          ),
      ],
    );
  }

  /// How long ago the figures were read, at the granularity the poll actually
  /// has. Anything finer would be a precision the once-a-minute refresh behind
  /// it cannot back up.
  static String _freshness(DateTime at) {
    final since = DateTime.now().difference(at);
    if (since.inMinutes < 1) return 'Updated just now';
    if (since.inMinutes < 60) return 'Updated ${since.inMinutes}m ago';
    return 'Updated ${since.inHours}h ago';
  }
}

/// One window: what it is, how full it is, and when it empties.
class _WindowRow extends StatelessWidget {
  const _WindowRow({required this.window, required this.color});

  final UsageWindow window;

  /// The account's own colour, so the bar and the mark at the top of the panel
  /// are visibly the same account's.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final resetsIn = window.resetsInLabel();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          window.label,
          style: TextStyle(
            color: grid.AppPalette.textPrimary,
            fontSize: 11.5,
            fontWeight: grid.AppFont.medium,
          ),
        ),
        const SizedBox(height: 6),
        UsageBar(usedPercent: window.usedPercent, color: color),
        const SizedBox(height: 5),
        Row(
          children: [
            Text(
              '${window.usedPercent.round()}% used',
              style: TextStyle(
                color: grid.AppPalette.textSecondary,
                fontSize: 11,
              ),
            ),
            const Spacer(),
            // No reset time means no countdown — never "resets in 0m", which
            // would read as a measurement rather than as the silence it is.
            if (resetsIn != null)
              Text(
                'Resets in $resetsIn',
                style: TextStyle(
                  color: grid.AppPalette.textFaint,
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// How full one window is.
///
/// Drawn the way the grid's memory bar is drawn — 6px and fully rounded — and
/// in the **account's own colour**, which is the same colour as the mark at the
/// top of the panel. The first version was a 3px grey sliver on a recessed
/// track, and at the single-digit percentages these windows actually sit at for
/// most of their life it was invisible: the figure beside it was doing all the
/// work and the bar was decoration that could not be seen.
///
/// Turns amber past [_warnAt]. The figure is already exact, so the colour is
/// not carrying the number — it is carrying the moment the number starts to
/// matter, which a bar that never changes hue cannot.
class UsageBar extends StatelessWidget {
  const UsageBar({
    super.key,
    required this.usedPercent,
    required this.color,
    this.height = 6,
  });

  final double usedPercent;

  /// The account's colour. Overridden by [_warn] once the window is nearly
  /// spent, because "which account" matters less at that point than "how close".
  final Color color;

  final double height;

  static const double _warnAt = 80;

  /// The narrowest the filled part may be drawn.
  ///
  /// The same reasoning as `MemorySplitBar.minSliceWidth`: below this a band of
  /// colour reads as a rendering artefact rather than a quantity, so a small
  /// percentage is over-represented on purpose. A window at 2% is *not* a
  /// window at 0%, and the bar has to be able to say so — the exact figure is
  /// printed directly underneath, so nothing is lost by rounding up here.
  static const double _minFill = 4;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final fill = usedPercent >= _warnAt ? grid.AppPalette.warn : color;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final full = constraints.maxWidth;
            final measured = full * (usedPercent / 100).clamp(0.0, 1.0);
            // Zero stays zero: an untouched window draws no colour at all, or
            // the bar would claim usage nobody has spent.
            final width = measured <= 0
                ? 0.0
                : measured.clamp(_minFill, full).toDouble();
            return Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(color: grid.AppSurface.recess),
                ),
                SizedBox(
                  // Keyed so a test can measure what was actually painted:
                  // this bar's whole failure mode is being present in the
                  // widget tree and invisible on screen.
                  key: const Key('usage-bar-fill'),
                  width: width,
                  child: ColoredBox(color: fill),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
