import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import '../share_controller.dart';
import '../share_route.dart';

/// The left half: what this page is for, what this computer is doing about it
/// right now, and the three ways in.
///
/// A rail rather than a header because the routes are a *choice*, and a choice
/// reads as one when its options sit side by side and stay put. Stacked
/// disclosures made the reader open an option to find out what it was, which is
/// the wrong way round — the point of the description on each card is that it
/// can be compared without opening anything.
class ShareRail extends StatelessWidget {
  const ShareRail({
    super.key,
    required this.gridName,
    required this.offers,
    required this.route,
    required this.status,
    required this.onPick,
  });

  final String gridName;
  final List<ShareRouteOffer> offers;
  final ShareRoute route;
  final ShareStatus status;
  final ValueChanged<ShareRoute> onPick;

  bool get _live => status == ShareStatus.live;
  bool get _busy =>
      status == ShareStatus.starting || status == ShareStatus.stopping;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // The whole column scrolls, with the footnote pushed to the bottom whenever
    // there is room for it there. Scrolling only the card list is what a pinned
    // footnote usually costs: on a short window the last route gets cut through
    // the middle of its own sentence, and a half-drawn card reads as a broken
    // page rather than as a list that continues.
    return ColoredBox(
      color: SharePalette.railBg,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: ShareMetrics.railPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(gridName: gridName),
                    const SizedBox(height: ShareMetrics.railGap),
                    _Status(status: status),
                    const SizedBox(height: ShareMetrics.railGap),
                    Text(
                      _live ? 'WAYS TO SHARE' : 'CHOOSE A ROUTE',
                      style: ShareType.eyebrow,
                    ),
                    const SizedBox(height: 8),
                    for (final offer in offers) ...[
                      _RouteCard(
                        offer: offer,
                        selected: !_live && offer.route == route,
                        enabled: !_live && !_busy,
                        onPressed: () => onPick(offer.route),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const Spacer(),
                    const SizedBox(height: 18),
                    const _Footnote(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the page is for, in the reader's terms rather than the product's.
class _Header extends StatelessWidget {
  const _Header({required this.gridName});

  final String gridName;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Broken where the design breaks it, not where the rail happens to run
        // out: "Put this computer" over "to work." is the shape that was drawn.
        Text('Put this computer\nto work.', style: ShareType.railTitle),
        const SizedBox(height: 10),
        Text(
          'Answer questions for $gridName using hardware and keys you already '
          'own. Pick a route below. You can change it at any time.',
          style: ShareType.railBody,
        ),
      ],
    );
  }
}

/// What this computer is doing, right now, in one block.
class _Status extends StatelessWidget {
  const _Status({required this.status});

  final ShareStatus status;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final (title, note, live) = switch (status) {
      ShareStatus.live => (
        'Sharing',
        'This computer is answering questions from the grid.',
        true,
      ),
      ShareStatus.starting => (
        'Starting…',
        'The engine is coming up. It has not joined until it does.',
        false,
      ),
      ShareStatus.stopping => (
        'Stopping…',
        'Leaving the grid. This takes a few seconds.',
        false,
      ),
      ShareStatus.failed => (
        'Not sharing',
        'The last attempt did not start. The reason is on the right.',
        false,
      ),
      ShareStatus.idle => (
        'Not sharing yet',
        'Nothing on this computer is reachable from the grid.',
        false,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: SharePalette.surface,
        border: Border.all(color: SharePalette.rim),
        borderRadius: BorderRadius.circular(ShareMetrics.statusRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 5, right: 10),
            decoration: BoxDecoration(
              color: live ? SharePalette.liveDot : SharePalette.idleDot,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: live
                      ? ShareType.statusTitle.copyWith(
                          color: SharePalette.liveInk,
                        )
                      : ShareType.statusTitle,
                ),
                const SizedBox(height: 2),
                Text(note, style: ShareType.note),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One route, as something you can compare before you press it.
class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.offer,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final ShareRouteOffer offer;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: enabled ? onPressed : null,
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                decoration: BoxDecoration(
                  color: SharePalette.surface,
                  borderRadius: BorderRadius.circular(ShareMetrics.cardRadius),
                  border: Border.all(
                    color: selected ? SharePalette.fieldRim : SharePalette.rim,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1, right: 11),
                      child: Icon(
                        _icon,
                        size: 17,
                        color: selected
                            ? SharePalette.ink
                            : SharePalette.eyebrow,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(offer.title, style: ShareType.cardTitle),
                          const SizedBox(height: 3),
                          Text(offer.line, style: ShareType.cardLine),
                          const SizedBox(height: 5),
                          Text(offer.cost, style: ShareType.cost),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // The selected route is marked the way the settings rail marks
              // its own open row: a bar at the edge, not a blue ring round the
              // card. On this page blue is the colour of the thing to press,
              // and a card wearing it competed with the button that actually
              // starts the share.
              if (selected)
                Positioned(
                  left: 0,
                  top: 11,
                  bottom: 11,
                  width: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: SharePalette.accent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData get _icon => switch (offer.route) {
    ShareRoute.local => Icons.laptop_mac_outlined,
    ShareRoute.key => Icons.key_outlined,
    ShareRoute.server => Icons.dns_outlined,
  };
}

/// The closing note: what this actually commits the machine to.
class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(height: 1, color: SharePalette.footRule),
        const SizedBox(height: 12),
        Text(
          // Deliberately NOT Grid's own wording, which says sharing stops when
          // you quit the app. Here it does not: `grid join` hands the machine
          // to a detached engine and exits, so closing this window leaves the
          // computer serving. Saying otherwise would be the one sentence on the
          // page that costs somebody money.
          'The engine runs on its own once it starts — closing Harness does not '
          'stop it, only Stop sharing does. A key you paste never leaves this '
          'computer.',
          style: ShareType.footnote,
        ),
      ],
    );
  }
}
