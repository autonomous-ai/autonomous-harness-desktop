import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Room the rail leaves above its first row for the macOS traffic lights.
///
/// With the title bar hidden (`configureDesktopWindow`) the three buttons
/// float over whatever is drawn in the window's top-left corner, so the rail
/// starts below them. The same 32/12 split Grid's sidebar uses, so the two
/// apps' wordmarks sit on one line.
double get railTopInset => Platform.isMacOS ? 32.0 : 12.0;

/// How far a full-width strip drawn at the very top of the window has to
/// start from the left to clear the traffic lights.
double get trafficLightClearance => Platform.isMacOS ? 78.0 : 0.0;

/// The traffic lights' own row, as a drag handle.
const double _dragStripHeight = 28;

/// A strip along the top of a screen that fills the window, so it can still be
/// dragged with the title bar gone. Zero height off macOS, where the native
/// caption bar does this itself.
class WindowDragStrip extends StatelessWidget {
  const WindowDragStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return DragToMoveArea(
      child: SizedBox(
        height: Platform.isMacOS ? _dragStripHeight : 0,
        width: double.infinity,
      ),
    );
  }
}

/// A screen that takes the whole window — sign-in, first-run setup, a forced
/// update — with a drag strip laid over its top edge.
///
/// Overlaid rather than stacked above, so the screen's own centring does not
/// shift by half a strip; these screens centre a card and draw nothing at the
/// top that the lights could cover.
class FullWindowScreen extends StatelessWidget {
  const FullWindowScreen({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        const Positioned(top: 0, left: 0, right: 0, child: WindowDragStrip()),
      ],
    );
  }
}
