import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../shared/theme/app_theme.dart' as grid;


/// How far a full-width strip drawn at the very top of the window has to
/// start from the left to clear the traffic lights.
double get trafficLightClearance => Platform.isMacOS ? 78.0 : 0.0;

/// The traffic lights' own row, as a drag handle.
const double _dragStripHeight = 28;

/// The window's own strip, above everything the app draws.
///
/// ⚠️ THIS IS NOT DECORATION — IT IS WHAT GIVES THE CONTENT BELOW IT ITS INPUT
/// BACK. `TitleBarStyle.hidden` sets `titlebarAppearsTransparent` and
/// `fullSizeContentView`, which does not remove the title bar: it makes it
/// transparent and lets the content run underneath. AppKit still owns dragging
/// in that band, and once it takes a gesture it keeps it — Flutter stops
/// getting move events for it. So anything the app draws in the top ~28px can
/// be looked at but not dragged, which is why dragging a pane's header moved
/// the whole window, and why it worked in full screen: there the window has
/// nowhere to go, so the Flutter drag wins by default.
///
/// [_barHeight] is therefore a floor, not a taste: it must clear
/// [_dragStripHeight]. The extra 4px is what the rail used to inset itself by.
class HarnessTopBar extends StatelessWidget {
  const HarnessTopBar({super.key});

  /// Zero off macOS: there the native caption bar already holds this space, and
  /// a second strip under it would be a gap with nothing in it.
  static double get height => Platform.isMacOS ? 32.0 : 0.0;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) return const SizedBox.shrink();
    grid.AppTheme.watch(context);
    return DragToMoveArea(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: grid.AppPalette.panelBg,
          border: Border(bottom: BorderSide(color: grid.AppGlass.hair)),
        ),
        padding: EdgeInsets.only(left: trafficLightClearance),
        alignment: Alignment.centerLeft,
        child: Text(
          'Harness',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: grid.AppPalette.textSecondary,
          ),
        ),
      ),
    );
  }
}


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
