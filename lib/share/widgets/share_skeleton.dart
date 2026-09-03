import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import '../../shared/widgets/skeleton.dart';

/// The Share pane while this computer is being probed — three HTTP probes
/// and two CLI spawns, which is long enough to see.
///
/// The same two columns at the same split as the answer, because the *shape*
/// of the answer is known before it arrives: a rail with a title, a status
/// block and a few route cards, and a pane with a heading over a plate of
/// fields. What is still unknown — which routes, what they say, which fields —
/// is blank at its final size. What is already known is set in ink: the
/// rail's title, the eyebrow, the footnote, and the heading of the pane.
///
/// A 20px spinner in the middle of a two-column page was the alternative, and
/// it made the whole layout *appear* a beat after the pane opened.
class ShareSkeleton extends StatelessWidget {
  const ShareSkeleton({super.key, required this.splitAt});

  /// The width under which the rail stacks above the detail — the pane's own
  /// breakpoint, passed in so the two cannot disagree.
  final double splitAt;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return SkeletonBlock(
      semanticsLabel: 'Checking this computer',
      child: LayoutBuilder(
        builder: (context, constraints) {
          const rail = _RailSkeleton();
          const detail = _DetailSkeleton();
          if (constraints.maxWidth < splitAt) {
            return SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 560, child: rail),
                  Divider(height: 1, color: SharePalette.rim),
                  SizedBox(height: constraints.maxHeight, child: detail),
                ],
              ),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(width: ShareMetrics.railWidth, child: rail),
              VerticalDivider(width: 1, color: SharePalette.rim),
              const Expanded(child: detail),
            ],
          );
        },
      ),
    );
  }
}

/// [ShareRail] with its facts blank: real title, real eyebrow, real footnote;
/// a status block and three route cards with bars where the words go.
class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton();

  static const _cards = 3;
  static const _titles = [0.42, 0.34, 0.5];
  static const _lines = [0.86, 0.7, 0.78];

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // The same scaffolding as [ShareRail]: the column fills the rail when it
    // can (the footnote pinned to the bottom) and grows past it when it must,
    // clipped rather than overflowing.
    return ColoredBox(
      color: SharePalette.railBg,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(child: _column(context)),
          ),
        ),
      ),
    );
  }

  Widget _column(BuildContext context) => Padding(
    padding: ShareMetrics.railPadding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Put this computer\nto work.', style: ShareType.railTitle),
        const SizedBox(height: 10),
        SkeletonText(style: ShareType.railBody, widthFactor: 0.94),
        SkeletonText(style: ShareType.railBody, widthFactor: 0.62),
        const SizedBox(height: ShareMetrics.railGap),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: SharePalette.surface,
            border: Border.all(color: SharePalette.rim),
            borderRadius: BorderRadius.circular(ShareMetrics.statusRadius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 5, right: 10),
                child: Skeleton.circle(size: 7),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(style: ShareType.statusTitle, width: 112),
                    const SizedBox(height: 2),
                    SkeletonText(style: ShareType.note, widthFactor: 0.8),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: ShareMetrics.railGap),
        Text('CHOOSE A ROUTE', style: ShareType.eyebrow),
        const SizedBox(height: 8),
        for (var i = 0; i < _cards; i++) ...[
          Opacity(
            opacity: skeletonFade(i, _cards, depth: skeletonFadeLight),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
              decoration: BoxDecoration(
                color: SharePalette.surface,
                borderRadius: BorderRadius.circular(ShareMetrics.cardRadius),
                border: Border.all(color: SharePalette.rim),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1, right: 11),
                    child: Skeleton(width: 17, height: 17, radius: 4),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonText(
                          style: ShareType.cardTitle,
                          widthFactor: _titles[i],
                        ),
                        const SizedBox(height: 3),
                        SkeletonText(
                          style: ShareType.cardLine,
                          widthFactor: _lines[i],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        const Spacer(),
        const SizedBox(height: 18),
        Divider(height: 1, color: SharePalette.footRule),
        const SizedBox(height: 12),
        Text(
          'The engine runs on its own once it starts — closing Harness does '
          'not stop it, only Stop sharing does. A key you paste never '
          'leaves this computer.',
          style: ShareType.footnote,
        ),
      ],
    ),
  );
}

/// [ShareDetail] with its route unknown: a heading's three lines, then a
/// plate of three fields and the Start button under it.
class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  static const _labels = [88.0, 64.0, 112.0];

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // The real pane's shape: heading pinned, body in a scroll view that here
    // cannot scroll — so a short window clips the plate rather than
    // overflowing it.
    return Padding(
      padding: ShareMetrics.panePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonText(style: ShareType.eyebrow, width: 150),
          const SizedBox(height: 7),
          SkeletonText(style: ShareType.paneTitle, widthFactor: 0.56),
          const SizedBox(height: 7),
          SkeletonText(style: ShareType.paneBody, widthFactor: 0.9),
          SkeletonText(style: ShareType.paneBody, widthFactor: 0.48),
          const SizedBox(height: ShareMetrics.paneGap),
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: _plate(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _plate(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: ShareMetrics.plateSection,
        decoration: BoxDecoration(
          color: SharePalette.surface,
          border: Border.all(color: SharePalette.rim),
          borderRadius: BorderRadius.circular(ShareMetrics.plateRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _labels.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              Opacity(
                opacity: skeletonFade(
                  i,
                  _labels.length,
                  depth: skeletonFadeLight,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(
                      style: ShareType.fieldLabel,
                      width: _labels[i],
                    ),
                    const SizedBox(height: 7),
                    const Skeleton(
                      height: 38,
                      radius: ShareMetrics.fieldRadius,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
      const Align(
        alignment: Alignment.centerLeft,
        child: Skeleton(
          width: 152,
          height: ShareMetrics.buttonHeight,
          radius: ShareMetrics.fieldRadius,
        ),
      ),
    ],
  );
}
