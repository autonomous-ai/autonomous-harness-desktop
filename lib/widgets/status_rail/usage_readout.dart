import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/widgets/skeleton.dart';
import '../../usage/usage_window.dart';
import 'rail_figure.dart';
import 'usage_panel.dart';

/// What the agent accounts on this machine have spent, along the status rail.
///
/// Stands where the grid figures stand, and appears exactly when they cannot:
/// with no grid chosen the strip used to read "No grid chosen", which is a
/// sentence that tells someone what they already know and gives them nothing.
/// These figures are true whether or not a grid is picked, because a rate limit
/// belongs to an *account*, not to a grid.
///
/// Generic over what a figure opens so it can hand the rail back its own panel
/// kind without that enum having to leave the rail.
class UsageReadout<T> extends StatelessWidget {
  const UsageReadout({
    super.key,
    required this.readings,
    required this.loading,
    required this.anchorFor,
    required this.kindFor,
    required this.onEnter,
    required this.onExit,
  });

  /// Every account, in the order they should be read.
  final List<ProviderUsage> readings;

  /// The first cycle has not landed yet and nothing has ever been shown.
  final bool loading;

  final RailFigureAnchor Function(UsageProvider) anchorFor;
  final T Function(UsageProvider) kindFor;
  final void Function(T) onEnter;
  final void Function(T) onExit;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // Blank at the size of the answer, so the strip does not assemble itself
    // one account at a time. Only before the first reading: once figures exist
    // they stay through every refresh.
    if (loading) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: _UsageSkeleton(),
      );
    }
    final shown = [
      for (final reading in readings)
        // An account nobody signed into here is left out rather than printed as
        // a row of blanks: the rail is for figures, and the reason there are
        // none belongs in the panel, where there is room to say it.
        if (reading.hasFigures) reading,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final reading in shown)
            RailHoverTarget<T>(
              kind: kindFor(reading.provider),
              anchor: anchorFor(reading.provider),
              semantics:
                  '${reading.provider.label} usage, '
                  '${reading.tightest?.usedPercent.round() ?? 0} percent used',
              onEnter: onEnter,
              onExit: onExit,
              child: _ProviderFigures(reading: reading),
            ),
        ],
      ),
    );
  }
}

/// One account's windows, as the strip prints them.
class _ProviderFigures extends StatelessWidget {
  const _ProviderFigures({required this.reading});

  final ProviderUsage reading;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: grid.AppPalette.textSecondary,
      fontSize: 11.5,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          usageIconFor(reading.provider),
          size: 12,
          color: grid.AppPalette.textFaint,
        ),
        const SizedBox(width: 5),
        for (final (index, window) in reading.windows.indexed) ...[
          if (index > 0)
            Text(
              ' · ',
              style: style.copyWith(color: grid.AppPalette.textFaint),
            ),
          Text(
            '${window.usedPercent.round()}% used',
            style: style.copyWith(fontWeight: grid.AppFont.medium),
          ),
          const SizedBox(width: 4),
          // The countdown when there is one, and the window's own name when
          // there is not — so every figure on the strip is followed by
          // something that says which limit it belongs to.
          Text(
            window.resetsInLabel() ?? window.label,
            style: style.copyWith(color: grid.AppPalette.textFaint),
          ),
        ],
      ],
    );
  }
}

/// The readout before the first answer: the same padding a live figure's hover
/// region takes, so the strip is the same width before and after.
class _UsageSkeleton extends StatelessWidget {
  const _UsageSkeleton();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: RailHoverTarget.gap,
      vertical: 4,
    ),
    child: SkeletonText(
      style: TextStyle(fontSize: 11.5, fontWeight: grid.AppFont.medium),
      width: 132,
    ),
  );
}
