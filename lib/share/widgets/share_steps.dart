import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import '../share_route.dart';

/// The three moves every route on this page is made of, as one column.
///
/// Before this, each route drew its own pane: the local one a picker over a
/// void, the key one a plate and a button, the server one two competing blue
/// buttons split by an OR rule. Same job, three shapes — so changing route
/// meant reading the screen again from the top.
///
/// A stepper is the smallest thing that fixes it. Step 1 is the route, step 2
/// is *what answers the questions* — a model, a key, an engine — and step 3 is
/// the same everywhere: name it and start. The reader learns the shape once.
/// It also gives the empty machine somewhere to stand: a disk with no model is
/// not a blank pane any more, it is step 2 of 3 with something to press.
enum ShareStepState {
  /// Answered. Collapsed to its title and the answer, with a way back.
  done,

  /// The one being worked on.
  current,

  /// Not reachable yet, and [ShareStep.lockedNote] says what would open it.
  waiting,
}

/// One step: its pip, the line down to the next, and everything it asks for.
class ShareStep extends StatelessWidget {
  const ShareStep({
    super.key,
    required this.index,
    required this.state,
    required this.title,
    this.said,
    this.onChange,
    this.changeLabel = 'Change',
    this.blurb,
    this.child,
    this.lockedNote,
    this.isLast = false,
  });

  /// Shown in the pip, one-based. A finished step shows a tick instead — the
  /// number's job is to say how far along this is, and a step that is done has
  /// already answered that.
  final int index;
  final ShareStepState state;
  final String title;

  /// The answer, beside the title, once there is one. This is what lets a
  /// finished step take one line instead of a card.
  final String? said;

  /// Reopens a finished step. Null when there is nothing to change.
  final VoidCallback? onChange;
  final String changeLabel;

  /// Why this step is here, in the reader's terms. One paragraph at most.
  final String? blurb;

  final Widget? child;

  /// What has to be true before a waiting step opens. Drawn under [child],
  /// which a waiting step shows greyed as a preview of what is coming.
  final String? lockedNote;

  final bool isLast;

  bool get _waiting => state == ShareStepState.waiting;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // The stem is a positioned line behind the row rather than a stretched
    // child inside an IntrinsicHeight. Intrinsics are both expensive and
    // fragile here: a step's body holds a picker, the picker measures itself
    // against the width it is given, and a LayoutBuilder cannot answer an
    // intrinsic query — so the version that stretched the stem crashed the
    // moment the model picker appeared inside a step.
    return Stack(
      children: [
        if (!isLast)
          Positioned(
            left: ShareMetrics.pipSize / 2 - 0.5,
            top: ShareMetrics.pipSize + 6,
            bottom: 0,
            width: 1,
            child: ColoredBox(color: SharePalette.stepStem),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Marker(index: index, state: state),
            const SizedBox(width: ShareMetrics.stepGutter),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: isLast ? 4 : ShareMetrics.stepGap,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Head(
                      title: title,
                      said: said,
                      onChange: onChange,
                      changeLabel: changeLabel,
                      dimmed: _waiting,
                    ),
                    if (blurb != null) ...[
                      const SizedBox(height: 7),
                      Text(blurb!, style: ShareType.paneBody),
                    ],
                    if (child != null)
                      // A waiting step still draws its form, greyed. Hiding it
                      // is what the old empty pane did, and it left the reader
                      // unable to see that anything followed the download.
                      _waiting
                          ? IgnorePointer(
                              child: Opacity(opacity: 0.45, child: child),
                            )
                          : child!,
                    if (lockedNote != null) ...[
                      const SizedBox(height: 11),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1, right: 8),
                            child: Icon(
                              LucideIcons.lock300,
                              size: 13,
                              color: SharePalette.helper,
                            ),
                          ),
                          Expanded(
                            child: Text(lockedNote!, style: ShareType.note),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A step's pip. The line down to the next one is drawn by [ShareStep] itself,
/// behind the whole row, so this stays a fixed-size box.
class _Marker extends StatelessWidget {
  const _Marker({required this.index, required this.state});

  final int index;
  final ShareStepState state;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final (fill, rim, ink) = switch (state) {
      ShareStepState.done => (
        SharePalette.stepDoneFill,
        SharePalette.stepDoneRim,
        SharePalette.liveDot,
      ),
      ShareStepState.current => (
        SharePalette.accent,
        SharePalette.accent,
        Colors.white,
      ),
      ShareStepState.waiting => (
        SharePalette.surface,
        SharePalette.fieldRim,
        SharePalette.eyebrow,
      ),
    };
    return Container(
      width: ShareMetrics.pipSize,
      height: ShareMetrics.pipSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: rim),
        shape: BoxShape.circle,
      ),
      child: state == ShareStepState.done
          ? Icon(LucideIcons.check300, size: 12, color: ink)
          : Text(
              '$index',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.0,
                color: ink,
              ),
            ),
    );
  }
}

/// The title, the answer beside it, and the way back into a finished step.
class _Head extends StatelessWidget {
  const _Head({
    required this.title,
    required this.said,
    required this.onChange,
    required this.changeLabel,
    required this.dimmed,
  });

  final String title;
  final String? said;
  final VoidCallback? onChange;
  final String changeLabel;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 2,
            children: [
              Text(
                title,
                style: ShareType.stepTitle.copyWith(
                  color: dimmed ? SharePalette.dim : SharePalette.ink,
                ),
              ),
              if (said != null)
                Text(said!, style: ShareType.note.copyWith(height: 1.0)),
            ],
          ),
        ),
        if (onChange != null) ...[
          const SizedBox(width: 12),
          ShareLink(label: changeLabel, onPressed: onChange!),
        ],
      ],
    );
  }
}

/// The page's one text button: a link that does something here rather than
/// navigating away. Used for Change, for the catalogue, for "where to find your
/// key" — all the same weight, because none of them is the thing to press.
class ShareLink extends StatelessWidget {
  const ShareLink({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: SharePalette.accent,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: const Size(0, 26),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: TextStyle(fontSize: 12, fontWeight: grid.AppFont.semibold),
      ),
      child: Text(label),
    );
  }
}

/// The column the steps live in, bounded so a wide window does not stretch a
/// paragraph past reading width.
class ShareSteps extends StatelessWidget {
  const ShareSteps({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: ShareMetrics.stepMaxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

/// Step 1, which is the same on all three routes and is written once here.
///
/// It is always finished — the reader cannot reach a pane without having picked
/// its route — so it exists to say what was picked, in a sentence rather than
/// as a card the rail already drew.
ShareStep routeChosenStep(ShareRoute route) => ShareStep(
  index: 1,
  state: ShareStepState.done,
  title: 'Route chosen',
  said: switch (route) {
    ShareRoute.local => 'Run a local model on this hardware',
    ShareRoute.key => 'Lend a key you already pay for',
    ShareRoute.server => 'Share an engine already on this computer',
  },
);
