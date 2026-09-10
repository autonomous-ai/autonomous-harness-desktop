import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../usage/usage_offer.dart';

/// What a nearly-spent subscription looks like: what is happening, what to do
/// about it, and a way out of both.
///
/// Split from `UsageLimitNotice` because that widget is about *when* to speak —
/// thresholds, dismissals, the once-per-window rule — and this one is about
/// what the sentence looks like. Neither question gets easier by being asked in
/// the same file as the other.
class UsageLimitCard extends StatelessWidget {
  const UsageLimitCard({
    super.key,
    required this.offer,
    required this.onAct,
    required this.onDismiss,
  });

  final UsageOffer offer;
  final VoidCallback onAct;
  final VoidCallback onDismiss;

  /// Wide enough for the headline on one line and the detail on two, narrow
  /// enough to leave the pane behind it readable.
  static const double _width = 372;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Material(
      elevation: grid.AppMenu.elevation,
      color: grid.AppMenu.fill,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(grid.AppMenu.panelRadius),
        side: BorderSide(color: grid.AppMenu.rim),
      ),
      child: SizedBox(
        width: _width,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A warning triangle, and here it is earned: unlike
                  // `ProviderAllOffBanner`, this is not a supported setup being
                  // described — it is work that is about to stop.
                  Icon(
                    LucideIcons.triangleAlert300,
                    size: 15,
                    color: grid.AppPalette.warn,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      offer.headline,
                      style: TextStyle(
                        color: grid.AppPalette.textPrimary,
                        fontFamily: grid.AppFont.sans,
                        fontSize: 12.5,
                        fontWeight: grid.AppFont.semibold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _DismissButton(onPressed: onDismiss),
                ],
              ),
              const SizedBox(height: 5),
              Padding(
                // Aligned under the headline rather than under the glyph, so
                // the two sentences read as one block.
                padding: const EdgeInsets.only(left: 24, right: 4),
                child: Text(
                  offer.detail,
                  style: TextStyle(
                    color: grid.AppPalette.textSecondary,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 11),
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: onAct,
                    style: FilledButton.styleFrom(
                      backgroundColor: grid.AppPalette.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: TextStyle(
                        fontFamily: grid.AppFont.sans,
                        fontSize: 12.5,
                        fontWeight: grid.AppFont.medium,
                      ),
                    ),
                    child: Text(offer.actionLabel),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The way out. Quiet on purpose: closing this is a fair answer, not a failure
/// to convert, and a dismiss styled as a peer of the action would read as one.
class _DismissButton extends StatelessWidget {
  const _DismissButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Not now — until this limit resets',
    child: InkResponse(
      onTap: onPressed,
      radius: 14,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(
          LucideIcons.x300,
          size: 13,
          color: grid.AppPalette.textFaint,
        ),
      ),
    ),
  );
}
