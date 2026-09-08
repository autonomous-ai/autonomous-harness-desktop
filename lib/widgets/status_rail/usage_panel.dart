import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../usage/usage_window.dart';

/// The glyph that stands for an agent account wherever its usage is printed.
///
/// One place, because the rail and the panel both draw it and a account that
/// changed shape between the strip and the popover would read as two accounts.
IconData usageIconFor(UsageProvider provider) => switch (provider) {
  UsageProvider.claude => LucideIcons.asterisk,
  UsageProvider.codex => LucideIcons.circleDot,
};

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
            _WindowRow(window: window),
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
        Icon(
          usageIconFor(reading.provider),
          size: 13,
          color: grid.AppPalette.textSecondary,
        ),
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
          Text(
            _freshness(fetchedAt),
            style: TextStyle(
              color: grid.AppPalette.textFaint,
              fontSize: 10.5,
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
  const _WindowRow({required this.window});

  final UsageWindow window;

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
        UsageBar(usedPercent: window.usedPercent),
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
/// Turns amber past [_warnAt]: the figure beside it is already exact, so the
/// colour is not carrying the number — it is carrying the moment the number
/// starts to matter, which a row of identical grey bars cannot.
class UsageBar extends StatelessWidget {
  const UsageBar({super.key, required this.usedPercent, this.height = 3});

  final double usedPercent;
  final double height;

  static const double _warnAt = 80;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: grid.AppSurface.recess),
            ),
            FractionallySizedBox(
              widthFactor: (usedPercent / 100).clamp(0.0, 1.0),
              child: ColoredBox(
                color: usedPercent >= _warnAt
                    ? grid.AppPalette.warn
                    : grid.AppPalette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
